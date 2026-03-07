import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/presentation/pages/video_inference_screen.dart';
import 'package:video_player/video_player.dart';

class ResultVideoSection extends StatelessWidget {
  final VideoPlayerController controller;
  final VoidCallback onOpenFullScreen;
  final VoidCallback onTogglePlayPause;

  const ResultVideoSection({
    super.key,
    required this.controller,
    required this.onOpenFullScreen,
    required this.onTogglePlayPause,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Result Video",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio == 0
                        ? 16 / 9
                        : controller.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        Container(
                          color: Colors.black,
                          child: VideoPlayer(controller),
                        ),
                        VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: Colors.blueAccent,
                            bufferedColor: Colors.white38,
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Material(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(12),
                            child: IconButton(
                              onPressed: onOpenFullScreen,
                              icon: const Icon(
                                Icons.fullscreen_rounded,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: ElevatedButton.icon(
            onPressed: onTogglePlayPause,
            icon: Icon(
              controller.value.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
            label: Text(controller.value.isPlaying ? 'Pause' : 'Play'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size(140, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
