import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/widgets/video_bounding_box_overlay.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:video_player/video_player.dart';

class ResultVideoSection extends StatelessWidget {
  final VideoPlayerController controller;
  final List<YOLOResult> detections;
  final String? detectedNumber;
  final bool isVoiceEnabled;
  final VoidCallback onOpenFullScreen;
  final VoidCallback onTogglePlayPause;
  final VoidCallback? onToggleVoice;
  final VoidCallback? onPickNewVideo;

  const ResultVideoSection({
    super.key,
    required this.controller,
    this.detections = const [],
    this.detectedNumber,
    this.isVoiceEnabled = true,
    required this.onOpenFullScreen,
    required this.onTogglePlayPause,
    this.onToggleVoice,
    this.onPickNewVideo,
  });

  @override
  Widget build(BuildContext context) {
    final videoSize = controller.value.size;

    return DecoratedBox(
      key: const Key('videoPreviewCard'),
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
          aspectRatio: controller.value.aspectRatio == 0
              ? 16 / 9
              : controller.value.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.bottomCenter,
            children: [
              Container(color: Colors.black, child: VideoPlayer(controller)),
              // Real-time Bounding Box Overlay
              Positioned.fill(
                child: VideoBoundingBoxOverlay(
                  detections: detections,
                  detectedNumber: detectedNumber,
                  videoSize: videoSize,
                ),
              ),
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
              // Live Status Badge
              Positioned(
                top: 14,
                left: 14,
                child: _VideoLiveBadge(
                  isPlaying: controller.value.isPlaying,
                  hasDetections:
                      detections.isNotEmpty || detectedNumber != null,
                ),
              ),
              // Action Controls (Play/Pause, Sound Toggle, Fullscreen, Change Video)
              Positioned(
                top: 10,
                right: 10,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                    if (onToggleVoice != null) ...[
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: isVoiceEnabled
                            ? 'ปิดเสียงการแจ้งเตือน'
                            : 'เปิดเสียงการแจ้งเตือน',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          foregroundColor: isVoiceEnabled
                              ? const Color(0xFF34C759)
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
                    IconButton.filled(
                      tooltip: 'แสดงเต็มจอ',
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.fullscreen_rounded),
                      onPressed: onOpenFullScreen,
                    ),
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

class _VideoLiveBadge extends StatelessWidget {
  const _VideoLiveBadge({required this.isPlaying, required this.hasDetections});

  final bool isPlaying;
  final bool hasDetections;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
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
