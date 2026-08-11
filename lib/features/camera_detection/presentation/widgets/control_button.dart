// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'package:flutter/material.dart';

/// ปุ่มควบคุมรูปวงกลม (Circular control button)
/// - รองรับการแสดง 3 แบบ: ไอคอน / รูปภาพ asset / ข้อความ
class ControlButton extends StatelessWidget {
  const ControlButton({
    super.key,
    required this.content, // เนื้อหาของปุ่ม: IconData / String (path asset หรือข้อความ)
    required this.onPressed, // callback เมื่อกด
  });

  final dynamic content;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 24,
      backgroundColor: Colors.black.withValues(alpha: 0.2), // พื้นดำโปร่งแสง
      child: _buildContent(), // แสดงตามประเภทของ content
    );
  }

  /// เลือกวิดเจ็ตด้านในให้ตรงกับประเภทของ content
  Widget _buildContent() {
    if (content is IconData) {
      // 1. เป็น IconData -> ใช้ IconButton
      return IconButton(
        icon: Icon(content, color: Colors.white),
        onPressed: onPressed,
      );
    } else if (content.toString().contains('assets/')) {
      // 2. เป็น path asset -> ใช้ Image.asset
      return IconButton(
        icon: Image.asset(content, width: 24, height: 24, color: Colors.white),
        onPressed: onPressed,
      );
    } else {
      // 3. กรณีอื่น -> ถือว่าเป็นข้อความ
      return TextButton(
        onPressed: onPressed,
        child: Text(
          content,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      );
    }
  }
}
