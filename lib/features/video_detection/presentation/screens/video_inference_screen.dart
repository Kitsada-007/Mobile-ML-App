import 'dart:async'; // ชุดช่วยทำงาน async
import 'package:flutter/material.dart'; // ชุด UI หลักของ Flutter
import 'package:trffic_ilght_app/features/video_detection/presentation/widgets/video_detection_panel.dart'; // แผงแสดงผลการตรวจจับวิดีโอ (เฉพาะฝั่ง Video)
import 'package:trffic_ilght_app/features/video_detection/presentation/controllers/video_inference_controller.dart'; // Controller ฝั่ง Business logic
import 'package:trffic_ilght_app/features/video_detection/presentation/widgets/video_result_section.dart'; // วิดเจ็ตแสดงผลวิดีโอ + overlay

/// หน้า Screen สำหรับ UI ของการตรวจจับวิดีโอ
/// ฝั่งนี้เป็นแค่ pure UI rendering และส่งต่อ business logic ทั้งหมดให้ [VideoInferenceController]
class VideoInferenceScreen extends StatefulWidget {
  const VideoInferenceScreen({super.key});

  @override
  State<VideoInferenceScreen> createState() => _VideoInferenceScreenState();
}

class _VideoInferenceScreenState extends State<VideoInferenceScreen>
    with WidgetsBindingObserver {
  late final VideoInferenceController
  _controller; // สร้าง controller เป็น late final
  bool? _isRouteCurrent;
  bool _isAppResumed = true;

  /// ระยะขอบบน/ล่างของทั้งหน้า (ใช้คำนวณความสูงที่เหลือด้วย)
  static const double _screenPadding = 12;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // สร้าง Controller, ลงทะเบียนฟังการแจ้งเตือน และเริ่มโหลดโมเดลทันที
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
      return; // ถ้า widget ถูกถอดออกจาก tree แล้ว ไม่ทำงาน (กัน error)
    }
    // ถ้ามีข้อความ SnackBar ให้แสดงเป็น SnackBar แล้วล้างออกทันทีเพื่อไม่ให้แสดงซ้ำ
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
    // ถอด listener และปล่อย controller (ซึ่งจะปล่อยโมเดล/วิดีโอ/เสียงด้วย)
    _controller.removeListener(_onControllerNotification);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ตรวจสอบว่าจอเป็นแนวนอนหรือแนวตั้ง เพื่อปรับ layout ให้เหมาะสม
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final colorScheme = Theme.of(context).colorScheme; // ธีมสีของแอป

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          unawaited(_controller.pause());
        }
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface, // พื้นหลังใช้สีจากธีม
        body: SafeArea(
          // กันเนื้อหาชนกับพื้นที่สถานะ/แถบนำทางของระบบ
          // ListenableBuilder: rebuild เฉพาะส่วนนี้เมื่อ controller มีการเปลี่ยนแปลง
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              // มีวิดีโอผลลัพธ์ที่พร้อมเล่นหรือไม่ (สร้าง + initialize แล้ว)
              final bool hasVideoResult =
                  _controller.videoController != null &&
                  _controller.videoController!.value.isInitialized;

              // LayoutBuilder: รู้ความสูงที่เหลือจริง จึงจัดเนื้อหาให้เต็มจอได้
              return LayoutBuilder(
                builder: (context, constraints) {
                  final horizontalPadding = isLandscape ? 24.0 : 16.0;
                  final availableHeight = constraints.maxHeight.isFinite
                      ? (constraints.maxHeight - _screenPadding * 2).clamp(
                          0.0,
                          double.infinity,
                        )
                      : 0.0;
                  // จอเตี้ยต้องแบ่งให้การ์ดน้อยลง ไม่งั้นแผงผลถูกดันตกขอบจนต้องเลื่อนหา
                  final cardHeight =
                      (availableHeight * (availableHeight >= 720 ? 0.55 : 0.45))
                          .clamp(180.0, 560.0);

                  final header = _VideoHeader(
                    showModelProgress: !_controller.areModelsReady,
                    onBack: () {
                      unawaited(_controller.pause());
                      Navigator.maybePop(context);
                    },
                  );

                  // การ์ดหลัก: แสดงตามสถานะ 3 แบบ
                  // 1. มีผลลัพธ์วิดีโอ -> วิดีโอ + overlay + ปุ่มควบคุม (คงสัดส่วนวิดีโอจริง)
                  // 2. กำลังประมวลผล -> การ์ดความคืบหน้า
                  // 3. ยังไม่ได้เลือกวิดีโอ -> การ์ดชวนให้เลือกวิดีโอ
                  final Widget mainCard;
                  if (hasVideoResult) {
                    mainCard = ResultVideoSection(
                      controller: _controller.videoController!,
                      detections: _controller.currentFrameDetections,
                      isVoiceEnabled: _controller.isVoiceEnabled,
                      onTogglePlayPause: _controller.togglePlayPause,
                      onToggleVoice: _controller.toggleVoice,
                      onPickNewVideo: _controller.pickVideo,
                    );
                  } else if (_controller.isProcessing) {
                    mainCard = _VideoProcessingCard(
                      progressValue: _controller.progressValue,
                      progressText: _controller.progressText,
                      height: cardHeight,
                    );
                  } else {
                    mainCard = _VideoPickerPlaceholderCard(
                      areModelsReady: _controller.areModelsReady,
                      onPickVideo: _controller.pickVideo,
                      height: cardHeight,
                    );
                  }

                  final panel = VideoDetectionPanel(
                    formalNames: _controller.currentFormalNames,
                    alertMessages: _controller.currentAlertMessages,
                    detectedNumber: _controller.currentDetectedNumber,
                    driverSignalResult: _controller.currentDriverSignalResult,
                    isLandscape: isLandscape,
                    // isPipelineStale: จริงเมื่อไม่ได้ประมวลผล และยังไม่มีผลตรวจจับในเฟรม
                    isPipelineStale:
                        !_controller.isProcessing &&
                        _controller.currentFrameDetections.isEmpty &&
                        _controller.currentDetectedNumber == null,
                    // กำหนดข้อความสถานะตามสถานะปัจจุบันของวิดีโอ
                    statusText: hasVideoResult
                        ? (_controller.videoController!.value.isPlaying
                              ? 'กำลังตรวจจับแบบเรีลไทม์'
                              : 'หยุดชั่วคราว')
                        : _controller.isProcessing
                        ? _controller.progressText
                        : 'พร้อมตรวจจับวิดีโอ',
                    lastDetectionConfidence: _controller.lastDetectionConfidence,
                  );

                  // แนวนอน: จอเตี้ยแต่กว้าง จึงวางวิดีโอคู่กับแผงผล
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
                                Expanded(
                                  flex: 3,
                                  // วิดีโอแนวตั้งสูงเกินจอได้ จึงให้เลื่อนดูได้แทนการล้นขอบ
                                  child: SingleChildScrollView(
                                    child: mainCard,
                                  ),
                                ),
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

                  // แนวตั้ง: ใช้ SingleChildScrollView ให้เลื่อนดูได้เมื่อเนื้อหายาว
                  return SingleChildScrollView(
                    key: const Key('videoDetectionScrollView'),
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      _screenPadding,
                      horizontalPadding,
                      _screenPadding,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        // minHeight ดันเนื้อหาให้สูงเท่าจอเสมอ จึงไม่เหลือช่องว่างค้างด้านล่าง
                        constraints: BoxConstraints(
                          maxWidth: 720,
                          minHeight: availableHeight,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            header,
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: mainCard,
                            ),
                            panel,
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// ส่วนหัวของหน้า: ปุ่มย้อนกลับ + ชื่อหน้า + แถบโหลดโมเดล (ถ้ายังไม่พร้อม)
class _VideoHeader extends StatelessWidget {
  const _VideoHeader({required this.showModelProgress, required this.onBack});

  final bool showModelProgress; // โมเดลยังโหลดไม่เสร็จหรือไม่
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            // ปุ่มย้อนกลับ (มี Semantics เพื่อ Accessibility)
            Semantics(
              button: true,
              label: 'ย้อนกลับ',
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: onBack,
              ),
            ),
            const SizedBox(width: 8),
            // ชื่อหน้า + คำอธิบายสั้น
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
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ),
          ],
        ),
        // แถบโหลดแบบเส้น ถ้าโมเดลยังโหลดไม่เสร็จ
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

/// การ์ดแสดงความคืบหน้า (Progress) ขณะประมวลผลวิดีโอ
class _VideoProcessingCard extends StatelessWidget {
  const _VideoProcessingCard({
    required this.progressValue,
    required this.progressText,
    required this.height,
  });

  final double progressValue; // ค่าความคืบหน้า 0.0 - 1.0
  final String progressText; // ข้อความอธิบายขั้นตอน
  final double height; // ความสูงที่หน้าจอจัดสรรให้

  @override
  Widget build(BuildContext context) {
    final percent = (progressValue * 100).clamp(0, 100).toInt();
    final hasDeterminateProgress = progressValue > 0;

    return DecoratedBox(
      // กล่องดำ + เงาใต้การ์ด
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
        // ตัดมุมโค้งให้กับเนื้อหาด้านในด้วย
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // วงกลมแจ้งความคืบหน้า: รวม CircularProgressIndicator + ตัวเลข % ไว้ที่เดียวกัน
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
                // ข้อความสถานะการทำงาน (ข้อความอธิบายใต้ตัวหมุน/ตัวเลข)
                Text(
                  progressText.isEmpty
                      ? 'กำลังวิเคราะห์วิดีโอ...'
                      : progressText,
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
                // แถบ Progress แบบเส้นตรง: จัดให้อยู่ใต้ข้อความและวงกลมประมวลผลอย่างสมดุล
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
      ),
    );
  }
}

/// การ์ดชวนเลือกวิดีโอ เมื่อยังไม่เลือกไฟล์ (Placeholder)
class _VideoPickerPlaceholderCard extends StatelessWidget {
  const _VideoPickerPlaceholderCard({
    required this.areModelsReady,
    required this.onPickVideo,
    required this.height,
  });

  final bool areModelsReady; // โมเดลพร้อมแล้วหรือยัง (ปุ่มเปิด/ปิดตามนี้)
  final VoidCallback onPickVideo; // callback กดปุ่มเลือกวิดีโอ
  final double height; // ความสูงที่หน้าจอจัดสรรให้

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
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // พื้นหลังไล่สีเข้ม + ไอคอนวิดีโอขนาดใหญ่
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
              // ข้อความชวน + ปุ่มเลือกวิดีโอ (คั่นกลาง)
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
                      // ปุ่มเลือกวิดีโอ (disabled ถ้าโมเดลยังไม่พร้อม)
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
