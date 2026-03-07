import 'dart:io';

import 'package:flutter/material.dart';

class InferenceActionBar extends StatelessWidget {
  final bool processing;
  final File? videoFile;
  final VoidCallback onPickVideo;
  final VoidCallback onRunInference;

  const InferenceActionBar({
    super.key,
    required this.processing,
    required this.videoFile,
    required this.onPickVideo,
    required this.onRunInference,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: processing ? null : onPickVideo,
            icon: const Icon(Icons.video_library_rounded),
            label: const Text('Pick Video'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: (processing || videoFile == null)
                ? null
                : onRunInference,
            icon: processing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: Text(processing ? 'Processing...' : 'Run'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
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
