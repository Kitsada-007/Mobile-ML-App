import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/presentation/controllers/camera_inference_controller.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_streaming_config.dart';
import 'package:ultralytics_yolo/yolo_view.dart';

/// Main content widget that handles the camera view and loading states
class CameraInferenceContent extends StatelessWidget {
  const CameraInferenceContent({
    super.key,
    required this.controller,
    this.rebuildKey = 0,
  });

  final CameraInferenceController controller;
  final int rebuildKey;

  @override
  Widget build(BuildContext context) {
    if (controller.modelPath != null) {
      return YOLOView(
        key: ValueKey(
          'yolo_view_${controller.modelPath}_${controller.selectedModel.task.name}_$rebuildKey',
        ),
        controller: controller.yoloController,
        modelPath: controller.modelPath!,
        task: controller.selectedModel.task,
        streamingConfig: const YOLOStreamingConfig.custom(
          includeOriginalImage: true,
          maxFPS: 15,
          inferenceFrequency: 15,
        ),
        onStreamingData: (data) {
          final originalImage = data['originalImage'] as Uint8List?;
          if (originalImage != null) {
            controller.updateLatestFrame(originalImage);
          }

          final detectionsList = data['detections'] as List<dynamic>?;
          if (detectionsList != null) {
            final yoloResults = detectionsList
                .map((e) => YOLOResult.fromMap(Map<String, dynamic>.from(e)))
                .toList();
            controller.onDetectionResults(yoloResults);
          }

          final fps = data['fps'];
          if (fps is num) {
            controller.onPerformanceMetrics(fps.toDouble());
          }
        },
        onZoomChanged: controller.onZoomChanged,
        onModelError: (error, modelPath, _) {
          unawaited(controller.onModelLoadError(error, modelPath));
        },
        lensFacing: controller.lensFacing,
      );
    } else {
      return const Center(
        child: Text(
          'No model path available',
          style: TextStyle(color: Colors.white),
        ),
      );
    }
  }
}
