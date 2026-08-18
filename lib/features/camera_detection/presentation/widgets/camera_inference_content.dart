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
      String pausedKey;
      String pausedLabel;
      if (isLifecyclePaused) {
        pausedKey = 'cameraLifecyclePaused';
        pausedLabel = 'กล้องหยุดชั่วคราว';
      } else {
        pausedKey = 'cameraDisabled';
        pausedLabel = 'กล้องปิดอยู่';
      }

      return Container(
        key: Key(pausedKey),
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
                pausedLabel,
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

    String titleText;
    if (isLoading) {
      titleText = 'กำลังโหลดระบบตรวจจับ';
    } else {
      titleText = 'กำลังเตรียมระบบตรวจจับ';
    }

    String detailText;
    if (message.isEmpty) {
      detailText = 'กล้องจะเริ่มทำงานอัตโนมัติเมื่อโมเดลพร้อม';
    } else {
      detailText = message;
    }

    return ColoredBox(
      color: const Color(0xFF090909),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxHeight < 240; // เนื้อที่น้อย -> โหมดกะทัดรัด

          // ขนาด/ระยะห่างทั้งหมดย่อลงพร้อมกันเมื่ออยู่ในโหมดกะทัดรัด
          double outerPadding;
          double circleSize;
          double iconSize;
          double gapAfterCircle;
          double titleFontSize;
          double gapAfterTitle;
          int detailMaxLines;
          double detailFontSize;
          double detailLineHeight;
          double gapBeforeProgress;
          if (compact) {
            outerPadding = 12;
            circleSize = 48;
            iconSize = 24;
            gapAfterCircle = 8;
            titleFontSize = 16;
            gapAfterTitle = 4;
            detailMaxLines = 2;
            detailFontSize = 11;
            detailLineHeight = 1.25;
            gapBeforeProgress = 8;
          } else {
            outerPadding = 20;
            circleSize = 64;
            iconSize = 30;
            gapAfterCircle = 14;
            titleFontSize = 18;
            gapAfterTitle = 6;
            detailMaxLines = 3;
            detailFontSize = 13;
            detailLineHeight = 1.45;
            gapBeforeProgress = 12;
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Padding(
                padding: EdgeInsets.all(outerPadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: circleSize,
                      height: circleSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 2),
                      ),
                      child: Icon(
                        Icons.center_focus_strong_rounded,
                        color: Colors.white,
                        size: iconSize,
                      ),
                    ),
                    SizedBox(height: gapAfterCircle),
                    Text(
                      titleText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: gapAfterTitle),
                    Text(
                      detailText,
                      textAlign: TextAlign.center,
                      maxLines: detailMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: detailFontSize,
                        height: detailLineHeight,
                      ),
                    ),
                    if (hasProgress) ...[
                      SizedBox(height: gapBeforeProgress),
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
