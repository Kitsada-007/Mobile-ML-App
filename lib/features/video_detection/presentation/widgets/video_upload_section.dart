import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoUploadSection extends StatelessWidget {
  const VideoUploadSection({
    super.key,
    required this.processing,
    required this.videoFile,
    required this.previewController,
    required this.progressValue,
    required this.progressText,
    required this.onPickVideo,
    required this.onRunInference,
  });

  final bool processing;
  final File? videoFile;
  final VideoPlayerController? previewController;
  final double progressValue;
  final String progressText;
  final VoidCallback onPickVideo;
  final VoidCallback onRunInference;

  static const green = Color(0xFF16A05D);
  static const grey = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    final selected = videoFile != null;
    final previewReady = previewController?.value.isInitialized == true;
    final duration = previewReady ? previewController!.value.duration : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _VideoPickerCard(
          selected: selected,
          processing: processing,
          previewReady: previewReady,
          previewController: previewController,
          fileName: videoFile?.path.split(Platform.pathSeparator).last,
          duration: duration,
          onPickVideo: onPickVideo,
        ),
        const SizedBox(height: 16),
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

  final bool selected;
  final bool processing;
  final bool previewReady;
  final VideoPlayerController? previewController;
  final String? fileName;
  final Duration? duration;
  final VoidCallback onPickVideo;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (previewReady)
                  VideoPlayer(previewController!)
                else
                  _EmptyVideoPreview(),
                if (selected) ...[
                  Positioned(
                    top: 12,
                    left: 12,
                    child: _StatusPill(
                      label: processing ? 'กำลังวิเคราะห์' : 'พร้อมวิเคราะห์',
                      color: processing ? const Color(0xFF6B7280) : const Color(0xFF16A05D),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton(
                      tooltip: 'เปลี่ยนวิดีโอ',
                      onPressed: processing ? null : onPickVideo,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black45,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.video_camera_back_rounded),
                    ),
                  ),
                  Center(
                    child: IconButton(
                      tooltip: 'เล่นตัวอย่างวิดีโอ',
                      onPressed: () {
                        final controller = previewController;
                        if (controller == null) return;
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: selected
                ? Row(
                    children: [
                      const Icon(Icons.movie_outlined, color: Color(0xFF16A05D)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          fileName ?? 'วิดีโอที่เลือก',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                        ),
                      ),
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
                        'รองรับ MP4, MOV',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: onPickVideo,
                        icon: const Icon(Icons.video_library_outlined),
                        label: const Text('เลือกวิดีโอ'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF16A05D),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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

class _EmptyVideoPreview extends StatelessWidget {
  const _EmptyVideoPreview();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .94), borderRadius: BorderRadius.circular(999)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _VideoAnalysisButton extends StatelessWidget {
  const _VideoAnalysisButton({
    required this.enabled,
    required this.processing,
    required this.progressValue,
    required this.progressText,
    required this.onPressed,
  });

  final bool enabled;
  final bool processing;
  final double progressValue;
  final String progressText;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: processing
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.play_arrow_rounded),
      label: Text(processing ? progressText : enabled ? 'เริ่มวิเคราะห์วิดีโอ' : 'เลือกวิดีโอก่อน'),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF16A05D),
        disabledBackgroundColor: const Color(0xFFE5E7EB),
        disabledForegroundColor: const Color(0xFF6B7280),
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

String _formatDuration(Duration? duration) {
  if (duration == null) return '--:--';
  final minutes = duration.inMinutes.toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
