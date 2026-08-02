import 'package:flutter/material.dart';

import 'detection_stats_display.dart';

/// Compact top HUD rendered over the fullscreen camera preview.
class CameraInferenceOverlay extends StatelessWidget {
  const CameraInferenceOverlay({
    super.key,
    required this.detectionCount,
    required this.currentFps,
    required this.isLandscape,
    required this.onLeadingPressed,
    this.showMenuButton = false,
  });

  final int detectionCount;
  final double currentFps;
  final bool isLandscape;
  final VoidCallback onLeadingPressed;
  final bool showMenuButton;

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
        child: Column(
          children: [
            Row(
              children: [
                _RoundOverlayButton(
                  key: const Key('cameraNavigationButton'),
                  tooltip: showMenuButton ? 'เปิดเมนู' : 'ย้อนกลับ',
                  icon: showMenuButton
                      ? Icons.menu_rounded
                      : Icons.arrow_back_rounded,
                  onPressed: onLeadingPressed,
                ),
                const SizedBox(width: 12),
                const Expanded(child: _BrandBadge()),
              ],
            ),
            const SizedBox(height: 8),
            DetectionStatsDisplay(
              detectionCount: detectionCount,
              currentFps: currentFps,
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandBadge extends StatelessWidget {
  const _BrandBadge();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Flexible(
            child: Text(
              'Berng Fai',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.8,
                shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF63E681),
              borderRadius: BorderRadius.circular(99),
            ),
            child: const Text(
              'LIVE',
              style: TextStyle(
                color: Colors.black,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundOverlayButton extends StatelessWidget {
  const _RoundOverlayButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}
