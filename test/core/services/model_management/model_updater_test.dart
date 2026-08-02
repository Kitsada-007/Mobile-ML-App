import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trffic_ilght_app/core/services/model_management/models/model_manifest.dart';
import 'package:trffic_ilght_app/core/services/model_management/model_file_store.dart';
import 'package:trffic_ilght_app/core/services/model_management/model_registry.dart';
import 'package:trffic_ilght_app/core/services/model_management/model_update_client.dart';
import 'package:trffic_ilght_app/core/services/model_management/model_updater.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('downloads and activates every newer model', () async {
    final preferences = await SharedPreferences.getInstance();
    final registry = ModelRegistry(preferences);
    final downloader = _FakeDownloader();
    final updater = ModelUpdater(
      _FakeManifestSource(_manifest()),
      downloader,
      registry,
      currentAppVersion: '1.1.2',
    );

    final report = await updater.checkForUpdates();

    expect(report.results['traffic']!.status, ModelUpdateStatus.updated);
    expect(report.results['number']!.status, ModelUpdateStatus.updated);
    expect(downloader.downloadedIds, <String>['traffic', 'number']);
    expect((await registry.getActive('traffic'))!.version, '1.2.0');
  });

  test('does not download a model that is already current', () async {
    final preferences = await SharedPreferences.getInstance();
    final registry = ModelRegistry(preferences);
    await registry.activate(
      'traffic',
      const StoredModelRecord(
        version: '1.2.0',
        path: 'C:/models/traffic.tflite',
        sha256: _shaA,
        sizeBytes: 1000,
      ),
    );
    await registry.activate(
      'number',
      const StoredModelRecord(
        version: '1.2.0',
        path: 'C:/models/number.tflite',
        sha256: _shaB,
        sizeBytes: 1000,
      ),
    );
    final downloader = _FakeDownloader();
    final updater = ModelUpdater(
      _FakeManifestSource(_manifest()),
      downloader,
      registry,
      currentAppVersion: '1.1.2',
    );

    final report = await updater.checkForUpdates();

    expect(
      report.results.values.map((result) => result.status),
      everyElement(ModelUpdateStatus.alreadyCurrent),
    );
    expect(downloader.downloadedIds, isEmpty);
  });

  test('rejects a manifest requiring a newer app version', () async {
    final preferences = await SharedPreferences.getInstance();
    final downloader = _FakeDownloader();
    final updater = ModelUpdater(
      _FakeManifestSource(_manifest(minimumAppVersion: '2.0.0')),
      downloader,
      ModelRegistry(preferences),
      currentAppVersion: '1.1.2',
    );

    final report = await updater.checkForUpdates();

    expect(
      report.results.values.map((result) => result.status),
      everyElement(ModelUpdateStatus.incompatible),
    );
    expect(downloader.downloadedIds, isEmpty);
  });

  test('keeps updating other models when one download fails', () async {
    final preferences = await SharedPreferences.getInstance();
    final registry = ModelRegistry(preferences);
    final downloader = _FakeDownloader(failingModelId: 'traffic');
    final updater = ModelUpdater(
      _FakeManifestSource(_manifest()),
      downloader,
      registry,
      currentAppVersion: '1.1.2',
    );

    final report = await updater.checkForUpdates();

    expect(report.results['traffic']!.status, ModelUpdateStatus.failed);
    expect(report.results['number']!.status, ModelUpdateStatus.updated);
    expect(await registry.getActive('traffic'), isNull);
    expect(await registry.getActive('number'), isNotNull);
  });

  test(
    'coalesces concurrent update checks into one manifest request',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final source = _DelayedManifestSource(_manifest());
      final updater = ModelUpdater(
        source,
        _FakeDownloader(),
        ModelRegistry(preferences),
        currentAppVersion: '1.1.2',
      );

      final first = updater.checkForUpdates();
      final second = updater.checkForUpdates();
      source.complete();
      await Future.wait(<Future<ModelUpdateReport>>[first, second]);

      expect(source.fetchCount, 1);
    },
  );

  test(
    'returns a failure report when the manifest cannot be fetched',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final updater = ModelUpdater(
        _FailingManifestSource(),
        _FakeDownloader(),
        ModelRegistry(preferences),
        currentAppVersion: '1.1.2',
      );

      final report = await updater.checkForUpdates();

      expect(report.manifestChecked, isFalse);
      expect(report.error, isA<ModelManifestFetchException>());
      expect(report.results, isEmpty);
    },
  );

  test(
    'does not redownload a model version rejected by the YOLO runtime',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final registry = ModelRegistry(preferences);
      await registry.markVersionFailed('traffic', '1.2.0');
      final downloader = _FakeDownloader();
      final updater = ModelUpdater(
        _FakeManifestSource(_manifest()),
        downloader,
        registry,
        currentAppVersion: '1.1.2',
      );

      final report = await updater.checkForUpdates();

      expect(report.results['traffic']!.status, ModelUpdateStatus.failed);
      expect(downloader.downloadedIds, isNot(contains('traffic')));
      expect(report.results['number']!.status, ModelUpdateStatus.updated);
    },
  );
}

class _FakeManifestSource implements ModelManifestSource {
  _FakeManifestSource(this.manifest);

  final ModelManifest manifest;

  @override
  Future<ModelManifest> fetchLatestManifest() async => manifest;
}

class _DelayedManifestSource implements ModelManifestSource {
  _DelayedManifestSource(this.manifest);

  final ModelManifest manifest;
  final Completer<void> _gate = Completer<void>();
  int fetchCount = 0;

  void complete() => _gate.complete();

  @override
  Future<ModelManifest> fetchLatestManifest() async {
    fetchCount++;
    await _gate.future;
    return manifest;
  }
}

class _FailingManifestSource implements ModelManifestSource {
  @override
  Future<ModelManifest> fetchLatestManifest() {
    throw const ModelManifestFetchException('offline');
  }
}

class _FakeDownloader implements ModelDownloader {
  _FakeDownloader({this.failingModelId});

  final String? failingModelId;
  final List<String> downloadedIds = <String>[];

  @override
  Future<File> downloadModel({
    required String modelId,
    required RemoteModelInfo model,
  }) async {
    downloadedIds.add(modelId);
    if (modelId == failingModelId) {
      throw const ModelDownloadException('simulated failure');
    }
    return File('C:/downloaded/$modelId/${model.fileName}');
  }
}

ModelManifest _manifest({String minimumAppVersion = '1.1.2'}) {
  return ModelManifest.fromJson(<String, dynamic>{
    'schemaVersion': 1,
    'releaseVersion': '1.2.0',
    'minimumAppVersion': minimumAppVersion,
    'models': <String, dynamic>{
      'traffic': <String, dynamic>{
        'version': '1.2.0',
        'fileName': 'traffic_model_v1_2_0.tflite',
        'url':
            'https://github.com/Kitsada-007/Mobile-ML-App/releases/download/'
            'model-v1.2.0/traffic_model_v1_2_0.tflite',
        'sha256': _shaA,
        'sizeBytes': 1000,
      },
      'number': <String, dynamic>{
        'version': '1.2.0',
        'fileName': 'number_model_v1_2_0.tflite',
        'url':
            'https://github.com/Kitsada-007/Mobile-ML-App/releases/download/'
            'model-v1.2.0/number_model_v1_2_0.tflite',
        'sha256': _shaB,
        'sizeBytes': 1000,
      },
    },
  });
}

const _shaA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _shaB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
