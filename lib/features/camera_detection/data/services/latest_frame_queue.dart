import 'dart:async';

typedef AsyncItemProcessor<T> = Future<void> Function(T item);

/// Runs one item at a time and retains only the newest item while busy.
class LatestFrameQueue<T> {
  LatestFrameQueue({required AsyncItemProcessor<T> processor})
    : _processor = processor;

  final AsyncItemProcessor<T> _processor;

  T? _pendingItem;
  Future<void>? _running;
  int _droppedCount = 0;
  bool _isDisposed = false;

  int get droppedCount => _droppedCount;
  Future<void>? get running => _running;

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

  Future<void> _drain(Completer<void> completer) async {
    try {
      while (!_isDisposed) {
        final item = _pendingItem;
        if (item == null) break;
        _pendingItem = null;
        await _processor(item);
      }
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    } finally {
      _running = null;
    }
  }

  void dispose() {
    _isDisposed = true;
    _pendingItem = null;
  }
}
