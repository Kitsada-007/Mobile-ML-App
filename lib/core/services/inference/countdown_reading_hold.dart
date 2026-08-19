/// คงเลขนับถอยหลังที่อ่านได้ล่าสุดไว้ชั่วคราวเมื่อเฟรมถัดมาอ่านไม่ได้
///
/// จำเป็นกับโหมดเรียลไทม์เพราะสองเหตุผล:
/// - ป้าย LED กะพริบตามจังหวะ PWM และภาพเบลอจากการสั่น ทำให้อ่านพลาดเป็นช่วง ๆ
/// - การอ่านเลขถูกจำกัดไว้ที่ทุก ๆ 400ms เฟรมระหว่างนั้นจึงไม่มีค่าใหม่เลย
///
/// แต่ต้องมีวันหมดอายุเสมอ ไม่งั้นเลขจะค้างบนจอทั้งที่ป้ายหายไปนานแล้ว
/// ซึ่งอันตรายกว่าไม่แสดงอะไรเลย
final class CountdownReadingHold {
  CountdownReadingHold({
    Duration holdDuration = const Duration(milliseconds: 1500),
  }) {
    _holdDuration = holdDuration;
  }

  late final Duration _holdDuration;
  String? _reading;
  DateTime? _acceptedAt;

  Duration get holdDuration => _holdDuration;
  String? get reading => _reading;

  /// อัปเดตด้วยผลอ่านของรอบนี้ ([reading] เป็น null เมื่ออ่านไม่ได้/ยังไม่ถึงรอบ)
  /// คืนเลขที่ควรแสดงบนจอ ณ เวลานั้น
  String? update(String? reading, {required DateTime timestamp}) {
    if (reading != null) {
      _reading = reading;
      _acceptedAt = timestamp;
      return _reading;
    }

    final acceptedAt = _acceptedAt;
    if (acceptedAt == null) {
      return null;
    }
    if (timestamp.difference(acceptedAt) > _holdDuration) {
      reset();
      return null;
    }
    return _reading;
  }

  void reset() {
    _reading = null;
    _acceptedAt = null;
  }
}
