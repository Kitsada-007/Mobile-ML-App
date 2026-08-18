import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/widgets/video_bounding_box_overlay.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:video_player/video_player.dart';

/// ส่วนแสดงผลวิดีโอผลลัพธ์หลังประมวลผลเสร็จ
/// - เล่นวิดีโอแบบ loop พร้อม overlay bounding box แบบ realtime
/// - มีปุ่มควบคุม: เล่น/หยุด, เปิด/ปิดเสียง, เลือกวิดีโอใหม่
/// - มีแถบ progress วิดีโอ + ป้ายสถานะสด (live badge)
class ResultVideoSection extends StatelessWidget {
  final VideoPlayerController controller;
  final List<YOLOResult> detections;
  final bool isVoiceEnabled;
  final VoidCallback onTogglePlayPause;

  /// null = ซ่อนปุ่ม
  final VoidCallback? onToggleVoice;

  /// null = ซ่อนปุ่ม
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
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
            // สัดส่วนตามวิดีโอจริง (fallback 16:9 ถ้ายังไม่มีค่า)
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio == 0
                  ? 16 / 9
                  : controller.value.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.bottomCenter,
                children: [
                  Container(
                    color: Colors.black,
                    child: VideoPlayer(controller),
                  ),
                  Positioned.fill(
                    child: VideoBoundingBoxOverlay(
                      detections: detections,
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
                  Positioned(
                    top: 14,
                    left: 14,
                    child: _VideoLiveBadge(
                      isPlaying: controller.value.isPlaying,
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
        ),
        if (fileName != null || onPickNewVideo != null) ...[
          const SizedBox(height: 10),
          _SelectedVideoInfoBar(
            fileName: fileName,
            onPickNewVideo: onPickNewVideo,
          ),
        ],
      ],
    );
  }
}

/// แถบข้อมูลวิดีโอที่เลือก พร้อมปุ่มเปลี่ยนวิดีโอรอง
class _SelectedVideoInfoBar extends StatelessWidget {
  const _SelectedVideoInfoBar({this.fileName, this.onPickNewVideo});

  final String? fileName;
  final VoidCallback? onPickNewVideo;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E242B) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.movie_outlined, size: 20, color: Color(0xFF0B9A5A)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fileName ?? 'วิดีโอที่เลือก',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          if (onPickNewVideo != null) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onPickNewVideo,
              icon: const Icon(Icons.video_library_rounded, size: 16),
              label: const Text('เปลี่ยนวิดีโอ'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0B9A5A),
                side: const BorderSide(color: Color(0xFF0B9A5A)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ],
      ),
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
