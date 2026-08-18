import 'dart:async';
import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/widgets/video_detection_panel.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/controllers/video_inference_controller.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/widgets/video_result_section.dart';

/// หน้า Screen สำหรับ UI ของการตรวจจับวิดีโอ
/// ฝั่งนี้เป็นแค่ pure UI rendering และส่งต่อ business logic ทั้งหมดให้ [VideoInferenceController]
class VideoInferenceScreen extends StatefulWidget {
  const VideoInferenceScreen({super.key});

  @override
  State<VideoInferenceScreen> createState() => _VideoInferenceScreenState();
}

class _VideoInferenceScreenState extends State<VideoInferenceScreen>
    with WidgetsBindingObserver {
  late final VideoInferenceController _controller;
  bool? _isRouteCurrent;
  bool _isAppResumed = true;

  /// ระยะขอบบน/ล่างของทั้งหน้า
  static const double _screenPadding = 12;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = VideoInferenceController();
    _controller.addListener(_onControllerNotification);
    _controller.initializeModels();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (_isRouteCurrent == isCurrent) return;

    _isRouteCurrent = isCurrent;
    _syncVideoLifecycle();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppResumed = state == AppLifecycleState.resumed;
    _syncVideoLifecycle();
  }

  void _syncVideoLifecycle() {
    final shouldPlay = (_isRouteCurrent ?? true) && _isAppResumed;
    if (!shouldPlay) {
      unawaited(_controller.pause());
    }
  }

  /// ตอบสนองเมื่อ controller notifyListeners()
  void _onControllerNotification() {
    if (!mounted) {
      return;
    }
    final message = _controller.snackBarMessage;
    if (message != null) {
      _controller.clearSnackBarMessage();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void deactivate() {
    unawaited(_controller.pause());
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerNotification);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          unawaited(_controller.pause());
        }
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final bool hasVideoResult =
                  _controller.videoController != null &&
                  _controller.videoController!.value.isInitialized;

              final horizontalPadding = isLandscape ? 24.0 : 16.0;

              final header = _VideoHeader(
                showModelProgress: !_controller.areModelsReady,
                onBack: () {
                  unawaited(_controller.pause());
                  Navigator.maybePop(context);
                },
              );

              // 1. สร้าง Widget เนื้อหาตรงกลาง (วิดีโอ / โหลดดิ้ง / ปุ่มเลือกไฟล์)
              final Widget cardContent;
              if (hasVideoResult) {
                cardContent = Container(
                  width: double.infinity, // กลับมากางให้กว้างเต็มหน้าจอ
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: Colors.black,
                  ),
                  clipBehavior: Clip.hardEdge,
                  // เอา Center และ AspectRatio ออก ปล่อยให้ ResultVideoSection จัดการตัวเองให้เต็มพื้นที่
                  child: ResultVideoSection(
                    controller: _controller.videoController!,
                    detections: _controller.currentFrameDetections,
                    isVoiceEnabled: _controller.isVoiceEnabled,
                    onTogglePlayPause: _controller.togglePlayPause,
                    onToggleVoice: _controller.toggleVoice,
                    onPickNewVideo: _controller.pickVideo,
                  ),
                );
              } else if (_controller.isProcessing) {
                cardContent = _VideoProcessingCard(
                  progressValue: _controller.progressValue,
                  progressText: _controller.progressText,
                );
              } else {
                cardContent = _VideoPickerPlaceholderCard(
                  areModelsReady: _controller.areModelsReady,
                  onPickVideo: _controller.pickVideo,
                );
              }

              // 2. แผงควบคุมด้านล่าง (คงที่เสมอ)
              final panel = VideoDetectionPanel(
                formalNames: _controller.currentFormalNames,
                alertMessages: _controller.currentAlertMessages,
                detectedNumber: _controller.currentDetectedNumber,
                driverSignalResult: _controller.currentDriverSignalResult,
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
                lastDetectionConfidence: _controller.lastDetectionConfidence,
                trafficLightClassName: _controller.stableTrafficLightClassName,
              );

              // 3. แนวนอน: จัดให้อยู่ในหน้าเดียวด้วย Row + Expanded คู่
              if (isLandscape) {
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    _screenPadding,
                    horizontalPadding,
                    _screenPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      const SizedBox(height: 12),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(flex: 3, child: cardContent),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: SingleChildScrollView(
                                key: const Key('videoDetectionScrollView'),
                                child: panel,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              // 4. แนวตั้ง: บังคับให้อยู่ใน 1 หน้าจอเป๊ะๆ (ไม่มี Scroll)
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  _screenPadding,
                  horizontalPadding,
                  _screenPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const SizedBox(height: 16),
                    // ใช้ Expanded คลุม Card เนื้อหาหลัก
                    // เพื่อให้มันยืดตัวกินที่ว่างตรงกลางหน้าจอ "ทั้งหมด"
                    Expanded(child: cardContent),
                    const SizedBox(height: 16),
                    panel, // แผงควบคุมจะถูกดันให้ไปชิดขอบล่างพอดี
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// ส่วนหัวของหน้า
class _VideoHeader extends StatelessWidget {
  const _VideoHeader({required this.showModelProgress, required this.onBack});

  final bool showModelProgress;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Semantics(
              button: true,
              label: 'ย้อนกลับ',
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: onBack,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ตรวจจับจากวิดีโอ',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (showModelProgress)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(
              minHeight: 3,
              color: colorScheme.primary,
              backgroundColor: colorScheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
      ],
    );
  }
}

/// การ์ดแสดงความคืบหน้า
class _VideoProcessingCard extends StatelessWidget {
  const _VideoProcessingCard({
    required this.progressValue,
    required this.progressText,
  });

  final double progressValue;
  final String progressText;

  @override
  Widget build(BuildContext context) {
    final percent = (progressValue * 100).clamp(0, 100).toInt();
    final hasDeterminateProgress = progressValue > 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF121417),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: CircularProgressIndicator(
                        value: hasDeterminateProgress ? progressValue : null,
                        strokeWidth: 5,
                        color: const Color(0xFF34C759),
                        backgroundColor: Colors.white12,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    if (hasDeterminateProgress)
                      Text(
                        '$percent%',
                        style: const TextStyle(
                          color: Color(0xFF34C759),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    else
                      const Icon(
                        Icons.movie_creation_rounded,
                        color: Color(0xFF34C759),
                        size: 28,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                progressText.isEmpty ? 'กำลังวิเคราะห์วิดีโอ...' : progressText,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: hasDeterminateProgress ? progressValue : null,
                    minHeight: 6,
                    color: const Color(0xFF34C759),
                    backgroundColor: Colors.white12,
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

/// การ์ดชวนเลือกวิดีโอ
class _VideoPickerPlaceholderCard extends StatelessWidget {
  const _VideoPickerPlaceholderCard({
    required this.areModelsReady,
    required this.onPickVideo,
  });

  final bool areModelsReady;
  final VoidCallback onPickVideo;

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
                      'ตรวจจับจากไฟล์วิดีโอ',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
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
    );
  }
}
