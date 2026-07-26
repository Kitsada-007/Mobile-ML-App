import 'dart:async';
import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/presentation/controllers/camera_inference_controller.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

/// Main content widget that handles the camera view and loading states
class CameraInferenceContent extends StatefulWidget {
  const CameraInferenceContent({
    super.key,
    required this.controller,
    this.rebuildKey = 0,
  });

  final CameraInferenceController controller;
  final int rebuildKey;

  @override
  State<CameraInferenceContent> createState() => _CameraInferenceContentState();
}

class _CameraInferenceContentState extends State<CameraInferenceContent> {
  String? _modelPath;
  late YOLOTask _task;

  @override
  void initState() {
    super.initState();
    _readModelState();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(CameraInferenceContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      _readModelState();
      widget.controller.addListener(_handleControllerChanged);
    }
  }

  void _readModelState() {
    _modelPath = widget.controller.modelPath;
    _task = widget.controller.selectedModel.task;
  }

  void _handleControllerChanged() {
    final nextModelPath = widget.controller.modelPath;
    final nextTask = widget.controller.selectedModel.task;
    if (nextModelPath == _modelPath && nextTask == _task) return;

    setState(() {
      _modelPath = nextModelPath;
      _task = nextTask;
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modelPath = _modelPath;
    final controller = widget.controller;
    if (modelPath != null) {
      return YOLOView(
        key: ValueKey('yolo_view_${widget.rebuildKey}'),
        controller: controller.yoloController,
        modelPath: modelPath,
        task: _task,
        streamingConfig: const YOLOStreamingConfig.custom(
          includeOriginalImage: true,
          maxFPS: 10,
          inferenceFrequency: 10,
        ),
        onStreamingData: (data) => unawaited(controller.onStreamingData(data)),
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
