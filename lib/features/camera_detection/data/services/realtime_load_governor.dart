/// ปรับความถี่ของงานหนัก (อ่านเลข) ตามสภาพเครื่อง ณ ขณะนั้น
///
/// ปัญหาที่แก้: เมื่อเครื่องช้าลง (ร้อนจนลดคล็อก/มีแอปอื่นแย่ง) ผลที่ประมวลผลเสร็จ
/// จะเก่าเกิน maximumFrameAge แล้วถูกทิ้ง กลายเป็นวงจร "ทำงานหนัก → ช้า → ทิ้งผล"
/// ที่เผาแบตโดยไม่ได้อะไรกลับมาเลย
///
/// วิธีแก้คือถอยความถี่ลงเมื่อทำไม่ทันติดกันหลายเฟรม แล้วค่อย ๆ กลับมาเร็วเท่าเดิม
/// เมื่อเครื่องไหวแล้ว (ไม่แตะ maximumFrameAge ซึ่งเป็นเกณฑ์ความปลอดภัย)
final class RealtimeLoadGovernor {
  RealtimeLoadGovernor({
    Duration baseInterval = const Duration(milliseconds: 400),
    Duration maximumInterval = const Duration(milliseconds: 1600),
    int backoffAfterOverruns = 2,
    int recoverAfterHealthyFrames = 20,
  }) {
    _baseInterval = baseInterval;
    _maximumInterval = maximumInterval;
    _backoffAfterOverruns = backoffAfterOverruns;
    _recoverAfterHealthyFrames = recoverAfterHealthyFrames;
    _interval = baseInterval;
  }

  late final Duration _baseInterval;
  late final Duration _maximumInterval;
  late final int _backoffAfterOverruns;
  late final int _recoverAfterHealthyFrames;

  late Duration _interval;
  int _overrunStreak = 0;
  int _healthyStreak = 0;

  /// ความถี่ที่ควรใช้อยู่ตอนนี้
  Duration get interval => _interval;

  /// true เมื่อกำลังถอยความถี่ลงจากค่าปกติ (ใช้แสดงสถานะ/วินิจฉัย)
  bool get isThrottled => _interval > _baseInterval;

  /// บันทึกผลของหนึ่งเฟรม — [overBudget] คือเฟรมที่ประมวลผลเสร็จช้าจนผลถูกทิ้ง
  void recordFrame({required bool overBudget}) {
    if (overBudget) {
      _healthyStreak = 0;
      _overrunStreak = _overrunStreak + 1;
      if (_overrunStreak < _backoffAfterOverruns) return;

      _overrunStreak = 0;
      final slower = _interval * 2;
      if (slower > _maximumInterval) {
        _interval = _maximumInterval;
      } else {
        _interval = slower;
      }
      return;
    }

    _overrunStreak = 0;
    if (!isThrottled) return;

    _healthyStreak = _healthyStreak + 1;
    if (_healthyStreak < _recoverAfterHealthyFrames) return;

    _healthyStreak = 0;
    final faster = _interval ~/ 2;
    if (faster < _baseInterval) {
      _interval = _baseInterval;
    } else {
      _interval = faster;
    }
  }

  void reset() {
    _interval = _baseInterval;
    _overrunStreak = 0;
    _healthyStreak = 0;
  }
}
