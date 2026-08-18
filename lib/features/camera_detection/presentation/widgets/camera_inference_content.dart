import 'dart:async';
import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/controllers/camera_inference_controller.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

const Size cameraAnalysisResolution = Size(1280, 960);
const int cameraInferenceFrequency = 15;
const int cameraResultMaxFps = 10;

/// เนื้อหาหลักของหน้าตรวจจับกล้อง: จัดการ view กล้อง (YOLOView) และสถานะโหลด
class CameraInferenceContent extends StatefulWidget {
  const CameraInferenceContent({
    super.key,
    required this.controller,
    this.rebuildKey = 0,
  });

  final CameraInferenceController controller;
  final int rebuildKey; // ใช้บังคับ rebuild YOLOView (เช่นกลับมาจากหน้าอื่น)

  @override
  State<CameraInferenceContent> createState() => _CameraInferenceContentState();
}

class _CameraInferenceContentState extends State<CameraInferenceContent> {
  String? _modelPath;
  late YOLOTask _task;
  bool _isModelLoading = false;
  String _loadingMessage = '';
  double _downloadProgress = 0;
  bool _isCameraActive = true;

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

  /// อ่านสถานะโมเดลจาก controller ครั้งเดียว (กัน rebuild บ่อย)
  void _readModelState() {
    _modelPath = widget.controller.modelPath;
    _task = widget.controller.selectedModel.task;
    _isModelLoading = widget.controller.isModelLoading;
    _loadingMessage = widget.controller.loadingMessage;
    _downloadProgress = widget.controller.downloadProgress;
    _isCameraActive = widget.controller.isCameraActive;
  }

  /// เมื่อ controller แจ้งเตือน: rebuild เฉพาะเมื่อสถานะโหลดโมเดลเปลี่ยน
  void _handleControllerChanged() {
    final nextModelPath = widget.controller.modelPath;
    final nextTask = widget.controller.selectedModel.task;
    final nextIsModelLoading = widget.controller.isModelLoading;
    final nextLoadingMessage = widget.controller.loadingMessage;
    final nextDownloadProgress = widget.controller.downloadProgress;
    final nextIsCameraActive = widget.controller.isCameraActive;
    // ถ้าไม่มีอะไรเปลี่ยน -> ไม่ต้อง rebuild (กันสะดุ้ง)
    if (nextModelPath == _modelPath &&
        nextTask == _task &&
        nextIsModelLoading == _isModelLoading &&
        nextLoadingMessage == _loadingMessage &&
        nextDownloadProgress == _downloadProgress &&
        nextIsCameraActive == _isCameraActive) {
      return;
    }

    setState(() {
      _modelPath = nextModelPath;
      _task = nextTask;
      _isModelLoading = nextIsModelLoading;
      _loadingMessage = nextLoadingMessage;
      _downloadProgress = nextDownloadProgress;
      _isCameraActive = nextIsCameraActive;
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

    // ไม่สร้าง YOLOView ขณะ route/app ถูกพัก เพื่อให้ native camera ถูกปล่อยจริง
    if (!_isCameraActive) {
      final isLifecyclePaused = controller.isCameraEnabled;
      return Container(
        key: Key(
          isLifecyclePaused ? 'cameraLifecyclePaused' : 'cameraDisabled',
        ),
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.videocam_off_rounded,
                color: Colors.white54,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                isLifecyclePaused ? 'กล้องหยุดชั่วคราว' : 'กล้องปิดอยู่',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (modelPath != null) {
      return YOLOView(
        key: ValueKey('yolo_view_${widget.rebuildKey}'),
        controller: controller.yoloController,
        modelPath: modelPath,
        task: _task,
        useGpu: true,
        streamingConfig: const YOLOStreamingConfig.custom(
          includeOriginalImage: true, // ส่งภาพต้นฉบับด้วย (ใช้ crop อ่านตัวเลข)
          maxFPS: cameraResultMaxFps,
          inferenceFrequency: cameraInferenceFrequency,
          analysisResolution: cameraAnalysisResolution,
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

/// หน้าจอ/วิดเจ็ตขณะกำลังโหลด/เตรียมระบบตรวจจับ
class _CameraPreparingState extends StatelessWidget {
  const _CameraPreparingState({
    required this.isLoading,
    required this.message,
    required this.progress,
  });

  final bool isLoading;
  final String message;
  final double progress; // ความคืบหน้าโหลด (0-1)

  @override
  Widget build(BuildContext context) {
    final hasProgress = progress > 0 && progress < 1;

    return ColoredBox(
      color: const Color(0xFF090909),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxHeight < 240; // เนื้อที่น้อย -> โหมดกะทัดรัด

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Padding(
                padding: EdgeInsets.all(compact ? 12 : 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: compact ? 48 : 64,
                      height: compact ? 48 : 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 2),
                      ),
                      child: Icon(
                        Icons.center_focus_strong_rounded,
                        color: Colors.white,
                        size: compact ? 24 : 30,
                      ),
                    ),
                    SizedBox(height: compact ? 8 : 14),
                    Text(
                      isLoading
                          ? 'กำลังโหลดระบบตรวจจับ'
                          : 'กำลังเตรียมระบบตรวจจับ',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 16 : 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: compact ? 4 : 6),
                    Text(
                      message.isEmpty
                          ? 'กล้องจะเริ่มทำงานอัตโนมัติเมื่อโมเดลพร้อม'
                          : message,
                      textAlign: TextAlign.center,
                      maxLines: compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: compact ? 11 : 13,
                        height: compact ? 1.25 : 1.45,
                      ),
                    ),
                    if (hasProgress) ...[
                      SizedBox(height: compact ? 8 : 12),
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
          );
        },
      ),
    );
  }
}
