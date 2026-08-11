import 'package:trffic_ilght_app/core/services/model_management/models/model_manifest.dart';
import 'package:trffic_ilght_app/core/services/model_management/models/semantic_version.dart';
import 'package:trffic_ilght_app/core/services/model_management/model_file_store.dart';
import 'package:trffic_ilght_app/core/services/model_management/model_registry.dart';
import 'package:trffic_ilght_app/core/services/model_management/model_update_client.dart';

/// สถานะการอัปเดตของแต่ละโมเดล
enum ModelUpdateStatus {
  updated, // อัปเดตเป็นเวอร์ชันใหม่แล้ว
  alreadyCurrent, // เป็นเวอร์ชันล่าสุดอยู่แล้ว
  incompatible, // แอปเวอร์ชันต่ำเกินไป ไม่รองรับ manifest นี้
  failed, // อัปเดตไม่สำเร็จ
}

/// ผลการอัปเดตของโมเดลหนึ่งตัว
class ModelUpdateItemResult {
  const ModelUpdateItemResult({
    required this.status,
    required this.version,
    this.error,
  });

  final ModelUpdateStatus status;
  final String version;
  final Object? error;
}

/// รายงานผลการตรวจอัปเดตทั้งหมด (ครบทุกโมเดล)
class ModelUpdateReport {
  const ModelUpdateReport({required this.results, this.error});

  final Map<String, ModelUpdateItemResult> results;
  final Object? error;

  /// ตรวจ manifest สำเร็จหรือไม่ (ไม่มี error ระดับ top-level)
  bool get manifestChecked => error == null;
}

/// เช็คอัปเดตโมเดลจากระยะไกลและดาวน์โหลดเวอร์ชันใหม่
/// - เปรียบเทียบเวอร์ชันโมเดลที่ใช้งานอยู่กับเวอร์ชันล่าสุด
/// - ตรวจ minimumAppVersion (แอปเก่าเกินไป = incompatible)
/// - กันรันซ้ำพร้อมกัน (in-flight) และกันดาวน์โหลดเวอร์ชันที่เคย fail
class ModelUpdater {
  ModelUpdater(
    this._manifestSource,
    this._downloader,
    this._registry, {
    required String currentAppVersion,
    this.modelIds = const <String>['traffic', 'number'],
  }) : _currentAppVersion = SemanticVersion.parse(currentAppVersion);

  final ModelManifestSource _manifestSource;
  final ModelDownloader _downloader;
  final ActiveModelRegistry _registry;
  final SemanticVersion _currentAppVersion;
  final List<String> modelIds;

  Future<ModelUpdateReport>? _inFlight;

  /// เริ่มเช็คอัปเดต (ถ้ามีการเช็คอยู่แล้ว จะใช้ผลเดียวกัน)
  Future<ModelUpdateReport> checkForUpdates() {
    final running = _inFlight;
    if (running != null) return running;

    final future = _performCheck();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<ModelUpdateReport> _performCheck() async {
    final ModelManifest manifest;
    try {
      manifest = await _manifestSource.fetchLatestManifest();
    } catch (error) {
      return ModelUpdateReport(
        results: const <String, ModelUpdateItemResult>{},
        error: error,
      );
    }

    final minimumVersion = SemanticVersion.parse(manifest.minimumAppVersion);
    if (_currentAppVersion < minimumVersion) {
      return ModelUpdateReport(
        results: Map<String, ModelUpdateItemResult>.unmodifiable(
          <String, ModelUpdateItemResult>{
            for (final modelId in modelIds)
              modelId: ModelUpdateItemResult(
                status: ModelUpdateStatus.incompatible,
                version: manifest.models[modelId]!.version,
              ),
          },
        ),
      );
    }

    final results = <String, ModelUpdateItemResult>{};
    for (final modelId in modelIds) {
      final remote = manifest.models[modelId]!;
      try {
        if (await _registry.isVersionFailed(modelId, remote.version)) {
          throw StateError(
            'Model $modelId version ${remote.version} previously failed to load',
          );
        }

        final active = await _registry.getActive(modelId);
        final remoteVersion = SemanticVersion.parse(remote.version);
        if (active != null &&
            SemanticVersion.parse(active.version) >= remoteVersion) {
          results[modelId] = ModelUpdateItemResult(
            status: ModelUpdateStatus.alreadyCurrent,
            version: active.version,
          );
          continue;
        }

        final downloaded = await _downloader.downloadModel(
          modelId: modelId,
          model: remote,
        );
        await _registry.activate(
          modelId,
          StoredModelRecord(
            version: remote.version,
            path: downloaded.path,
            sha256: remote.sha256,
            sizeBytes: remote.sizeBytes,
          ),
        );
        results[modelId] = ModelUpdateItemResult(
          status: ModelUpdateStatus.updated,
          version: remote.version,
        );
      } catch (error) {
        results[modelId] = ModelUpdateItemResult(
          status: ModelUpdateStatus.failed,
          version: remote.version,
          error: error,
        );
      }
    }

    return ModelUpdateReport(
      results: Map<String, ModelUpdateItemResult>.unmodifiable(results),
    );
  }
}
