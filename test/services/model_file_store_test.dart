import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trffic_ilght_app/core/models/model_manifest.dart';
import 'package:trffic_ilght_app/services/model_file_store.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'model-file-store-test-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('downloads, verifies, and atomically publishes a model', () async {
    final modelBytes = <int>[1, 2, 3, 4, 5];
    final model = _remoteModel(
      sizeBytes: modelBytes.length,
      sha: sha256.convert(modelBytes).toString(),
    );
    final store = ModelFileStore(
      MockClient((_) async => http.Response.bytes(modelBytes, 200)),
      rootDirectoryProvider: () async => temporaryDirectory,
    );

    final downloadedFile = await store.downloadModel(
      modelId: 'traffic',
      model: model,
    );

    expect(await downloadedFile.readAsBytes(), modelBytes);
    expect(await File('${downloadedFile.path}.part').exists(), isFalse);
    expect(
      await store.verifyFile(
        downloadedFile,
        expectedSha256: model.sha256,
        expectedSizeBytes: model.sizeBytes,
      ),
      isTrue,
    );
  });

  test('deletes the partial file when the checksum does not match', () async {
    final modelBytes = <int>[1, 2, 3, 4, 5];
    final store = ModelFileStore(
      MockClient((_) async => http.Response.bytes(modelBytes, 200)),
      rootDirectoryProvider: () async => temporaryDirectory,
    );

    await expectLater(
      store.downloadModel(
        modelId: 'traffic',
        model: _remoteModel(sizeBytes: modelBytes.length, sha: '0' * 64),
      ),
      throwsA(isA<ModelDownloadException>()),
    );

    final files = temporaryDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .toList();
    expect(files, isEmpty);
  });

  test('rejects a response whose byte count differs from the manifest', () {
    final modelBytes = <int>[1, 2, 3];
    final store = ModelFileStore(
      MockClient((_) async => http.Response.bytes(modelBytes, 200)),
      rootDirectoryProvider: () async => temporaryDirectory,
    );

    expect(
      store.downloadModel(
        modelId: 'number',
        model: _remoteModel(
          sizeBytes: modelBytes.length + 1,
          sha: sha256.convert(modelBytes).toString(),
        ),
      ),
      throwsA(isA<ModelDownloadException>()),
    );
  });

  test('rejects a non-200 model response', () {
    final store = ModelFileStore(
      MockClient((_) async => http.Response('Not Found', 404)),
      rootDirectoryProvider: () async => temporaryDirectory,
    );

    expect(
      store.downloadModel(
        modelId: 'traffic',
        model: _remoteModel(sizeBytes: 1, sha: '0' * 64),
      ),
      throwsA(isA<ModelDownloadException>()),
    );
  });

  test('rejects a download URL outside the configured GitHub repository', () {
    final store = ModelFileStore(
      MockClient((_) async => http.Response.bytes(<int>[1], 200)),
      rootDirectoryProvider: () async => temporaryDirectory,
    );
    final model = _remoteModel(sizeBytes: 1, sha: '0' * 64);

    expect(
      store.downloadModel(
        modelId: 'traffic',
        model: RemoteModelInfo(
          version: model.version,
          fileName: model.fileName,
          url: Uri.parse(
            'https://github.com/attacker/repository/releases/download/'
            'model-v1.2.0/${model.fileName}',
          ),
          sha256: model.sha256,
          sizeBytes: model.sizeBytes,
        ),
      ),
      throwsA(
        isA<ModelDownloadException>().having(
          (error) => error.message,
          'message',
          'Invalid model download URL',
        ),
      ),
    );
  });

  test('rejects a URL whose asset name differs from the manifest', () {
    final store = ModelFileStore(
      MockClient((_) async => http.Response.bytes(<int>[1], 200)),
      rootDirectoryProvider: () async => temporaryDirectory,
    );
    final model = _remoteModel(sizeBytes: 1, sha: '0' * 64);

    expect(
      store.downloadModel(
        modelId: 'traffic',
        model: RemoteModelInfo(
          version: model.version,
          fileName: model.fileName,
          url: Uri.parse(
            'https://github.com/Kitsada-007/Mobile-ML-App/releases/download/'
            'model-v1.2.0/different.tflite',
          ),
          sha256: model.sha256,
          sizeBytes: model.sizeBytes,
        ),
      ),
      throwsA(
        isA<ModelDownloadException>().having(
          (error) => error.message,
          'message',
          'Invalid model download URL',
        ),
      ),
    );
  });
}

RemoteModelInfo _remoteModel({required int sizeBytes, required String sha}) {
  return RemoteModelInfo(
    version: '1.2.0',
    fileName: 'traffic_model_v1_2_0.tflite',
    url: Uri.parse(
      'https://github.com/Kitsada-007/Mobile-ML-App/releases/download/'
      'model-v1.2.0/traffic_model_v1_2_0.tflite',
    ),
    sha256: sha,
    sizeBytes: sizeBytes,
  );
}
