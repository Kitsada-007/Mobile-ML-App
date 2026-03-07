import 'package:flutter/material.dart';

class EmptyStateSection extends StatelessWidget {
  const EmptyStateSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: SizedBox(
        height: 260,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.video_call_rounded,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 14),
                Text(
                  "No video selected",
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Please choose a video and run inference.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
