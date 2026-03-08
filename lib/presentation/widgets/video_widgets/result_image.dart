import 'dart:typed_data';

import 'package:flutter/material.dart';

class ResultImageSection extends StatelessWidget {
  final Uint8List imageBytes;

  const ResultImageSection({super.key, required this.imageBytes});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Result Image",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.memory(imageBytes, fit: BoxFit.contain),
          ),
        ),
      ],
    );
  }
}
