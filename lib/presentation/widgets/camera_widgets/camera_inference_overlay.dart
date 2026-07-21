import 'package:flutter/material.dart';

import 'detection_stats_display.dart';

/// Compact top HUD rendered over the fullscreen camera preview.
class CameraInferenceOverlay extends StatelessWidget {
  const CameraInferenceOverlay({
    super.key,
    required this.detectionCount,
    required this.currentFps,
    required this.isLandscape,
    required this.onBack,
  });

  final int detectionCount;
  final double currentFps;
  final bool isLandscape;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        minimum: EdgeInsets.fromLTRB(
          isLandscape ? 8 : 12,
          isLandscape ? 6 : 8,
          isLandscape ? 8 : 12,
          0,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: IconButton(
                tooltip: 'ย้อนกลับ',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DetectionStatsDisplay(
                detectionCount: detectionCount,
                currentFps: currentFps,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
