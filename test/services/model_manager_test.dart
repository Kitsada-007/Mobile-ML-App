import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trffic_ilght_app/core/models/models.dart';
import 'package:trffic_ilght_app/services/model_manager.dart';
import 'package:trffic_ilght_app/services/model_registry.dart';

void main() {
  late Directory temporaryDirectory;
  late ModelRegistry registry;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    registry = ModelRegistry(await SharedPreferences.getInstance());
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'model-manager-test-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('prefers a verified downloaded model over the bundled model', () async {
    final active = await _writeModel(
      temporaryDirectory,
      'traffic-1.2.0.tflite',
      <int>[1, 2, 3],
    );
    await registry.activate('traffic', _record('1.2.0', active));
    final manager = _manager(registry, temporaryDirectory);

    final path = await manager.getModelPath(ModelType.traffic);

    expect(path, active.path);
  });

  test('rolls back when the active downloaded model is corrupted', () async {
    final previous = await _writeModel(
      temporaryDirectory,
      'traffic-1.1.0.tflite',
      <int>[1, 2, 3],
    );
    final corrupted = await _writeModel(
      temporaryDirectory,
      'traffic-1.2.0.tflite',
      <int>[4, 5, 6],
    );
    await registry.activate('traffic', _record('1.1.0', previous));
    await registry.activate(
      'traffic',
      StoredModelRecord(
        version: '1.2.0',
        path: corrupted.path,
        sha256: '0' * 64,
        sizeBytes: await corrupted.length(),
      ),
    );
    final manager = _manager(registry, temporaryDirectory);

    final path = await manager.getModelPath(ModelType.traffic);

    expect(path, previous.path);
    expect((await registry.getActive('traffic'))!.path, previous.path);
  });

  test('copies the bundled model when no downloaded model is usable', () async {
    final manager = _manager(
      registry,
      temporaryDirectory,
      bundledBytes: <int>[7, 8, 9],
    );

    final path = await manager.getModelPath(ModelType.number);

    expect(path, isNotNull);
    expect(await File(path!).readAsBytes(), <int>[7, 8, 9]);
  });

  test('reports a load failure and returns the previous model', () async {
    final previous = await _writeModel(
      temporaryDirectory,
      'number-1.1.0.tflite',
      <int>[1, 2, 3],
    );
    final active = await _writeModel(
      temporaryDirectory,
      'number-1.2.0.tflite',
      <int>[4, 5, 6],
    );
    await registry.activate('number', _record('1.1.0', previous));
    await registry.activate('number', _record('1.2.0', active));
    final manager = _manager(registry, temporaryDirectory);

    final replacement = await manager.reportModelLoadFailure(
      ModelType.number,
      failedPath: active.path,
    );

    expect(replacement, previous.path);
  });
}

ModelManager _manager(
  ModelRegistry registry,
  Directory temporaryDirectory, {
  List<int> bundledBytes = const <int>[9],
}) {
  return ModelManager(
    registry: registry,
    isAndroid: true,
    rootDirectoryProvider: () async => temporaryDirectory,
    bundledModelLoader: (_) async => Uint8List.fromList(bundledBytes),
    nativeModelLookup: (_) async => null,
  );
}

Future<File> _writeModel(
  Directory temporaryDirectory,
  String name,
  List<int> bytes,
) async {
  final file = File('${temporaryDirectory.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

StoredModelRecord _record(String version, File file) {
  final bytes = file.readAsBytesSync();
  return StoredModelRecord(
    version: version,
    path: file.path,
    sha256: sha256.convert(bytes).toString(),
    sizeBytes: bytes.length,
  );
}
