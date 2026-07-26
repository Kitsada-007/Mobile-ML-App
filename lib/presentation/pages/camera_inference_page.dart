// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/presentation/controllers/camera_inference_controller.dart';
import 'package:trffic_ilght_app/presentation/widgets/camera_widgets/camera_detection_panel.dart';
import 'package:trffic_ilght_app/presentation/widgets/camera_widgets/camera_inference_content.dart';
import 'package:trffic_ilght_app/presentation/widgets/camera_widgets/camera_inference_overlay.dart';

/// Fullscreen real-time YOLO camera inference with an overlaid status HUD.
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: ListenableBuilder(
        listenable: _controller,
        child: CameraInferenceContent(
          key: ValueKey('camera_content_$_rebuildKey'),
          controller: _controller,
          rebuildKey: _rebuildKey,
        ),
        builder: (context, cameraContent) {
          return Stack(
            key: const Key('fullscreenCameraStack'),
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: cameraContent!),
              CameraDetectionPanel(
                formalNames: _controller.detectedFormalNames,
                alertMessages: _controller.detectedAlertMessages,
                detectedNumber: _controller.detectedNumber,
                isLandscape: isLandscape,
              ),
              CameraInferenceOverlay(
                detectionCount: _controller.detectionCount,
                currentFps: _controller.currentFps,
                isLandscape: isLandscape,
                showMenuButton: widget.onMenuPressed != null,
                onLeadingPressed:
                    widget.onMenuPressed ?? () => Navigator.maybePop(context),
              ),
            ],
          );
        },
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
