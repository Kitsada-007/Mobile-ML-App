import 'dart:async';
import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/controllers/camera_inference_controller.dart';
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
  bool _isModelLoading = false;
  String _loadingMessage = '';
  double _downloadProgress = 0;

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
    _isModelLoading = widget.controller.isModelLoading;
    _loadingMessage = widget.controller.loadingMessage;
    _downloadProgress = widget.controller.downloadProgress;
  }

  void _handleControllerChanged() {
    final nextModelPath = widget.controller.modelPath;
    final nextTask = widget.controller.selectedModel.task;
    final nextIsModelLoading = widget.controller.isModelLoading;
    final nextLoadingMessage = widget.controller.loadingMessage;
    final nextDownloadProgress = widget.controller.downloadProgress;
    if (nextModelPath == _modelPath &&
        nextTask == _task &&
        nextIsModelLoading == _isModelLoading &&
        nextLoadingMessage == _loadingMessage &&
        nextDownloadProgress == _downloadProgress) {
      return;
    }

    setState(() {
      _modelPath = nextModelPath;
      _task = nextTask;
      _isModelLoading = nextIsModelLoading;
      _loadingMessage = nextLoadingMessage;
      _downloadProgress = nextDownloadProgress;
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
          maxFPS: 8,
          inferenceFrequency: 10,
          analysisResolution: Size(1280, 960),
        ),
        onStreamingData: (data) => unawaited(controller.onStreamingData(data)),
        onZoomChanged: controller.onZoomChanged,
        onModelError: (error, modelPath, _) {
          unawaited(controller.onModelLoadError(error, modelPath));
        },
        lensFacing: controller.lensFacing,
      );
    } else {
      return _CameraPreparingState(
        isLoading: _isModelLoading,
        message: _loadingMessage,
        progress: _downloadProgress,
      );
    }
  }
}

class _CameraPreparingState extends StatelessWidget {
  const _CameraPreparingState({
    required this.isLoading,
    required this.message,
    required this.progress,
  });

  final bool isLoading;
  final String message;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final hasProgress = progress > 0 && progress < 1;

    return ColoredBox(
      color: const Color(0xFF090909),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                  child: const Icon(
                    Icons.center_focus_strong_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  isLoading ? 'กำลังโหลดระบบตรวจจับ' : 'กำลังเตรียมระบบตรวจจับ',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message.isEmpty
                      ? 'กล้องจะเริ่มทำงานอัตโนมัติเมื่อโมเดลพร้อม'
                      : message,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                if (hasProgress) ...[
                  const SizedBox(height: 20),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: Colors.white12,
                      color: const Color(0xFF63E681),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
