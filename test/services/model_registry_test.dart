import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trffic_ilght_app/services/model_registry.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('activate keeps the former active model as previous', () async {
    final preferences = await SharedPreferences.getInstance();
    final registry = ModelRegistry(preferences);
    const oldModel = StoredModelRecord(
      version: '1.1.0',
      path: 'C:/models/traffic-1.1.0.tflite',
      sha256: _shaA,
      sizeBytes: 100,
    );
    const newModel = StoredModelRecord(
      version: '1.2.0',
      path: 'C:/models/traffic-1.2.0.tflite',
      sha256: _shaB,
      sizeBytes: 120,
    );

    await registry.activate('traffic', oldModel);
    await registry.activate('traffic', newModel);

    expect(await registry.getActive('traffic'), newModel);
    expect(await registry.getPrevious('traffic'), oldModel);
  });

  test(
    'rollback promotes the previous model and removes the failed one',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final registry = ModelRegistry(preferences);
      const oldModel = StoredModelRecord(
        version: '1.1.0',
        path: 'C:/models/traffic-1.1.0.tflite',
        sha256: _shaA,
        sizeBytes: 100,
      );
      const failedModel = StoredModelRecord(
        version: '1.2.0',
        path: 'C:/models/traffic-1.2.0.tflite',
        sha256: _shaB,
        sizeBytes: 120,
      );
      await registry.activate('traffic', oldModel);
      await registry.activate('traffic', failedModel);

      final restored = await registry.markActiveFailed(
        'traffic',
        failedPath: failedModel.path,
      );

      expect(restored, oldModel);
      expect(await registry.getActive('traffic'), oldModel);
      expect(await registry.getPrevious('traffic'), isNull);
      expect(await registry.isVersionFailed('traffic', '1.2.0'), isTrue);
    },
  );

  test('ignores and removes a corrupted registry record', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'remote_models.traffic.active': '{not-json',
    });
    final preferences = await SharedPreferences.getInstance();
    final registry = ModelRegistry(preferences);

    expect(await registry.getActive('traffic'), isNull);
    expect(preferences.containsKey('remote_models.traffic.active'), isFalse);
  });

  test(
    'does not roll back when the failed path is not currently active',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final registry = ModelRegistry(preferences);
      const active = StoredModelRecord(
        version: '1.2.0',
        path: 'C:/models/traffic-1.2.0.tflite',
        sha256: _shaB,
        sizeBytes: 120,
      );
      await registry.activate('traffic', active);

      final result = await registry.markActiveFailed(
        'traffic',
        failedPath: 'C:/models/some-other-file.tflite',
      );

      expect(result, active);
      expect(await registry.getActive('traffic'), active);
    },
  );

  test('can roll back corruption without blacklisting its version', () async {
    final preferences = await SharedPreferences.getInstance();
    final registry = ModelRegistry(preferences);
    const active = StoredModelRecord(
      version: '1.2.0',
      path: 'C:/models/traffic-1.2.0.tflite',
      sha256: _shaB,
      sizeBytes: 120,
    );
    await registry.activate('traffic', active);

    await registry.markActiveFailed(
      'traffic',
      failedPath: active.path,
      preventRetry: false,
    );

    expect(await registry.isVersionFailed('traffic', '1.2.0'), isFalse);
  });
}

const _shaA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _shaB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
