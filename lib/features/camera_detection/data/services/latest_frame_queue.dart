import 'dart:async'; // ใช้ Completer และ Future

typedef AsyncItemProcessor<T> = Future<void> Function(T item);

/// คิวสำหรับประมวลผลทีละ 1 item (ครั้งละหนึ่งงาน)
/// - ถ้ากำลังประมวลผลอยู่ และมี item ใหม่ส่งเข้ามา คิวจะเก็บไว้เป็น "item ค้าง" (pending)
/// - ถ้ามี item ใหม่เพิ่มขึ้นอีกระหว่างค้าง จะถือว่า "ตกงาน" (drop) และเก็บไว้แค่ตัวล่าสุด
/// - เหมาะกับกล้องเรียลไทม์: ใช้เฟรมที่ใหม่ที่สุดเสมอ ไม่ต้องประมวลผลเฟรมเก่าที่ล้าสมัย
class LatestFrameQueue<T> {
  LatestFrameQueue({required AsyncItemProcessor<T> processor})
    : _processor = processor;

  final AsyncItemProcessor<T> _processor; // ฟังก์ชันประมวลผล 1 item

  T? _pendingItem; // item ที่รอประมวลผล (เก็บตัวล่าสุดเพียงตัวเดียว)
  Future<void>? _running; // งานที่กำลังรันอยู่
  int _droppedCount = 0; // นับจำนวน item ที่ถูกทิ้ง (drop)
  bool _isDisposed = false; // คิวถูกปิดแล้วหรือยัง

  int get droppedCount => _droppedCount;
  Future<void>? get running => _running;

  /// ส่ง item เข้าคิว
  /// - ถ้ากำลังมี item ค้างอยู่ แสดงว่ามี item ใหม่แทรก -> นับ drop เพิ่ม
  /// - ตั้ง _pendingItem เป็นตัวใหม่ (ตัวเก่าถูกแทนที่)
  /// - ถ้ายังไม่มีงานรัน -> เริ่ม drain (ประมวลผลทีละตัว)
  Future<void> submit(T item) {
    if (_isDisposed) return Future.value(); // หลัง dispose ไม่รับงานอีก

    if (_running != null && _pendingItem != null) {
      _droppedCount += 1; // มีงานค้างอยู่ -> item ใหม่ชนกัน
    }
    _pendingItem = item;

    final running = _running;
    if (running != null) return running; // ยังมีงานรัน -> ไม่เริ่มใหม่

    final completer = Completer<void>();
    _running = completer.future;
    unawaited(_drain(completer));
    return completer.future;
  }

  /// ระบายงาน: ประมวลผล item ค้างซ้ำไปเรื่อย ๆ จนกว่าไม่มีงานเหลือ
  Future<void> _drain(Completer<void> completer) async {
    try {
      while (!_isDisposed) {
        final item = _pendingItem;
        if (item == null) break; // งานหมดแล้ว -> หยุด
        _pendingItem = null; // หยิบงานไปก่อน (เพื่อรับงานใหม่ระหว่างประมวลผล)
        await _processor(item); // ประมวลผล
      }
      completer.complete(); // เสร็จสมบูรณ์
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace); // โยน error ต่อ
    } finally {
      _running = null; // เคลียร์งานที่รัน เพื่อให้รอบต่อไปเริ่ม drain ใหม่ได้
    }
  }

  void dispose() {
    _isDisposed = true;
    _pendingItem = null; // ทิ้งงานค้างทั้งหมด
  }
}
