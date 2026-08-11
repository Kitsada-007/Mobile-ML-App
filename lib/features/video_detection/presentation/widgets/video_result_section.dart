import 'package:flutter/material.dart'; // ชุด UI หลักของ Flutter
import 'package:trffic_ilght_app/features/video_detection/presentation/widgets/video_bounding_box_overlay.dart'; // วิดเจ็ตวาด Bounding Box
import 'package:ultralytics_yolo/yolo.dart'; // โครงสร้าง YOLOResult
import 'package:video_player/video_player.dart'; // ตัวเล่นวิดีโอ

/// ส่วนแสดงผลวิดีโอผลลัพธ์หลังประมวลผลเสร็จ
/// - เล่นวิดีโอแบบ loop พร้อม overlay bounding box แบบ realtime
/// - มีปุ่มควบคุม: เล่น/หยุด, เปิด/ปิดเสียง, เลือกวิดีโอใหม่
/// - มีแถบ progress วิดีโอ + ป้ายสถานะสด (live badge)
class ResultVideoSection extends StatelessWidget {
  final VideoPlayerController controller; // ตัวควบคุมวิดีโอผลลัพธ์
  final List<YOLOResult>
  detections; // ผลตรวจจับของเฟรมปัจจุบัน (ใช้วาด overlay)
  final String? detectedNumber; // ตัวเลขนับถอยหลังปัจจุบัน
  final bool isVoiceEnabled; // เสียงเปิดหรือไม่ (กำหนดสีปุ่ม)
  final VoidCallback onTogglePlayPause; // สลับเล่น/หยุด
  final VoidCallback? onToggleVoice; // สลับเปิด/ปิดเสียง (nullable = ซ่อนปุ่ม)
  final VoidCallback? onPickNewVideo; // เลือกวิดีโอใหม่ (nullable = ซ่อนปุ่ม)

  const ResultVideoSection({
    super.key,
    required this.controller,
    this.detections = const [],
    this.detectedNumber,
    this.isVoiceEnabled = true,

    required this.onTogglePlayPause,
    this.onToggleVoice,
    this.onPickNewVideo,
  });

  @override
  Widget build(BuildContext context) {
    final videoSize =
        controller.value.size; // ขนาดเฟรมวิดีโอ (ใช้แปลงพิกัด overlay)

    return DecoratedBox(
      key: const Key('videoPreviewCard'),
      // กล่องดำพร้อมเงา (เหมือนการ์ดอื่นในหน้าจอ)
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
        // สัดส่วนตามวิดีโอจริง (fallback 16:9 ถ้ายังไม่มีค่า)
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio == 0
              ? 16 / 9
              : controller.value.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.bottomCenter,
            children: [
              // ชั้นวิดีโอตัวจริง
              Container(color: Colors.black, child: VideoPlayer(controller)),
              // ชั้น overlay: วาด bounding box แบบ realtime ทับวิดีโอ
              Positioned.fill(
                child: VideoBoundingBoxOverlay(
                  detections: detections,
                  detectedNumber: detectedNumber,
                  videoSize: videoSize,
                ),
              ),
              // แถบ progress วิดีโอ (ลากเพื่อข้ามเวลาได้)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Color(0xFF16A05D),
                    bufferedColor: Colors.white38,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
              // ป้ายสถานะสดที่มุมบนซ้าย (เล่น/หยุด/ตรวจจับแล้ว)
              Positioned(
                top: 14,
                left: 14,
                child: _VideoLiveBadge(
                  isPlaying: controller.value.isPlaying,
                  hasDetections:
                      detections.isNotEmpty || detectedNumber != null,
                ),
              ),
              // ---------- ปุ่มควบคุมชุด (Play/Pause, เสียง, เลือกวิดีโอใหม่) ----------
              Positioned(
                top: 10,
                right: 10,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ปุ่มเล่น/หยุดวิดีโอ (ไอคอนเปลี่ยนตามสถานะ)
                    IconButton.filled(
                      tooltip: controller.value.isPlaying
                          ? 'พักวิดีโอ'
                          : 'เล่นวิดีโอ',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                      ),
                      icon: Icon(
                        controller.value.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      onPressed: onTogglePlayPause,
                    ),
                    // ปุ่มเปิด/ปิดเสียง (แสดงเฉพาะเมื่อส่ง callback มา)
                    if (onToggleVoice != null) ...[
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: isVoiceEnabled
                            ? 'ปิดเสียงการแจ้งเตือน'
                            : 'เปิดเสียงการแจ้งเตือน',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          foregroundColor: isVoiceEnabled
                              ? const Color(0xFF34C759) // เขียว = เสียงเปิด
                              : Colors.white60,
                        ),
                        icon: Icon(
                          isVoiceEnabled
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                        ),
                        onPressed: onToggleVoice,
                      ),
                    ],

                    // ปุ่มเลือกวิดีโอใหม่ (แสดงเฉพาะเมื่อส่ง callback มา)
                    if (onPickNewVideo != null) ...[
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'เลือกวิดีโอใหม่',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.video_library_rounded),
                        onPressed: onPickNewVideo,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ป้ายสถานะสด (Live Badge) แสดงที่มุมบนซ้ายของวิดีโอ
class _VideoLiveBadge extends StatelessWidget {
  const _VideoLiveBadge({required this.isPlaying, required this.hasDetections});

  final bool isPlaying; // วิดีโอกำลังเล่นหรือไม่
  final bool hasDetections; // มีผลการตรวจจับในเฟรมนี้หรือไม่

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      // กล่องดำโปร่งมุมโค้งพร้อมกรอบขาวบาง ๆ
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
            // จุดไฟสถานะ: เขียว = เล่นอยู่, ส้ม = หยุด
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: isPlaying
                    ? const Color(0xFF34C759)
                    : Colors.orangeAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            // ข้อความแจ้งสถานะปัจจุบัน
            Text(
              hasDetections
                  ? 'ตรวจจับแล้ว'
                  : isPlaying
                  ? 'กำลังตรวจจับ'
                  : 'พักวิดีโอ',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
