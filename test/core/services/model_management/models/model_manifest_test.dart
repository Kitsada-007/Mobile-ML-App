import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/core/services/model_management/models/model_manifest.dart';

void main() {
  group('ModelManifest.fromJson', () {
    test('parses a valid YOLO model manifest', () {
      final manifest = ModelManifest.fromJson(_validManifest());

      expect(manifest.schemaVersion, 1);
      expect(manifest.releaseVersion, '1.2.0');
      expect(manifest.minimumAppVersion, '1.1.2');
      expect(manifest.models.keys, containsAll(<String>['traffic', 'number']));
      expect(
        manifest.models['traffic']!.fileName,
        'traffic_model_v1_2_0.tflite',
      );
    });

    test('rejects an unsupported schema version', () {
      final json = _validManifest()..['schemaVersion'] = 2;

      expect(() => ModelManifest.fromJson(json), throwsFormatException);
    });

    test('rejects a missing required model', () {
      final json = _validManifest();
      (json['models']! as Map<String, dynamic>).remove('number');

      expect(() => ModelManifest.fromJson(json), throwsFormatException);
    });

    test('rejects an HTTP model URL', () {
      final json = _validManifest();
      final traffic =
          (json['models']! as Map<String, dynamic>)['traffic']!
              as Map<String, dynamic>;
      traffic['url'] =
          'http://github.com/Kitsada-007/Mobile-ML-App/releases/download/'
          'model-v1.2.0/traffic_model_v1_2_0.tflite';

      expect(() => ModelManifest.fromJson(json), throwsFormatException);
    });

    test('rejects a file name containing path traversal', () {
      final json = _validManifest();
      final traffic =
          (json['models']! as Map<String, dynamic>)['traffic']!
              as Map<String, dynamic>;
      traffic['fileName'] = '../traffic_model.tflite';

      expect(() => ModelManifest.fromJson(json), throwsFormatException);
    });

    test('rejects an invalid SHA-256 digest', () {
      final json = _validManifest();
      final traffic =
          (json['models']! as Map<String, dynamic>)['traffic']!
              as Map<String, dynamic>;
      traffic['sha256'] = 'not-a-sha256';

      expect(() => ModelManifest.fromJson(json), throwsFormatException);
    });

    test('rejects a model larger than the configured maximum', () {
      final json = _validManifest();
      final traffic =
          (json['models']! as Map<String, dynamic>)['traffic']!
              as Map<String, dynamic>;
      traffic['sizeBytes'] = RemoteModelInfo.maximumModelSizeBytes + 1;

      expect(() => ModelManifest.fromJson(json), throwsFormatException);
    });
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
