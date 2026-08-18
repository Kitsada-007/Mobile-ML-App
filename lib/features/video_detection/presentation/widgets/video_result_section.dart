import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/widgets/video_bounding_box_overlay.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:video_player/video_player.dart';

/// ส่วนแสดงผลวิดีโอผลลัพธ์หลังประมวลผลเสร็จ
class ResultVideoSection extends StatelessWidget {
  final VideoPlayerController controller;
  final List<YOLOResult> detections;
  final bool isVoiceEnabled;
  final VoidCallback onTogglePlayPause;
  final VoidCallback? onToggleVoice;
  final VoidCallback? onPickNewVideo;
  final String? fileName;

  const ResultVideoSection({
    super.key,
    required this.controller,
    this.detections = const [],
    this.isVoiceEnabled = true,
    required this.onTogglePlayPause,
    this.onToggleVoice,
    this.onPickNewVideo,
    this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    final videoSize = controller.value.size;

    // ขนาดวิดีโอยังเป็น 0 ตอนที่ controller ยังไม่พร้อม จึงต้องมีค่าสำรองไว้ก่อน
    double fallbackWidth;
    if (videoSize.width == 0) {
      fallbackWidth = 1080.0;
    } else {
      fallbackWidth = videoSize.width;
    }

    double fallbackHeight;
    if (videoSize.height == 0) {
      fallbackHeight = 1920.0;
    } else {
      fallbackHeight = videoSize.height;
    }

    final isPlaying = controller.value.isPlaying;

    String playPauseTooltip;
    IconData playPauseIcon;
    if (isPlaying) {
      playPauseTooltip = 'พักวิดีโอ';
      playPauseIcon = Icons.pause_rounded;
    } else {
      playPauseTooltip = 'เล่นวิดีโอ';
      playPauseIcon = Icons.play_arrow_rounded;
    }

    String voiceTooltip;
    Color voiceForegroundColor;
    IconData voiceIcon;
    if (isVoiceEnabled) {
      voiceTooltip = 'ปิดเสียง';
      voiceForegroundColor = const Color(0xFF34C759);
      voiceIcon = Icons.volume_up_rounded;
    } else {
      voiceTooltip = 'เปิดเสียง';
      voiceForegroundColor = Colors.white60;
      voiceIcon = Icons.volume_off_rounded;
    }

    return Stack(
      fit: StackFit.expand, // บังคับให้ขยายเต็ม Container กว้างๆ ที่ส่งมา
      children: [
        FittedBox(
          fit: BoxFit.cover, // ซูมวิดีโอให้เต็มกรอบ ตัดขอบที่ล้นทิ้ง
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: fallbackWidth,
            height: fallbackHeight,
            child: Stack(
              children: [
                VideoPlayer(controller),
                Positioned.fill(
                  child: VideoBoundingBoxOverlay(
                    detections: detections,
                    videoSize: videoSize,
                  ),
                ),
              ],
            ),
          ),
        ),

        //UI ควบคุม (ลอยอยู่ด้านบนสุด ขนาดไม่ถูกซูมตามวิดีโอ)
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
        Positioned(
          top: 14,
          left: 14,
          child: _VideoLiveBadge(
            isPlaying: isPlaying,
            hasDetections: detections.isNotEmpty,
          ),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.filled(
                tooltip: playPauseTooltip,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                ),
                icon: Icon(playPauseIcon),
                onPressed: onTogglePlayPause,
              ),
              if (onToggleVoice != null) ...[
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: voiceTooltip,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: voiceForegroundColor,
                  ),
                  icon: Icon(voiceIcon),
                  onPressed: onToggleVoice,
                ),
              ],
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
    );
  }
}

/// ป้ายสถานะสด (Live Badge) แสดงที่มุมบนซ้ายของวิดีโอ
class _VideoLiveBadge extends StatelessWidget {
  const _VideoLiveBadge({required this.isPlaying, required this.hasDetections});

  final bool isPlaying;
  final bool hasDetections;

  @override
  Widget build(BuildContext context) {
    Color statusDotColor;
    if (isPlaying) {
      statusDotColor = const Color(0xFF34C759);
    } else {
      statusDotColor = Colors.orangeAccent;
    }

    // ผลตรวจจับสำคัญกว่าสถานะเล่น/พัก จึงเช็คก่อนเป็นอันดับแรก
    String statusText;
    if (hasDetections) {
      statusText = 'ตรวจจับแล้ว';
    } else if (isPlaying) {
      statusText = 'กำลังตรวจจับ';
    } else {
      statusText = 'พักวิดีโอ';
    }

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
                color: statusDotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              statusText,
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
