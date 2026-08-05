// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/controllers/camera_inference_controller.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/widgets/camera_detection_panel.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/widgets/camera_inference_content.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/widgets/camera_inference_overlay.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/widgets/detection_stats_display.dart';

/// Real-time YOLO camera inference with results displayed below the preview.
class CameraInferencePage extends StatefulWidget {
  const CameraInferencePage({
    super.key,
    this.onMenuPressed,
    this.initializeOnStart = true,
  });

  final VoidCallback? onMenuPressed;
  final bool initializeOnStart;

  @override
  State<CameraInferencePage> createState() => _CameraInferencePageState();
}

class _CameraInferencePageState extends State<CameraInferencePage> {
  late final CameraInferenceController _controller;
  int _rebuildKey = 0;

  @override
  void initState() {
    super.initState();
    _controller = CameraInferenceController();
    if (widget.initializeOnStart) {
      _controller.initialize().catchError((error) {
        if (mounted) {
          _showError('Model Loading Error', error.toString());
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route?.isCurrent == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _rebuildKey++);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          child: CameraInferenceContent(
            key: ValueKey('camera_content_$_rebuildKey'),
            controller: _controller,
            rebuildKey: _rebuildKey,
          ),
          builder: (context, cameraContent) {
            return SingleChildScrollView(
              key: const Key('cameraDetectionScrollView'),
              padding: EdgeInsets.fromLTRB(
                isLandscape ? 24 : 16,
                8,
                isLandscape ? 24 : 16,
                24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CameraInferenceOverlay(
                        showMenuButton: widget.onMenuPressed != null,
                        onLeadingPressed:
                            widget.onMenuPressed ??
                            () => Navigator.maybePop(context),
                      ),
                      const SizedBox(height: 16),
                      DecoratedBox(
                        key: const Key('cameraPreviewCard'),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: AspectRatio(
                            aspectRatio: isLandscape ? 16 / 9 : 4 / 3,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                cameraContent!,
                                Positioned(
                                  top: 14,
                                  left: 14,
                                  child: _LiveStatusBadge(
                                    hasDetections:
                                        _controller.detectionCount > 0,
                                  ),
                                ),
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  child: Semantics(
                                    button: true,
                                    label: _controller.isCameraEnabled
                                        ? 'ปิดกล้อง'
                                        : 'เปิดกล้อง',
                                    child: IconButton.filled(
                                      key: const Key('cameraPowerButton'),
                                      tooltip: _controller.isCameraEnabled
                                          ? 'ปิดกล้อง'
                                          : 'เปิดกล้อง',
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.black54,
                                        foregroundColor: Colors.white,
                                      ),
                                      icon: Icon(
                                        _controller.isCameraEnabled
                                            ? Icons.videocam_rounded
                                            : Icons.videocam_off_rounded,
                                      ),
                                      onPressed: () =>
                                          unawaited(_controller.toggleCamera()),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 14,
                                  right: 14,
                                  bottom: 14,
                                  child: DetectionStatsDisplay(
                                    detectionCount: _controller.detectionCount,
                                    currentFps: _controller.currentFps,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      CameraDetectionPanel(
                        formalNames: _controller.detectedFormalNames,
                        alertMessages: _controller.detectedAlertMessages,
                        detectedNumber: _controller.detectedNumber,
                        isLandscape: isLandscape,
                        isPipelineStale: _controller.isRealtimePipelineStale,
                        statusText: _controller.detectionStatus,
                        lastDetectionConfidence:
                            _controller.lastDetectionConfidence,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showError(String title, String message) => showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

class _LiveStatusBadge extends StatelessWidget {
  const _LiveStatusBadge({required this.hasDetections});

  final bool hasDetections;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: hasDetections ? 'ตรวจจับสัญญาณแล้ว' : 'กำลังตรวจจับ',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: Color(0xFF34C759),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                hasDetections ? 'ตรวจจับแล้ว' : 'กำลังตรวจจับ',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
