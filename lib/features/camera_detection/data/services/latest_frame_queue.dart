import 'dart:async';

typedef AsyncItemProcessor<T> = Future<void> Function(T item);

/// คิวสำหรับประมวลผลทีละ 1 item (ครั้งละหนึ่งงาน)
/// - ถ้ากำลังประมวลผลอยู่ และมี item ใหม่ส่งเข้ามา คิวจะเก็บไว้เป็น "item ค้าง" (pending)
/// - ถ้ามี item ใหม่เพิ่มขึ้นอีกระหว่างค้าง จะถือว่า "ตกงาน" (drop) และเก็บไว้แค่ตัวล่าสุด
/// - เหมาะกับกล้องเรียลไทม์: ใช้เฟรมที่ใหม่ที่สุดเสมอ ไม่ต้องประมวลผลเฟรมเก่าที่ล้าสมัย
class LatestFrameQueue<T> {
  LatestFrameQueue({required AsyncItemProcessor<T> processor}) {
    _processor = processor;
  }

  late final AsyncItemProcessor<T> _processor;

  T? _pendingItem;
  Future<void>? _running;
  int _droppedCount = 0;
  bool _isDisposed = false;

  int get droppedCount => _droppedCount;
  Future<void>? get running => _running;

  /// ส่ง item เข้าคิว — ถ้ามี item ค้างอยู่แล้ว ตัวเก่าจะถูกทิ้งและนับเป็น drop
  Future<void> submit(T item) {
    if (_isDisposed) return Future.value();

    if (_running != null && _pendingItem != null) {
      _droppedCount += 1;
    }
    _pendingItem = item;

    final running = _running;
    if (running != null) return running;

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
        if (item == null) break;
        // หยิบงานออกก่อนเริ่มประมวลผล เพื่อให้ submit ระหว่างนั้นเก็บงานใหม่ได้
        _pendingItem = null;
        await _processor(item);
      }
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    } finally {
      // เคลียร์เพื่อให้ submit รอบถัดไปเริ่ม drain ใหม่ได้
      _running = null;
    }
  }

  void dispose() {
    _isDisposed = true;
    _pendingItem = null;
  }
}
