import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/features/camera_detection/data/services/realtime_load_governor.dart';

void main() {
  test('เริ่มต้นที่ความถี่ปกติและไม่ถือว่าถูกถอย', () {
    final governor = RealtimeLoadGovernor();

    expect(governor.interval, const Duration(milliseconds: 400));
    expect(governor.isThrottled, isFalse);
  });

  test('ทำไม่ทันครั้งเดียวยังไม่ถอย (กันการถอยเพราะสะดุดชั่วคราว)', () {
    final governor = RealtimeLoadGovernor(backoffAfterOverruns: 2);

    governor.recordFrame(overBudget: true);

    expect(governor.interval, const Duration(milliseconds: 400));
  });

  test('ทำไม่ทันติดกันแล้วถอยความถี่ลงทีละเท่าตัว', () {
    final governor = RealtimeLoadGovernor(backoffAfterOverruns: 2);

    governor.recordFrame(overBudget: true);
    governor.recordFrame(overBudget: true);
    expect(governor.interval, const Duration(milliseconds: 800));
    expect(governor.isThrottled, isTrue);

    governor.recordFrame(overBudget: true);
    governor.recordFrame(overBudget: true);
    expect(governor.interval, const Duration(milliseconds: 1600));
  });

  test('ถอยได้ไม่เกินเพดานที่กำหนด', () {
    final governor = RealtimeLoadGovernor(
      backoffAfterOverruns: 1,
      maximumInterval: const Duration(milliseconds: 800),
    );

    for (var frame = 0; frame < 10; frame++) {
      governor.recordFrame(overBudget: true);
    }

    expect(governor.interval, const Duration(milliseconds: 800));
  });

  test('กลับมาเร็วเท่าเดิมเมื่อเครื่องไหวแล้ว', () {
    final governor = RealtimeLoadGovernor(
      backoffAfterOverruns: 1,
      recoverAfterHealthyFrames: 3,
    );
    governor.recordFrame(overBudget: true);
    expect(governor.interval, const Duration(milliseconds: 800));

    for (var frame = 0; frame < 3; frame++) {
      governor.recordFrame(overBudget: false);
    }
    expect(governor.interval, const Duration(milliseconds: 400));
    expect(governor.isThrottled, isFalse);
  });

  test('เฟรมที่ทันสลับกับไม่ทันต้องไม่รีบกลับไปเร็ว', () {
    final governor = RealtimeLoadGovernor(
      backoffAfterOverruns: 1,
      recoverAfterHealthyFrames: 3,
    );
    governor.recordFrame(overBudget: true);

    governor.recordFrame(overBudget: false);
    governor.recordFrame(overBudget: false);
    governor.recordFrame(overBudget: true); // ล้มอีกครั้ง -> ถอยเพิ่ม
    expect(governor.interval, const Duration(milliseconds: 1600));
  });

  test('reset คืนค่าเริ่มต้นทั้งหมด', () {
    final governor = RealtimeLoadGovernor(backoffAfterOverruns: 1);
    governor.recordFrame(overBudget: true);
    governor.reset();

    expect(governor.interval, const Duration(milliseconds: 400));
    expect(governor.isThrottled, isFalse);
  });
}
