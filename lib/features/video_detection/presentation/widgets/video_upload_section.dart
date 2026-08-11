import 'dart:io'; // ใช้ File และ Platform (ดึงชื่อไฟล์)

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart'; // ตัวเล่นวิดีโอตัวอย่าง

/// ส่วนอัปโหลดวิดีโอ: ประกอบด้วย
/// - การ์ดแสดงตัวอย่างวิดีโอ (preview) + ชื่อไฟล์ + ระยะเวลา
/// - ปุ่มเริ่มวิเคราะห์วิดีโอ (พร้อมแถบความคืบหน้า)
class VideoUploadSection extends StatelessWidget {
  const VideoUploadSection({
    super.key,
    required this.processing, // กำลังประมวลผลหรือไม่
    required this.videoFile, // ไฟล์วิดีโอที่เลือก (null = ยังไม่เลือก)
    required this.previewController, // ตัวเล่นตัวอย่างวิดีโอ
    required this.progressValue, // ความคืบหน้า 0.0-1.0
    required this.progressText, // ข้อความสถานะ
    required this.onPickVideo, // กดเลือกวิดีโอ
    required this.onRunInference, // กดเริ่มวิเคราะห์
  });

  final bool processing;
  final File? videoFile;
  final VideoPlayerController? previewController;
  final double progressValue;
  final String progressText;
  final VoidCallback onPickVideo;
  final VoidCallback onRunInference;

  // สีประจำของ feature นี้
  static const green = Color(0xFF16A05D); // เขียวหลัก
  static const grey = Color(0xFF6B7280); // เทา

  @override
  Widget build(BuildContext context) {
    final selected = videoFile != null; // มีไฟล์ที่เลือกหรือยัง
    final previewReady =
        previewController?.value.isInitialized == true; // preview พร้อมเล่นไหม
    final duration = previewReady
        ? previewController!.value.duration
        : null; // ระยะเวลาวิดีโอ

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // การ์ดเลือก/แสดงตัวอย่างวิดีโอ
        _VideoPickerCard(
          selected: selected,
          processing: processing,
          previewReady: previewReady,
          previewController: previewController,
          // ดึงเฉพาะชื่อไฟล์ (ไม่รวม path ทั้งหมด)
          fileName: videoFile?.path.split(Platform.pathSeparator).last,
          duration: duration,
          onPickVideo: onPickVideo,
        ),
        const SizedBox(height: 16),
        // ปุ่มเริ่มวิเคราะห์ (เปิดใช้งานเมื่อเลือกวิดีโอแล้ว และไม่ได้ประมวลผลอยู่)
        _VideoAnalysisButton(
          enabled: selected && !processing,
          processing: processing,
          progressValue: progressValue,
          progressText: progressText,
          onPressed: onRunInference,
        ),
      ],
    );
  }
}

/// การ์ดแสดงตัวอย่างวิดีโอที่เลือก (มี preview + ปุ่มควบคุม + ชื่อไฟล์)
class _VideoPickerCard extends StatelessWidget {
  const _VideoPickerCard({
    required this.selected,
    required this.processing,
    required this.previewReady,
    required this.previewController,
    required this.fileName,
    required this.duration,
    required this.onPickVideo,
  });

  final bool selected; // มีไฟล์ที่เลือกแล้วหรือยัง
  final bool processing; // กำลังประมวลผลอยู่หรือไม่
  final bool previewReady; // ตัวเล่นพร้อมใช้งานไหม
  final VideoPlayerController? previewController; // ตัวควบคุม preview
  final String? fileName; // ชื่อไฟล์วิดีโอ
  final Duration? duration; // ระยะเวลาวิดีโอ
  final VoidCallback onPickVideo; // callback เลือกวิดีโอ

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme; // ธีมสี
    return Card(
      elevation: 0, // ไม่มีเงา
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ), // มุมโค้ง
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // เนื้อหาหลัก: เล่นตัวอย่างวิดีโอ หรือพื้นที่ว่างเปล่า (ยังไม่เลือกไฟล์)
                if (previewReady)
                  VideoPlayer(previewController!)
                else
                  _EmptyVideoPreview(),
                // ถ้ามีไฟล์ที่เลือกแล้ว แสดงป้ายสถานะ + ปุ่มควบคุม
                if (selected) ...[
                  // ป้ายสถานะที่มุมบนซ้าย (วิเคราะห์/พร้อม)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: _StatusPill(
                      label: processing ? 'กำลังวิเคราะห์' : 'พร้อมวิเคราะห์',
                      color: processing
                          ? const Color(0xFF6B7280)
                          : const Color(0xFF16A05D),
                    ),
                  ),
                  // ปุ่มเปลี่ยนวิดีโอที่มุมบนขวา
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      tooltip: 'เปลี่ยนวิดีโอ',
                      onPressed: processing
                          ? null
                          : onPickVideo, // ปิดระหว่างประมวลผล
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black45,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.video_camera_back_rounded),
                    ),
                  ),
                  // ปุ่มเล่น/หยุดตัวอย่างวิดีโอตรงกลาง
                  Center(
                    child: IconButton(
                      tooltip: 'เล่นตัวอย่างวิดีโอ',
                      onPressed: () {
                        final controller = previewController;
                        if (controller == null) return;
                        // สลับระหว่างเล่น/หยุดตามสถานะปัจจุบัน
                        if (controller.value.isPlaying) {
                          controller.pause();
                        } else {
                          controller.play();
                        }
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black45,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(56, 56),
                      ),
                      icon: Icon(
                        previewController?.value.isPlaying == true
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 34,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // ส่วนล่าง: แสดงชื่อไฟล์ + ระยะเวลา หรือชวนเลือกวิดีโอ (ถ้ายังไม่เลือก)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: selected
                ? Row(
                    children: [
                      const Icon(
                        Icons.movie_outlined,
                        color: Color(0xFF16A05D),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          fileName ?? 'วิดีโอที่เลือก',
                          maxLines: 1,
                          overflow:
                              TextOverflow.ellipsis, // ตัดข้อความถ้ายาวเกิน
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      // แสดงระยะเวลา เช่น 01:30
                      Text(
                        _formatDuration(duration),
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Text(
                        'เลือกวิดีโอเพื่อตรวจจับ',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'รองรับ MP4, MOV', // ระบุรูปแบบที่รองรับ
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 14),
                      // ปุ่มเลือกวิดีโอ
                      FilledButton.icon(
                        onPressed: onPickVideo,
                        icon: const Icon(Icons.video_library_outlined),
                        label: const Text('เลือกวิดีโอ'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF16A05D),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// พื้นที่ว่างเปล่า (แสดงเมื่อยังไม่เลือกวิดีโอ) มีพื้นหลังไล่สีเทา + ไอคอนวิดีโอ
class _EmptyVideoPreview extends StatelessWidget {
  const _EmptyVideoPreview();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          // พื้นหลังไล่สีเทาอ่อน
          colors: [Color(0xFFF0F3F2), Color(0xFFE4E9E7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.video_library_outlined,
          size: 64,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// ป้ายสถานะเล็ก ๆ (มีจุดสี + ข้อความ) เช่น "พร้อมวิเคราะห์"
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label; // ข้อความสถานะ
  final Color color; // สีของจุด + ข้อความ

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      // พื้นขาวโปร่งแสงมุมโค้งเต็ม
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // จุดสถานะสี
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ปุ่มเริ่มวิเคราะห์วิดีโอ (แสดง spinner + ข้อความเมื่อกำลังประมวลผล)
class _VideoAnalysisButton extends StatelessWidget {
  const _VideoAnalysisButton({
    required this.enabled,
    required this.processing,
    required this.progressValue,
    required this.progressText,
    required this.onPressed,
  });

  final bool enabled; // ปุ่มเปิดใช้งานได้หรือไม่
  final bool processing; // กำลังประมวลผลอยู่ไหม
  final double progressValue; // ความคืบหน้า (ไม่ค่อยใช้ในปุ่มนี้)
  final String progressText; // ข้อความสถานะขณะประมวลผล
  final VoidCallback onPressed; // callback กดปุ่ม

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: enabled ? onPressed : null, // ปิดปุ่มเมื่อไร้ความสามารถ
      icon: processing
          // แสดง spinner สีขาวแทนไอคอนเล่นเมื่อกำลังประมวลผล
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.play_arrow_rounded), // ไอคอนเล่นเมื่อพร้อม
      label: Text(
        processing
            ? progressText
            : enabled
            ? 'เริ่มวิเคราะห์วิดีโอ'
            : 'เลือกวิดีโอก่อน',
      ),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF16A05D), // สีเขียวหลัก
        disabledBackgroundColor: const Color(0xFFE5E7EB), // สีเมื่อปิดใช้งาน
        disabledForegroundColor: const Color(0xFF6B7280),
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

/// แปลง Duration เป็นข้อความ MM:SS เช่น 1 นาที 30 วินาที -> "01:30"
String _formatDuration(Duration? duration) {
  if (duration == null) return '--:--';
  final minutes = duration.inMinutes.toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
