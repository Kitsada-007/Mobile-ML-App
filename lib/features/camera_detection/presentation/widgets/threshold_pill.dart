// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'package:flutter/material.dart';

/// ป้ายรูปแคปซูล (pill) สำหรับแสดงค่า threshold
class ThresholdPill extends StatelessWidget {
  const ThresholdPill({super.key, required this.label});

  final String label; // ข้อความที่แสดง (เช่น "CONF 0.50")

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6), // พื้นดำโปร่งแสง
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
