import 'package:flutter/material.dart'; // ชุด UI หลักของ Flutter
import 'package:trffic_ilght_app/features/camera_detection/presentation/widgets/camera_detection_panel.dart'; // แผงแสดงผลการตรวจจับ (ใช้ร่วมกับหน้าหนัง)
import 'package:trffic_ilght_app/features/video_detection/presentation/controllers/video_inference_controller.dart'; // Controller ฝั่ง Business logic
import 'package:trffic_ilght_app/features/video_detection/presentation/widgets/video_result_section.dart'; // วิดเจ็ตแสดงผลวิดีโอ + overlay

/// หน้า Screen สำหรับ UI ของการตรวจจับวิดีโอ
/// ฝั่งนี้เป็นแค่ pure UI rendering และส่งต่อ business logic ทั้งหมดให้ [VideoInferenceController]
class VideoInferenceScreen extends StatefulWidget {
  const VideoInferenceScreen({super.key});

  @override
  State<VideoInferenceScreen> createState() => _VideoInferenceScreenState();
}

class _VideoInferenceScreenState extends State<VideoInferenceScreen> {
  late final VideoInferenceController
  _controller; // สร้าง controller เป็น late final

  @override
  void initState() {
    super.initState();
    // สร้าง Controller, ลงทะเบียนฟังการแจ้งเตือน และเริ่มโหลดโมเดลทันที
    _controller = VideoInferenceController();
    _controller.addListener(_onControllerNotification);
    _controller.initializeModels();
  }

  /// ตอบสนองเมื่อ controller notifyListeners()
  void _onControllerNotification() {
    if (!mounted) {
      return; // ถ้า widget ถูกถอดออกจาก tree แล้ว ไม่ทำงาน (กัน error)
    }
    // ถ้ามีข้อความ SnackBar ให้แสดงเป็น SnackBar
    if (_controller.snackBarMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_controller.snackBarMessage!)));
    }
    setState(() {}); // rebuild UI เพื่อให้แสดงสถานะล่าสุด
  }

  @override
  void dispose() {
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

    return Scaffold(
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

            // ใช้ SingleChildScrollView ให้เลื่อนดูได้เมื่อเนื้อหายาว (หมุนจอ)
            return SingleChildScrollView(
              key: const Key('videoDetectionScrollView'),
              padding: EdgeInsets.fromLTRB(
                isLandscape ? 24 : 16, // ขอบตามแนวนอน/แนวตั้ง
                8,
                isLandscape ? 24 : 16,
                24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 720,
                  ), // จำกัดความกว้างให้งามบนจอใหญ่
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.stretch, // ให้ลูกทุกตัวกว้างเต็ม
                    children: [
                      // ---------- Header Row (ย้อนกลับ + ชื่อหน้า + เลือกวิดีโอ) ----------
                      Row(
                        children: [
                          // ปุ่มย้อนกลับ (มี Semantics เพื่อ Accessibility)
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
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // ปุ่มเลือกวิดีโอ (ปิดการใช้งานตอนกำลังประมวลผล)
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

                      // แสดงแถบโหลดแบบเส้น ถ้าโมเดลยังโหลดไม่เสร็จ
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

                      // ---------- การ์ดหลัก: แสดงตามสถานะ 3 แบบ ----------
                      // 1. มีผลลัพธ์วิดีโอ -> แสดงวิดีโอ + overlay + ปุ่มควบคุม
                      if (hasVideoResult) ...[
                        ResultVideoSection(
                          controller: _controller.videoController!,
                          detections: _controller.currentFrameDetections,
                          detectedNumber: _controller.currentDetectedNumber,
                          isVoiceEnabled: _controller.isVoiceEnabled,

                          onTogglePlayPause: _controller.togglePlayPause,
                          onToggleVoice: _controller.toggleVoice,
                          onPickNewVideo: _controller.pickVideo,
                        ),
                      ] else if (_controller.isProcessing) ...[
                        // 2. กำลังประมวลผล -> แสดงการ์ดความคืบหน้า
                        _VideoProcessingCard(
                          progressValue: _controller.progressValue,
                          progressText: _controller.progressText,
                          isLandscape: isLandscape,
                        ),
                      ] else ...[
                        // 3. ยังไม่ได้เลือกวิดีโอ -> แสดงการ์ดชวนให้เลือกวิดีโอ
                        _VideoPickerPlaceholderCard(
                          areModelsReady: _controller.areModelsReady,
                          onPickVideo: _controller.pickVideo,
                          isLandscape: isLandscape,
                        ),
                      ],

                      const SizedBox(height: 20),

                      // ---------- แผงผลลัพธ์การตรวจจับ (เหมือนหน้า Camera) ----------
                      CameraDetectionPanel(
                        formalNames: _controller.currentFormalNames,
                        alertMessages: _controller.currentAlertMessages,
                        detectedNumber: _controller.currentDetectedNumber,
                        driverSignalResult:
                            _controller.currentDriverSignalResult,
                        isLandscape: isLandscape,
                        // isPipelineStale: จริงเมื่อไม่ได้ประมวลผล และยังไม่มีผลตรวจจับในเฟรม
                        isPipelineStale:
                            !_controller.isProcessing &&
                            _controller.currentFrameDetections.isEmpty &&
                            _controller.currentDetectedNumber == null,
                        // กำหนดข้อความสถานะตามสถานะปัจจุบันของวิดีโอ
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

/// การ์ดแสดงความคืบหน้า (Progress) ขณะประมวลผลวิดีโอ
class _VideoProcessingCard extends StatelessWidget {
  const _VideoProcessingCard({
    required this.progressValue,
    required this.progressText,
    required this.isLandscape,
  });

  final double progressValue; // ค่าความคืบหน้า 0.0 - 1.0
  final String progressText; // ข้อความอธิบายขั้นตอน
  final bool isLandscape; // จอแนวนอนหรือไม่ (ปรับสัดส่วน)

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      // กล่องดำ + เงาใต้การ์ด
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
        // ตัดมุมโค้งให้กับเนื้อหาด้านในด้วย
        borderRadius: BorderRadius.circular(24),
        // สัดส่วนตามการหมุนจอ (16:9 แนวนอน / 4:3 แนวตั้ง)
        child: AspectRatio(
          aspectRatio: isLandscape ? 16 / 9 : 4 / 3,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ไอคอนหมุน (CircularProgressIndicator) สีเขียว
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 4,
                    color: Color(0xFF34C759),
                  ),
                ),
                const SizedBox(height: 20),
                // ข้อความสถานะการทำงาน (fallback ข้อความเสมอถ้าช่องว่าง)
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
                // แถบ progress (ไม่มีกำหนดค่า -> ใช้ mode อนิเมชันแบบ indeterminate)
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

/// การ์ดชวนเลือกวิดีโอ เมื่อยังไม่เลือกไฟล์ (Placeholder)
class _VideoPickerPlaceholderCard extends StatelessWidget {
  const _VideoPickerPlaceholderCard({
    required this.areModelsReady,
    required this.onPickVideo,
    required this.isLandscape,
  });

  final bool areModelsReady; // โมเดลพร้อมแล้วหรือยัง (ปุ่มเปิด/ปิดตามนี้)
  final VoidCallback onPickVideo; // callback กดปุ่มเลือกวิดีโอ
  final bool isLandscape; // ปรับสัดส่วนตามการหมุนจอ

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
