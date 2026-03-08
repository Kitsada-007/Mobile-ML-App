import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:trffic_ilght_app/core/models/models.dart';

/// Manages YOLO model loading from app assets and local cache.
///
/// Flow:
/// 1. Resolve model file name
/// 2. Check local cached file in app documents
/// 3. If not found, copy from assets/models/ to local storage
/// 4. Return local file path
class ModelManager {
  /// Optional progress callback.
  /// In this version it will mainly report 0.0 -> 1.0 while copying from assets.
  final void Function(double progress)? onDownloadProgress;

  /// Optional status callback for UI text such as "Loading model..."
  final void Function(String message)? onStatusUpdate;

  ModelManager({this.onDownloadProgress, this.onStatusUpdate});

  /// Entry point for loading model path based on current platform.
  Future<String?> getModelPath(ModelType modelType) async {
    if (Platform.isAndroid) {
      return _getAndroidModelPath(modelType);
    } else if (Platform.isIOS) {
      return _getIOSModelPath(modelType);
    }
    return null;
  }

  String _resolveAssetPath(String fileName) {
    if (fileName.startsWith('assets/')) {
      return fileName;
    }
    return 'assets/models/$fileName';
  }

  Future<String?> _getAndroidModelPath(ModelType modelType) async {
    final String fileName = _resolveAndroidModelFileName(modelType);
    final String assetPath = _resolveAssetPath(fileName);

    _updateStatus('Loading $fileName ...');
    onDownloadProgress?.call(0.0);

    final Directory dir = await getApplicationDocumentsDirectory();
    final String localName = fileName.split('/').last;
    final File modelFile = File('${dir.path}/models/$localName');

    if (await modelFile.exists()) {
      _updateStatus('');
      onDownloadProgress?.call(1.0);
      return modelFile.path;
    }

    try {
      final ByteData assetData = await rootBundle.load(assetPath);

      await modelFile.parent.create(recursive: true);
      await modelFile.writeAsBytes(assetData.buffer.asUint8List(), flush: true);

      _updateStatus('');
      onDownloadProgress?.call(1.0);
      return modelFile.path;
    } catch (e) {
      debugPrint('Failed to load Android model asset: $e');
      _updateStatus('Failed to load model');
      onDownloadProgress?.call(0.0);
      return null;
    }
  }

  /// iOS: basic support for loading model assets.
  ///
  /// If your iOS build actually uses `.mlpackage`, this method expects
  /// the asset path to exist in `assets/models/`.
  Future<String?> _getIOSModelPath(ModelType modelType) async {
    final String modelName = modelType.modelName;

    _updateStatus('Loading $modelName ...');
    onDownloadProgress?.call(0.0);

    final Directory dir = await getApplicationDocumentsDirectory();

    // Case 1: direct file model (.mlmodel / .tflite / etc.)
    final File directFile = File('${dir.path}/models/$modelName');
    if (await directFile.exists()) {
      _updateStatus('');
      onDownloadProgress?.call(1.0);
      return directFile.path;
    }

    // Case 2: mlpackage directory already exists
    final Directory mlPackageDir = Directory(
      '${dir.path}/models/$modelName.mlpackage',
    );
    final File manifestFile = File('${mlPackageDir.path}/Manifest.json');

    if (await mlPackageDir.exists() && await manifestFile.exists()) {
      _updateStatus('');
      onDownloadProgress?.call(1.0);
      return mlPackageDir.path;
    }

    // Try loading from assets as a normal file first
    try {
      final ByteData assetData = await rootBundle.load(
        'assets/models/$modelName',
      );

      await directFile.parent.create(recursive: true);
      await directFile.writeAsBytes(
        assetData.buffer.asUint8List(),
        flush: true,
      );

      _updateStatus('');
      onDownloadProgress?.call(1.0);
      return directFile.path;
    } catch (_) {
      // ignore and try mlpackage path next
    }

    // Try loading as `.mlpackage` asset bundle file path
    try {
      final ByteData assetData = await rootBundle.load(
        'assets/models/$modelName.mlpackage',
      );

      final File outputFile = File('${dir.path}/models/$modelName.mlpackage');

      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(
        assetData.buffer.asUint8List(),
        flush: true,
      );

      _updateStatus('');
      onDownloadProgress?.call(1.0);
      return outputFile.path;
    } catch (e) {
      debugPrint('Failed to load iOS model asset: $e');
      _updateStatus('Failed to load model');
      onDownloadProgress?.call(0.0);
      return null;
    }
  }

  /// Resolve Android file name.
  ///
  /// If modelName already ends with a supported extension, use it directly.
  /// Otherwise default to `.tflite`.
  String _resolveAndroidModelFileName(ModelType modelType) {
    final String name = modelType.modelName;

    if (name.endsWith('.tflite') ||
        name.endsWith('.pt') ||
        name.endsWith('.onnx')) {
      return name;
    }

    return '$name.tflite';
  }

  void _updateStatus(String message) {
    onStatusUpdate?.call(message);
  }
}
