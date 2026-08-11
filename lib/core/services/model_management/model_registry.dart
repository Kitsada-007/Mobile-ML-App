import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:trffic_ilght_app/core/services/model_management/models/semantic_version.dart';

/// ทะเบียนโมเดลที่ใช้งานอยู่/ก่อนหน้า เก็บไว้ใน SharedPreferences
/// - ติดตามโมเดลที่กำลังใช้ (active) และรุ่นก่อนหน้า (previous) ต่อ modelId
/// - จำบันทึกเวอร์ชันที่โหลดไม่สำเร็จ เพื่อไม่ให้ดาวน์โหลดซ้ำเดิม
abstract interface class ActiveModelRegistry {
  Future<StoredModelRecord?> getActive(String modelId);

  Future<StoredModelRecord?> getPrevious(String modelId);

  Future<void> activate(String modelId, StoredModelRecord model);

  Future<bool> isVersionFailed(String modelId, String version);

  Future<void> markVersionFailed(String modelId, String version);

  Future<StoredModelRecord?> markActiveFailed(
    String modelId, {
    required String failedPath,
    bool preventRetry = true,
  });
}

/// Implementation จริงของ ActiveModelRegistry เก็บข้อมูลเป็น JSON ใน preferences
class ModelRegistry implements ActiveModelRegistry {
  ModelRegistry(this._preferences);

  final SharedPreferences _preferences;

  @override
  Future<StoredModelRecord?> getActive(String modelId) {
    return _readRecord(modelId, _Slot.active);
  }

  @override
  Future<StoredModelRecord?> getPrevious(String modelId) {
    return _readRecord(modelId, _Slot.previous);
  }

  @override
  Future<void> activate(String modelId, StoredModelRecord model) async {
    _validateModelId(modelId);
    model.validate();

    final current = await getActive(modelId);
    if (current != null && current != model) {
      await _writeRecord(modelId, _Slot.previous, current);
    }
    await _writeRecord(modelId, _Slot.active, model);
  }

  @override
  Future<bool> isVersionFailed(String modelId, String version) async {
    _validateModelId(modelId);
    SemanticVersion.parse(version);

    final key = _failedVersionKey(modelId);
    final failedVersion = _preferences.getString(key);
    if (failedVersion == null) return false;

    try {
      SemanticVersion.parse(failedVersion);
    } catch (_) {
      await _preferences.remove(key);
      return false;
    }
    return failedVersion == version;
  }

  @override
  Future<void> markVersionFailed(String modelId, String version) async {
    _validateModelId(modelId);
    SemanticVersion.parse(version);
    final written = await _preferences.setString(
      _failedVersionKey(modelId),
      version,
    );
    if (!written) {
      throw StateError('Unable to persist the failed $modelId model version');
    }
  }

  @override
  Future<StoredModelRecord?> markActiveFailed(
    String modelId, {
    required String failedPath,
    bool preventRetry = true,
  }) async {
    _validateModelId(modelId);
    final active = await getActive(modelId);
    if (active == null || active.path != failedPath) return active;

    if (preventRetry) {
      await markVersionFailed(modelId, active.version);
    }

    final previous = await getPrevious(modelId);
    if (previous == null) {
      await _preferences.remove(_key(modelId, _Slot.active));
      return null;
    }

    await _writeRecord(modelId, _Slot.active, previous);
    await _preferences.remove(_key(modelId, _Slot.previous));
    return previous;
  }

  /// อ่าน record จาก preferences (ถ้า JSON เสีย -> ลบทิ้งแล้วคืน null)
  Future<StoredModelRecord?> _readRecord(String modelId, _Slot slot) async {
    _validateModelId(modelId);
    final key = _key(modelId, slot);

    try {
      final encoded = _preferences.getString(key);
      if (encoded == null) return null;
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) throw const FormatException('Invalid record');
      return StoredModelRecord.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      await _preferences.remove(key);
      return null;
    }
  }

  /// เขียน record ลง preferences (ตรวจสอบก่อนเสมอ)
  Future<void> _writeRecord(
    String modelId,
    _Slot slot,
    StoredModelRecord record,
  ) async {
    record.validate();
    final written = await _preferences.setString(
      _key(modelId, slot),
      jsonEncode(record.toJson()),
    );
    if (!written) {
      throw StateError('Unable to persist the $modelId model registry');
    }
  }

  String _key(String modelId, _Slot slot) {
    return 'remote_models.$modelId.${slot.name}';
  }

  String _failedVersionKey(String modelId) {
    return 'remote_models.$modelId.failed_version';
  }

  void _validateModelId(String modelId) {
    if (!RegExp(r'^[a-z][a-z0-9_-]*$').hasMatch(modelId)) {
      throw ArgumentError.value(modelId, 'modelId', 'Invalid model id');
    }
  }
}

enum _Slot { active, previous }

/// บันทึกข้อมูลโมเดลที่เก็บไว้ (ทั้ง active และ previous)
class StoredModelRecord {
  const StoredModelRecord({
    required this.version,
    required this.path,
    required this.sha256,
    required this.sizeBytes,
  });

  final String version;
  final String path;
  final String sha256;
  final int sizeBytes;

  factory StoredModelRecord.fromJson(Map<String, dynamic> json) {
    final record = StoredModelRecord(
      version: json['version'] as String,
      path: json['path'] as String,
      sha256: json['sha256'] as String,
      sizeBytes: json['sizeBytes'] as int,
    );
    record.validate();
    return record;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': version,
    'path': path,
    'sha256': sha256,
    'sizeBytes': sizeBytes,
  };

  void validate() {
    SemanticVersion.parse(version);
    if (path.trim().isEmpty || !path.toLowerCase().endsWith('.tflite')) {
      throw const FormatException('Invalid stored model path');
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException('Invalid stored model SHA-256');
    }
    if (sizeBytes <= 0) {
      throw const FormatException('Invalid stored model size');
    }
  }

  @override
  bool operator ==(Object other) {
    return other is StoredModelRecord &&
        version == other.version &&
        path == other.path &&
        sha256 == other.sha256 &&
        sizeBytes == other.sizeBytes;
  }

  @override
  int get hashCode => Object.hash(version, path, sha256, sizeBytes);
}
