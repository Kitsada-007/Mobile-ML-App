import 'dart:async';
import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/core/services/voice/traffic_voice_service.dart';
import 'package:trffic_ilght_app/features/settings/settings.dart';
import 'package:trffic_ilght_app/shared/utils/optional_provider.dart';
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
  SettingsProvider? _settings; // null เมื่อหน้านี้ถูก pump เดี่ยว ๆ ในเทสต์
  late final Listenable _uiListenable;
  bool? _isRouteCurrent;
  bool _isAppResumed = true;

  /// ระยะขอบบน/ล่างของทั้งหน้า
  static const double _screenPadding = 12;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = VideoInferenceController(
      // ใช้ TrafficVoiceService ตัวเดียวกับทั้งแอป ค่าเสียงจากหน้า Settings จึงมีผลที่นี่ด้วย
      voiceService: readOptionalProvider<TrafficVoiceService>(context),
    );
    _controller.addListener(_onControllerNotification);

    final settings = readOptionalProvider<SettingsProvider>(context);
    _settings = settings;
    if (settings != null) {
      _applyDetectionSettings();
      settings.addListener(_applyDetectionSettings);
    }
    // UI ต้อง rebuild ทั้งตอน controller เปลี่ยน และตอนผู้ใช้เปลี่ยนค่าในหน้า Settings
    if (settings == null) {
      _uiListenable = _controller;
    } else {
      _uiListenable = Listenable.merge([_controller, settings]);
    }

    _controller.initializeModels();
  }

  /// ส่งค่า threshold ของผู้ใช้ให้ controller (โหมดวิดีโอกรองด้วยกติกาเดียวกับกล้อง)
  void _applyDetectionSettings() {
    final settings = _settings;
    if (settings == null) return;
    _controller.applyDetectionSettings(
      confidenceThreshold: settings.confidenceThreshold,
    );
  }

  /// สถานะเปิด/ปิดเสียงที่ใช้แสดงบนปุ่ม
  /// อ่านจาก SettingsProvider เป็นหลัก เพราะเป็นเจ้าของค่าที่บันทึกไว้
  bool get _isVoiceEnabled {
    final settings = _settings;
    if (settings == null) {
      return _controller.isVoiceEnabled;
    }
    return settings.isVoiceEnabled;
  }

  /// สลับเปิด/ปิดเสียงผ่าน SettingsProvider เพื่อให้ทั้งแอปเห็นค่าเดียวกัน
  /// (ถ้าสั่งที่ service ตรง ๆ สวิตช์ในหน้า Settings จะค้างค่าเก่า)
  void _toggleVoice() {
    final settings = _settings;
    if (settings == null) {
      _controller.toggleVoice();
      return;
    }
    unawaited(settings.toggleVoice(!settings.isVoiceEnabled));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    bool isCurrent;
    if (route == null) {
      isCurrent = true;
    } else {
      isCurrent = route.isCurrent;
    }
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
    final routeCurrent = _isRouteCurrent;
    bool isRouteCurrent;
    if (routeCurrent == null) {
      isRouteCurrent = true;
    } else {
      isRouteCurrent = routeCurrent;
    }
    final shouldPlay = isRouteCurrent && _isAppResumed;
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
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(message)));
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
    _settings?.removeListener(_applyDetectionSettings);
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
            listenable: _uiListenable,
            builder: (context, _) {
              final bool hasVideoResult =
                  _controller.videoController != null &&
                  _controller.videoController!.value.isInitialized;

              double horizontalPadding;
              if (isLandscape) {
                horizontalPadding = 24.0;
              } else {
                horizontalPadding = 16.0;
              }

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
                    isVoiceEnabled: _isVoiceEnabled,
                    onTogglePlayPause: _controller.togglePlayPause,
                    onToggleVoice: _toggleVoice,
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
              String statusText;
              if (hasVideoResult) {
                if (_controller.videoController!.value.isPlaying) {
                  statusText = 'กำลังตรวจจับแบบเรียลไทม์';
                } else {
                  statusText = 'หยุดชั่วคราว';
                }
              } else if (_controller.isProcessing) {
                statusText = _controller.progressText;
              } else {
                statusText = 'พร้อมตรวจจับวิดีโอ';
              }

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
                statusText: statusText,
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

    // null = ให้ indicator หมุนแบบไม่ระบุความคืบหน้า (ยังไม่รู้สัดส่วนงาน)
    double? indicatorValue;
    if (hasDeterminateProgress) {
      indicatorValue = progressValue;
    } else {
      indicatorValue = null;
    }

    String progressLabel;
    if (progressText.isEmpty) {
      progressLabel = 'กำลังวิเคราะห์วิดีโอ...';
    } else {
      progressLabel = progressText;
    }

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
                        value: indicatorValue,
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
                progressLabel,
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
                    value: indicatorValue,
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
    // ปิดปุ่มจนกว่าโมเดลจะพร้อม (null = ปุ่มถูก disable)
    VoidCallback? onPickPressed;
    if (areModelsReady) {
      onPickPressed = onPickVideo;
    } else {
      onPickPressed = null;
    }

    String pickButtonLabel;
    if (areModelsReady) {
      pickButtonLabel = 'เลือกวิดีโอจากคลัง';
    } else {
      pickButtonLabel = 'กำลังโหลดโมเดล...';
    }

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
                      onPressed: onPickPressed,
                      icon: const Icon(Icons.video_library_outlined),
                      label: Text(pickButtonLabel),
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
