import 'package:flutter/material.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/widgets/camera_detection_panel.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/controllers/video_inference_controller.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/widgets/full_screen_video.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/widgets/video_result_section.dart';

export 'package:trffic_ilght_app/features/video_detection/presentation/controllers/video_inference_controller.dart'
    show createVideoYolo;

/// Screen widget for Video Detection UI.
/// Contains pure UI rendering and delegates business logic to [VideoInferenceController].
class VideoInferenceScreen extends StatefulWidget {
  const VideoInferenceScreen({super.key});

  @override
  State<VideoInferenceScreen> createState() => _VideoInferenceScreenState();
}

class _VideoInferenceScreenState extends State<VideoInferenceScreen> {
  late final VideoInferenceController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoInferenceController();
    _controller.addListener(_onControllerNotification);
    _controller.initializeModels();
  }

  void _onControllerNotification() {
    if (!mounted) return;
    final message = _controller.snackBarMessage;
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
      _controller.clearSnackBarMessage();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerNotification);
    _controller.dispose();
    super.dispose();
  }

  void _openFullScreen() {
    if (_controller.videoController == null) return;

    Get.to(
      () => FullScreenVideoPage(controller: _controller.videoController!),
    )?.then((_) {
      if (mounted) setState(() {});
    });
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
          builder: (context, _) {
            final bool hasVideoResult =
                _controller.videoController != null &&
                _controller.videoController!.value.isInitialized;

            return SingleChildScrollView(
              key: const Key('videoDetectionScrollView'),
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
                      // Header Row
                      Row(
                        children: [
                          Semantics(
                            button: true,
                            label: 'ย้อนกลับ',
                            child: IconButton(
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                              ),
                              onPressed: () => Navigator.maybePop(context),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ตรวจจับจากวิดีโอ',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Video Traffic Light Detection',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'เลือกวิดีโอ',
                            icon: const Icon(Icons.video_library_rounded),
                            onPressed: _controller.isProcessing
                                ? null
                                : _controller.pickVideo,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      if (!_controller.areModelsReady)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator(
                            minHeight: 3,
                            color: colorScheme.primary,
                            backgroundColor: colorScheme.onSurface.withValues(
                              alpha: 0.08,
                            ),
                          ),
                        ),

                      // Main Video Card (Result Video OR Processing OR Picker Prompt)
                      if (hasVideoResult) ...[
                        ResultVideoSection(
                          controller: _controller.videoController!,
                          detections: _controller.currentFrameDetections,
                          detectedNumber: _controller.currentDetectedNumber,
                          onOpenFullScreen: _openFullScreen,
                          onTogglePlayPause: _controller.togglePlayPause,
                          onPickNewVideo: _controller.pickVideo,
                        ),
                      ] else if (_controller.isProcessing) ...[
                        _VideoProcessingCard(
                          progressValue: _controller.progressValue,
                          progressText: _controller.progressText,
                          isLandscape: isLandscape,
                        ),
                      ] else ...[
                        _VideoPickerPlaceholderCard(
                          areModelsReady: _controller.areModelsReady,
                          onPickVideo: _controller.pickVideo,
                          isLandscape: isLandscape,
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Realtime Detection Panel matching Camera Page
                      CameraDetectionPanel(
                        formalNames: _controller.currentFormalNames,
                        alertMessages: _controller.currentAlertMessages,
                        detectedNumber: _controller.currentDetectedNumber,
                        isLandscape: isLandscape,
                        isPipelineStale:
                            !_controller.isProcessing &&
                            _controller.currentFrameDetections.isEmpty &&
                            _controller.currentDetectedNumber == null,
                        statusText: hasVideoResult
                            ? (_controller.videoController!.value.isPlaying
                                  ? 'กำลังตรวจจับแบบเรียลไทม์'
                                  : 'หยุดชั่วคราว')
                            : _controller.isProcessing
                            ? _controller.progressText
                            : 'พร้อมตรวจจับวิดีโอ',
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
}

class _VideoProcessingCard extends StatelessWidget {
  const _VideoProcessingCard({
    required this.progressValue,
    required this.progressText,
    required this.isLandscape,
  });

  final double progressValue;
  final String progressText;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
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
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    color: Color(0xFF34C759),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  progressText.isEmpty
                      ? 'กำลังวิเคราะห์วิดีโอ...'
                      : progressText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progressValue > 0 ? progressValue : null,
                    minHeight: 8,
                    color: const Color(0xFF34C759),
                    backgroundColor: Colors.white24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoPickerPlaceholderCard extends StatelessWidget {
  const _VideoPickerPlaceholderCard({
    required this.areModelsReady,
    required this.onPickVideo,
    required this.isLandscape,
  });

  final bool areModelsReady;
  final VoidCallback onPickVideo;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
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
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.video_library_rounded,
                    size: 72,
                    color: Colors.white24,
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'ตรวจจับจากไฟล์วิดีโอ (Real-Time)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'เลือกวิดีโอจากคลังเพื่อเริ่มการตรวจจับสัญญาณไฟสดบนวิดีโอ',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: areModelsReady ? onPickVideo : null,
                        icon: const Icon(Icons.video_library_outlined),
                        label: Text(
                          areModelsReady
                              ? 'เลือกวิดีโอจากคลัง'
                              : 'กำลังโหลดโมเดล...',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF16A05D),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
