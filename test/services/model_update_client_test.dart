import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trffic_ilght_app/services/model_update_client.dart';

void main() {
  final manifestUri = Uri.parse(
    'https://github.com/Kitsada-007/Mobile-ML-App/'
    'releases/latest/download/model_manifest.json',
  );

  test('fetchLatestManifest parses a valid HTTP 200 response', () async {
    final httpClient = MockClient((request) async {
      expect(request.url, manifestUri);
      return http.Response(jsonEncode(_validManifest()), 200);
    });
    final client = ModelUpdateClient(httpClient, manifestUri: manifestUri);

    final manifest = await client.fetchLatestManifest();

    expect(manifest.releaseVersion, '1.2.0');
    expect(manifest.models['traffic']!.version, '1.2.0');
  });

  test('fetchLatestManifest rejects a non-200 response', () async {
    final client = ModelUpdateClient(
      MockClient((_) async => http.Response('Not Found', 404)),
      manifestUri: manifestUri,
    );

    await expectLater(
      client.fetchLatestManifest(),
      throwsA(
        isA<ModelManifestFetchException>().having(
          (error) => error.message,
          'message',
          contains('HTTP 404'),
        ),
      ),
    );
  });

  test('fetchLatestManifest enforces the streamed response size limit', () {
    final client = ModelUpdateClient(
      MockClient((_) async => http.Response('x' * 64, 200)),
      manifestUri: manifestUri,
      maximumManifestSizeBytes: 32,
    );

    expect(
      client.fetchLatestManifest(),
      throwsA(isA<ModelManifestFetchException>()),
    );
  });

  test('fetchLatestManifest wraps invalid JSON as a typed failure', () {
    final client = ModelUpdateClient(
      MockClient((_) async => http.Response('{invalid', 200)),
      manifestUri: manifestUri,
    );

    expect(
      client.fetchLatestManifest(),
      throwsA(isA<ModelManifestFetchException>()),
    );
  });
}

Map<String, dynamic> _validManifest() {
  return <String, dynamic>{
    'schemaVersion': 1,
    'releaseVersion': '1.2.0',
    'minimumAppVersion': '1.1.2',
    'models': <String, dynamic>{
      'traffic': <String, dynamic>{
        'version': '1.2.0',
        'fileName': 'traffic_model_v1_2_0.tflite',
        'url':
            'https://github.com/Kitsada-007/Mobile-ML-App/releases/download/'
            'model-v1.2.0/traffic_model_v1_2_0.tflite',
        'sha256': 'a' * 64,
        'sizeBytes': 1000,
      },
      'number': <String, dynamic>{
        'version': '1.2.0',
        'fileName': 'number_model_v1_2_0.tflite',
        'url':
            'https://github.com/Kitsada-007/Mobile-ML-App/releases/download/'
            'model-v1.2.0/number_model_v1_2_0.tflite',
        'sha256': 'b' * 64,
        'sizeBytes': 1000,
      },
    },
  };
}
