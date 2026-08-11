// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/shared/models/model_types.dart'; // ประเภท SliderType

/// วิดเจ็ตแถบเลื่อน (Slider) สำหรับปรับค่า threshold ของโมเดล
/// - ปรากฏเฉพาะเมื่อ activeSlider != none (ปุ่มถูกเปิดไว้)
/// - ปรับได้ 3 แบบ: numItems / confidence / iou (ตามที่เลือก)
class ThresholdSlider extends StatelessWidget {
  const ThresholdSlider({
    super.key,
    required this.activeSlider, // สไลเดอร์ตัวที่กำลังแสดงอยู่
    required this.confidenceThreshold, // ค่า confidence ปัจจุบัน
    required this.iouThreshold, // ค่า iou ปัจจุบัน
    required this.numItemsThreshold, // ค่า numItems ปัจจุบัน
    required this.onValueChanged, // callback เมื่อค่าถูกเปลี่ยน
    required this.isLandscape, // ปรับ padding ตามแนวนอน/แนวตั้ง
  });

  final SliderType activeSlider;
  final double confidenceThreshold;
  final double iouThreshold;
  final int numItemsThreshold;
  final ValueChanged<double> onValueChanged;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    // ไม่มี slider ถูกเปิด -> ไม่แสดงอะไรเลย
    if (activeSlider == SliderType.none) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isLandscape ? 16 : 24,
          vertical: isLandscape ? 8 : 12,
        ),
        color: Colors.black.withValues(alpha: 0.8), // พื้นดำโปร่งแสง
        child: SliderTheme(
          // ปรับธีมสีของ slider ให้เป็นฟ้า
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.blue,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
            thumbColor: Colors.blue,
            overlayColor: Colors.blue.withValues(alpha: 0.2),
          ),
          child: Slider(
            value: _getSliderValue(), // ค่าปัจจุบันตามประเภท
            min: _getSliderMin(),
            max: _getSliderMax(),
            divisions: _getSliderDivisions(),
            label: _getSliderLabel(),
            onChanged: onValueChanged,
          ),
        ),
      ),
    );
  }

  /// ค่าปัจจุบันของ slider (ตามประเภทที่เลือก)
  double _getSliderValue() => switch (activeSlider) {
    SliderType.numItems => numItemsThreshold.toDouble(),
    SliderType.confidence => confidenceThreshold,
    SliderType.iou => iouThreshold,
    _ => 0,
  };

  double _getSliderMin() => activeSlider == SliderType.numItems ? 5 : 0.1;
  double _getSliderMax() => activeSlider == SliderType.numItems ? 50 : 0.9;
  int _getSliderDivisions() => activeSlider == SliderType.numItems ? 9 : 8;
  String _getSliderLabel() => switch (activeSlider) {
    SliderType.numItems => '$numItemsThreshold',
    SliderType.confidence => confidenceThreshold.toStringAsFixed(1),
    SliderType.iou => iouThreshold.toStringAsFixed(1),
    _ => '',
  };
}
