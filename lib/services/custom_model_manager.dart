// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ultralytics_yolo/config/channel_config.dart';

/// Manages custom YOLO models loaded from local storage or assets
class CustomModelManager {
  static final MethodChannel _channel =
      ChannelConfig.createSingleImageChannel();

  /// Gets the path for a custom model
  Future<String?> getCustomModelPath(
    String modelName, {
    String? customPath,
  }) async {
    // If custom path is provided, use it directly
    if (customPath != null && await File(customPath).exists()) {
      return customPath;
    }

    // Check in assets first
    try {
      final assetPath = 'assets/models/$modelName';
      await rootBundle.load(assetPath);
      return assetPath;
    } catch (_) {
      // Not in assets, check local storage
    }

    // Check in local storage
    final dir = await getApplicationDocumentsDirectory();
    final modelFile = File('${dir.path}/$modelName');
    if (await modelFile.exists()) {
      return modelFile.path;
    }

    return null;
  }

  /// Copy custom model from assets to local storage
  Future<String?> copyModelFromAssets(String modelName) async {
    try {
      final assetPath = 'assets/models/$modelName';
      final byteData = await rootBundle.load(assetPath);
      final bytes = byteData.buffer.asUint8List();

      final dir = await getApplicationDocumentsDirectory();
      final modelFile = File('${dir.path}/$modelName');
      await modelFile.writeAsBytes(bytes);

      return modelFile.path;
    } catch (e) {
      print('Error copying model from assets: $e');
      return null;
    }
  }

  /// Check if custom model exists in native assets
  Future<bool> checkCustomModelExists(String modelName) async {
    try {
      final result = await _channel.invokeMethod('checkModelExists', {
        'modelPath': modelName,
      });
      return result != null && result['exists'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Get list of available custom models in local storage
  Future<List<String>> getLocalCustomModels() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory('${dir.path}/custom_models');

      if (!await modelsDir.exists()) {
        return [];
      }

      final files = await modelsDir.list().toList();
      return files
          .whereType<File>()
          .map((file) => file.path.split('/').last)
          .where(
            (name) =>
                name.endsWith('.pt') ||
                name.endsWith('.tflite') ||
                name.endsWith('.onnx'),
          )
          .toList();
    } catch (e) {
      print('Error getting local custom models: $e');
      return [];
    }
  }

  /// Save custom model to local storage
  Future<String?> saveCustomModel(String sourcePath, String modelName) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final customModelsDir = Directory('${dir.path}/custom_models');
      await customModelsDir.create(recursive: true);

      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return null;
      }

      final targetFile = File('${customModelsDir.path}/$modelName');
      await sourceFile.copy(targetFile.path);

      return targetFile.path;
    } catch (e) {
      print('Error saving custom model: $e');
      return null;
    }
  }
}
