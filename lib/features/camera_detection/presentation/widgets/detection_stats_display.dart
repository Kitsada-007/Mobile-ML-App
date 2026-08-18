// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'package:flutter/material.dart';

/// วิดเจ็ตแสดงสถิติการตรวจจับ (จำนวนที่ตรวจพบ และ FPS ปัจจุบัน)
/// - วางทับบนกล้อง (HUD) และกันไม่ให้รับการแตะ (IgnorePointer)
class DetectionStatsDisplay extends StatelessWidget {
  const DetectionStatsDisplay({
    super.key,
    required this.detectionCount,
    required this.currentFps,
  });

  final int detectionCount;
  final double currentFps;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: DecoratedBox(
          key: const Key('cameraStatusHud'),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: FittedBox(
              fit: BoxFit.scaleDown, // ย่อให้พอดีเมื่อเนื้อที่น้อย กัน overflow
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'DETECTIONS: $detectionCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'FPS: ${currentFps.toStringAsFixed(1)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
