import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/yolo.dart'; // โครงสร้าง YOLOResult (ผลการตรวจจับ)

/// วิดเจ็ตสำหรับวาด Bounding Box Overlay แบบ realtime บนตัวเล่นวิดีโอ
class VideoBoundingBoxOverlay extends StatelessWidget {
  const VideoBoundingBoxOverlay({
    super.key,
    required this.detections,
    this.detectedNumber,
    required this.videoSize,
  });

  final List<YOLOResult> detections; // ผลการตรวจจับของเฟรมปัจจุบัน
  final String? detectedNumber; // ตัวเลขนับถอยหลังที่ตรวจจับได้ (ถ้ามี)
  final Size videoSize; // ขนาดของวิดีโอ (ใช้แปลงพิกัด)

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ชั้นที่ 1: วาดกล่อง bounding box ด้วย CustomPaint
        Positioned.fill(
          child: CustomPaint(
            painter: _BoundingBoxPainter(
              detections: detections,
              videoSize: videoSize,
            ),
          ),
        ),
        // ชั้นที่ 2: แสดงป้าย "ถอยหลัง: <เลข>" ที่มุมล่างซ้าย ถ้ามีตัวเลข
        if (detectedNumber != null && detectedNumber!.isNotEmpty)
          Positioned(
            bottom: 16,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xB3000000), // พื้นดำโปร่งแสง
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF16A05D),
                  width: 2,
                ), // กรอบสีเขียว
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    color: Color(0xFF16A05D),
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'ถอยหลัง: $detectedNumber',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// CustomPainter สำหรับวาดกล่อง bounding box และรหัสสีตามคลาสที่ตรวจพบ
class _BoundingBoxPainter extends CustomPainter {
  _BoundingBoxPainter({required this.detections, required this.videoSize});

  final List<YOLOResult> detections;
  final Size videoSize;

  /// คืนค่าสีประจำแต่ละคลาสของสัญญาณไฟจราจร
  Color _getColorForClass(String className) {
    switch (className) {
      case 'red_light':
      case 'red_light_circle':
        return Colors.redAccent; // ไฟแดง -> สีแดง
      case 'green_light':
      case 'green_light_circle':
        return const Color(0xFF16A05D); // ไฟเขียว -> สีเขียว
      case 'yellow_light':
      case 'yellow_light_circle':
        return Colors.amber; // ไฟเหลือง -> สีเหลือง
      case 'sign_number':
        return Colors.cyanAccent; // ป้ายตัวเลข -> สีฟ้า
      default:
        return Colors.blueAccent; // คลาสอื่น ๆ -> สีน้ำเงิน
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // กันกรณีขนาด canvas เป็น 0 (ไม่มีพื้นที่วาด)
    if (size.width == 0 || size.height == 0) return;

    // Paint สำหรับวาดเส้นกล่อง (stroke)
    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Paint สำหรับวาดพื้นหลัง (fill) — เตรียมไว้เผื่ออนาคต
    final bgPaint = Paint()..style = PaintingStyle.fill;

    for (final detection in detections) {
      final color = _getColorForClass(detection.className); // เลือกสีตามคลาส
      boxPaint.color = color;
      bgPaint.color = color.withValues(alpha: 0.85);

      final normBox = detection.normalizedBox; // พิกัดแบบ normalized (0-1)
      final Rect rect;
      // ถ้ามี normalized box -> แปลงสัดส่วนให้ตรงกับขนาดวิดีโอ
      if (normBox.width > 0 && normBox.height > 0) {
        rect = Rect.fromLTRB(
          normBox.left * size.width,
          normBox.top * size.height,
          normBox.right * size.width,
          normBox.bottom * size.height,
        );
      } else {
        // fallback: ใช้ boundingBox ตรง ๆ ถ้าไม่มี normalized box
        final box = detection.boundingBox;
        rect = Rect.fromLTRB(
          box.left * size.width,
          box.top * size.height,
          box.right * size.width,
          box.bottom * size.height,
        );
      }

      // วาดกล่อง bounding box (ตามขนาดที่คำนวณได้)
      canvas.drawRect(rect, boxPaint);
      // หมายเหตุ: overlay ชั้นนี้ตั้งใจให้เบา (สีกล่องแยกตามคลาสเท่านั้น)
      // ไม่วาด label/confidence เพื่อให้ UI ไม่เละบนวิดีโอ
    }
  }

  @override
  bool shouldRepaint(covariant _BoundingBoxPainter oldDelegate) => true;
}
