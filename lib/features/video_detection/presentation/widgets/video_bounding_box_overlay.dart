import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/yolo.dart';

/// Widget for rendering live Bounding Box Overlay on video player
class VideoBoundingBoxOverlay extends StatelessWidget {
  const VideoBoundingBoxOverlay({
    super.key,
    required this.detections,
    this.detectedNumber,
    required this.videoSize,
  });

  final List<YOLOResult> detections;
  final String? detectedNumber;
  final Size videoSize;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _BoundingBoxPainter(
              detections: detections,
              videoSize: videoSize,
            ),
          ),
        ),
        if (detectedNumber != null && detectedNumber!.isNotEmpty)
          Positioned(
            bottom: 16,
            left: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xB3000000),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF16A05D), width: 2),
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

class _BoundingBoxPainter extends CustomPainter {
  _BoundingBoxPainter({required this.detections, required this.videoSize});

  final List<YOLOResult> detections;
  final Size videoSize;

  Color _getColorForClass(String className) {
    switch (className) {
      case 'red_light':
      case 'red_light_circle':
        return Colors.redAccent;
      case 'green_light':
      case 'green_light_circle':
        return const Color(0xFF16A05D);
      case 'yellow_light':
      case 'yellow_light_circle':
        return Colors.amber;
      case 'sign_number':
        return Colors.cyanAccent;
      default:
        return Colors.blueAccent;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width == 0 || size.height == 0) return;

    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final bgPaint = Paint()..style = PaintingStyle.fill;

    for (final detection in detections) {
      final color = _getColorForClass(detection.className);
      boxPaint.color = color;
      bgPaint.color = color.withValues(alpha: 0.85);

      final normBox = detection.normalizedBox;
      final Rect rect;
      if (normBox.width > 0 && normBox.height > 0) {
        rect = Rect.fromLTRB(
          normBox.left * size.width,
          normBox.top * size.height,
          normBox.right * size.width,
          normBox.bottom * size.height,
        );
      } else {
        final box = detection.boundingBox;
        rect = Rect.fromLTRB(
          box.left * size.width,
          box.top * size.height,
          box.right * size.width,
          box.bottom * size.height,
        );
      }

      // Draw bounding box
      canvas.drawRect(rect, boxPaint);

      // Keep the overlay lightweight for end users: color-coded boxes only.
    }
  }

  @override
  bool shouldRepaint(covariant _BoundingBoxPainter oldDelegate) => true;
}
