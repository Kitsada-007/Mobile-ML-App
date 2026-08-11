import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trffic_ilght_app/shared/models/model_types.dart';
import 'package:trffic_ilght_app/core/services/model_management/model_file_store.dart';
import 'package:trffic_ilght_app/core/services/model_management/model_registry.dart';
import 'package:ultralytics_yolo/config/channel_config.dart';

/// โหลดโมเดลที่ฝังมากับแอป (asset) : คืน bytes
typedef BundledModelLoader = Future<Uint8List> Function(String assetPath);

/// ค้นหาโมเดล native (ผ่าน platform channel) : คืน path หรือ null
typedef NativeModelLookup = Future<String?> Function(String assetPath);

/// ตัวจัดการโมเดล YOLO:
/// - ใช้โมเดลที่ดาวน์โหลดและตรวจสอบแล้วก่อน (registry)
/// - ถ้าไม่มีหรือใช้ไม่ได้ -> ถอยกลับไปใช้โมเดลที่ฝังในแอป
/// - มีระบบโหลดโมเดลที่ล้มเหลว -> ย้อนกลับรุ่นก่อนหน้าอัตโนมัติ
class ModelManager {
  ModelManager({
    this.onStatusUpdate,
    ActiveModelRegistry? registry,
    bool? isAndroid,
    RootDirectoryProvider? rootDirectoryProvider,
    BundledModelLoader? bundledModelLoader,
    NativeModelLookup? nativeModelLookup,
  }) : _providedRegistry = registry,
       _isAndroid = isAndroid ?? Platform.isAndroid,
       _rootDirectoryProvider =
           rootDirectoryProvider ?? getApplicationDocumentsDirectory,
       _bundledModelLoader = bundledModelLoader ?? _loadBundledAsset,
       _nativeModelLookup = nativeModelLookup ?? _lookupNativeModel;

  static final MethodChannel _channel =
      ChannelConfig.createSingleImageChannel();

  final void Function(String message)? onStatusUpdate;
  final ActiveModelRegistry? _providedRegistry;
  final bool _isAndroid;
  final RootDirectoryProvider _rootDirectoryProvider;
  final BundledModelLoader _bundledModelLoader;
  final NativeModelLookup _nativeModelLookup;

  Future<ActiveModelRegistry>? _registryFuture;

  /// คืน path ของโมเดลที่ควรใช้ (ดาวน์โหลดแล้ว -> ถ้าไม่มี ใช้แบบฝังในแอป)
  Future<String?> getModelPath(ModelType modelType) async {
    if (!_isAndroid) {
      _updateStatus('แอปพลิเคชันนี้รองรับโมเดลเฉพาะระบบ Android');
      return null;
    }

    _updateStatus('กำลังตรวจสอบโมเดล ${modelType.remoteId}...');
    final downloadedPath = await _resolveDownloadedModel(modelType);
    if (downloadedPath != null) {
      _updateStatus('กำลังใช้โมเดล ${modelType.remoteId} ที่อัปเดตแล้ว');
      return downloadedPath;
    }

    return _resolveBundledModel(modelType);
  }

  /// ใช้เมื่อโมเดลที่ดาวน์โหลดโหลดไม่ขึ้น (runtime error)
  /// - marks โมเดลนั้นว่า failed
  /// - คืนโมเดลรุ่นก่อนหน้าที่ตรวจสอบแล้ว หรือ fallback เป็นแบบฝังในแอป
  Future<String?> reportModelLoadFailure(
    ModelType modelType, {
    required String failedPath,
  }) async {
    final registry = await _getRegistry();
    await registry.markActiveFailed(modelType.remoteId, failedPath: failedPath);

    final replacement = await _resolveDownloadedModel(modelType);
    if (replacement != null) {
      _updateStatus('ย้อนกลับไปใช้โมเดล ${modelType.remoteId} รุ่นก่อนหน้า');
      return replacement;
    }
    return _resolveBundledModel(modelType);
  }

  /// ค้นหาโมเดลที่ดาวน์โหลดมาและตรวจสอบว่าไฟล์ยัง valid (ขนาด + SHA-256)
  Future<String?> _resolveDownloadedModel(ModelType modelType) async {
    final registry = await _getRegistry();
    var active = await registry.getActive(modelType.remoteId);

    // At most active + previous can be examined during one resolution.
    for (var attempt = 0; attempt < 2 && active != null; attempt++) {
      final file = File(active.path);
      final valid = await verifyModelFile(
        file,
        expectedSha256: active.sha256,
        expectedSizeBytes: active.sizeBytes,
      );
      if (valid) return file.path;

      active = await registry.markActiveFailed(
        modelType.remoteId,
        failedPath: active.path,
        preventRetry: false,
      );
    }
    return null;
  }

  /// เตรียมโมเดลที่ฝังในแอป (native path หรือ copy ลง documents)
  Future<String?> _resolveBundledModel(ModelType modelType) async {
    try {
      final nativePath = await _nativeModelLookup(modelType.modelName);
      if (nativePath != null) return nativePath;
    } catch (_) {
      // Some plugin versions do not expose the optional lookup method.
    }

    try {
      _updateStatus('กำลังเตรียมโมเดล ${modelType.remoteId} จากแอป...');
      final root = await _rootDirectoryProvider();
      final directory = Directory(
        '${root.path}${Platform.pathSeparator}bundled_models',
      );
      await directory.create(recursive: true);

      final fileName = modelType.modelName.split('/').last;
      final modelFile = File(
        '${directory.path}${Platform.pathSeparator}$fileName',
      );
      if (!await modelFile.exists()) {
        final bytes = await _bundledModelLoader(modelType.modelName);
        await modelFile.writeAsBytes(bytes, flush: true);
      }
      return modelFile.path;
    } catch (error) {
      debugPrint(
        'Unable to prepare bundled ${modelType.remoteId} model: $error',
      );
      return null;
    }
  }

  /// รับ registry (จากที่ส่งเข้ามา หรือสร้างจาก SharedPreferences เอง)
  Future<ActiveModelRegistry> _getRegistry() {
    final provided = _providedRegistry;
    if (provided != null) return Future<ActiveModelRegistry>.value(provided);

    return _registryFuture ??= SharedPreferences.getInstance().then(
      (preferences) => ModelRegistry(preferences),
    );
  }

  /// โหลด asset ที่ฝังในแอปเป็น bytes
  static Future<Uint8List> _loadBundledAsset(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  /// ถาม native ว่าโมเดลใน asset มีอยู่จริงและอยู่ที่ไหน
  static Future<String?> _lookupNativeModel(String assetPath) async {
    final result = await _channel.invokeMethod<dynamic>(
      'checkModelExists',
      <String, dynamic>{'modelPath': assetPath},
    );
    if (result is! Map || result['exists'] != true) return null;
    if (result['location'] == 'assets') return assetPath;
    final path = result['path'];
    return path is String && path.isNotEmpty ? path : null;
  }

  void _updateStatus(String message) => onStatusUpdate?.call(message);
}
