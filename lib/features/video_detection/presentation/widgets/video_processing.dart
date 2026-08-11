import 'package:flutter/material.dart';

/// การ์ดแสดงสถานะการประมวลผลวิดีโอ (Progress Card)
/// ใช้แสดงความคืบหน้า + ข้อความสถานะระหว่างวิเคราะห์วิดีโอ
class ProcessingCard extends StatelessWidget {
  final double progressValue; // ค่าความคืบหน้า 0.0 - 1.0
  final String progressText; // ข้อความอธิบายขั้นตอน

  const ProcessingCard({
    super.key,
    required this.progressValue,
    required this.progressText,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme; // ธีมสีของแอป
    return Card(
      elevation: 0, // ไม่มีเงา
      color: colorScheme.surface, // พื้นหลังตามธีม
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ), // มุมโค้ง
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // แถวบน: ไอคอนหมุน + ข้อความสถานะ
            Row(
              children: [
                // ไอคอนหมุนขนาดเล็ก
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                // ข้อความสถานะ (ตัดข้อความถ้ายาวเกิน)
                Expanded(
                  child: Text(
                    progressText,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // แถบ progress (value = null นั้น indeterminate mode)
            ClipRRect(
              borderRadius: BorderRadius.circular(999), // ทำเป็นแท่งกลมมน
              child: LinearProgressIndicator(
                value: progressValue > 0 ? progressValue : null,
                minHeight: 10,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            // แสดง % ความคืบหน้าทางขวาหรือข้อความ "กำลังประมวลผล..."
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                progressValue > 0
                    ? "${(progressValue * 100).toStringAsFixed(1)}%"
                    : "กำลังประมวลผล...",
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
