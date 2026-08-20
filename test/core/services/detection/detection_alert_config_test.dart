import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/core/services/detection/detection_alert_config.dart';

void main() {
  const config = DetectionAlertConfig();

  test('คลาสทั่วไปใช้ threshold ที่ผู้ใช้เลือกตรง ๆ', () {
    expect(config.effectiveConfidenceThreshold('green_light_circle', 0.9), 0.9);
    expect(config.effectiveConfidenceThreshold('turn_left', 0.75), 0.75);
    expect(config.effectiveConfidenceThreshold('go_straight_arrow', 0.2), 0.2);
  });

  test('คลาสที่เกี่ยวกับความปลอดภัยถูกจำกัดไม่ให้เกินเพดาน', () {
    for (final className in DetectionAlertConfig.safetyCriticalClasses) {
      expect(
        config.effectiveConfidenceThreshold(className, 0.9),
        DetectionAlertConfig.safetyCriticalConfidenceCeiling,
        reason: '$className ต้องไม่ถูกปรับให้มองข้ามได้',
      );
    }
  });

  test('ผู้ใช้ยังปรับให้ไวขึ้นกว่าเพดานได้', () {
    expect(config.effectiveConfidenceThreshold('red_light_circle', 0.3), 0.3);
    expect(config.effectiveConfidenceThreshold('off_light', 0.15), 0.15);
  });

  test('ไฟแดง ไฟเหลือง ไฟเสีย และป้ายห้าม อยู่ในกลุ่มที่ถูกคุ้มครอง', () {
    expect(
      DetectionAlertConfig.safetyCriticalClasses,
      containsAll(<String>[
        'red_light_circle',
        'yellow_light',
        'off_light',
        'dont_turn_left',
        'dont_turn_right',
        'dont_go_straight_arrow',
      ]),
    );
    // ไฟเขียว/ลูกศรอนุญาต ไม่ใช่สัญญาณอันตราย จึงไม่ต้องถูกคุ้มครอง
    expect(
      DetectionAlertConfig.safetyCriticalClasses,
      isNot(contains('green_light_circle')),
    );
  });
}
