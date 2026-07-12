import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/presentation/controllers/camera_inference_controller.dart';

import 'detection_stats_display.dart';

/// Top overlay widget containing model selector, stats, and threshold pills
class CameraInferenceOverlay extends StatelessWidget {
  const CameraInferenceOverlay({
    super.key,
    required this.controller,
    required this.isLandscape,
  });

  final CameraInferenceController controller;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + (isLandscape ? 8 : 16),
      left: isLandscape ? 8 : 16,
      right: isLandscape ? 8 : 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ModelSelector(
          //   selectedModel: controller.selectedModel,
          //   isModelLoading: controller.isModelLoading,
          //   onModelChanged: controller.changeModel,
          // ),
          SizedBox(height: isLandscape ? 8 : 12),
          DetectionStatsDisplay(
            detectionCount: controller.detectionCount,
            currentFps: controller.currentFps,
          ),
        ],
      ),
    );
  }
}
