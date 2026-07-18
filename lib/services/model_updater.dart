import 'package:trffic_ilght_app/core/models/model_manifest.dart';
import 'package:trffic_ilght_app/core/models/semantic_version.dart';
import 'package:trffic_ilght_app/services/model_file_store.dart';
import 'package:trffic_ilght_app/services/model_registry.dart';
import 'package:trffic_ilght_app/services/model_update_client.dart';

enum ModelUpdateStatus { updated, alreadyCurrent, incompatible, failed }

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

class ModelUpdateReport {
  const ModelUpdateReport({required this.results, this.error});

  final Map<String, ModelUpdateItemResult> results;
  final Object? error;

  bool get manifestChecked => error == null;
}

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
