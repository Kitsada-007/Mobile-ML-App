import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:trffic_ilght_app/core/services/inference/sign_crop_task.dart';

/// อินเทอร์เฟซของตัวประมวลผล crop แบบ Realtime (แยกเพื่อสลับ implementation ได้)
abstract interface class RealtimeSignCropProcessor {
  Future<RealtimeFrameTaskResult> process(RealtimeFrameTaskData data);

  Future<void> dispose();
}

/// ใช้ isolate เดียว (reuse) และส่งข้อมูลเฟรมแบบ zero-copy (TransferableTypedData)
/// - ลดค่าใช้จ่ายการสร้าง isolate ใหม่ทุกเฟรม
/// - ติดตามงานค้าง (pending) และคืนผลตาม requestId
/// - เก็บ worker ไว้ใน memory ระหว่างเฟรม
class PersistentSignCropWorker implements RealtimeSignCropProcessor {
  ReceivePort? _responsePort;
  StreamSubscription<dynamic>? _responseSubscription;
  Isolate? _isolate;
  SendPort? _workerPort;
  Completer<SendPort>? _startupCompleter;
  final Map<int, Completer<RealtimeFrameTaskResult>> _pending = {};
  int _nextRequestId = 0;
  int _spawnCount = 0;
  bool _isDisposed = false;

  int get spawnCount => _spawnCount;

  @override
  Future<RealtimeFrameTaskResult> process(RealtimeFrameTaskData data) async {
    final workerPort = await _ensureStarted();
    final requestId = _nextRequestId++;
    final completer = Completer<RealtimeFrameTaskResult>();
    _pending[requestId] = completer;

    // ส่งเฟรมผ่าน TransferableTypedData เพื่อไม่ต้องคัดลอกหน่วยความจำ
    workerPort.send([
      requestId,
      TransferableTypedData.fromList([data.frameBytes]),
      data.left,
      data.top,
      data.right,
      data.bottom,
      data.expectedFrameWidth,
      data.expectedFrameHeight,
      data.rotationDegrees,
      data.runAlternative,
    ]);
    return completer.future;
  }

  Future<SendPort> _ensureStarted() async {
    if (_isDisposed) {
      throw StateError('PersistentSignCropWorker is disposed');
    }
    final workerPort = _workerPort;
    if (workerPort != null) return workerPort;

    final starting = _startupCompleter;
    if (starting != null) return starting.future;

    // สร้าง isolate ขึ้นครั้งเดียว (ถ้ายังไม่มี) แล้วรอรับ SendPort กลับมา
    final startupCompleter = Completer<SendPort>();
    _startupCompleter = startupCompleter;
    final responsePort = ReceivePort();
    _responsePort = responsePort;
    _responseSubscription = responsePort.listen(_handleWorkerMessage);
    _isolate = await Isolate.spawn(
      _signCropWorkerEntryPoint,
      responsePort.sendPort,
      debugName: 'realtime-sign-crop-worker',
    );
    _spawnCount += 1;
    return startupCompleter.future;
  }

  void _handleWorkerMessage(dynamic message) {
    if (message is SendPort) {
      _workerPort = message;
      final startupCompleter = _startupCompleter;
      if (startupCompleter != null && !startupCompleter.isCompleted) {
        startupCompleter.complete(message);
      }
      return;
    }

    if (message is! List || message.length < 4) return;
    final requestId = message[0] as int;
    final completer = _pending.remove(requestId);
    if (completer == null) return;

    // ถ้า worker ส่ง error กลับมา -> ทำคำขอให้ล้มเหลวตามนั้น
    final error = message[3] as String?;
    if (error != null) {
      completer.completeError(StateError(error));
      return;
    }

    completer.complete(
      RealtimeFrameTaskResult(
        tightCropBytes: _materializeBytes(message[1]),
        wideCropBytes: _materializeBytes(message[2]),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _workerPort?.send(null);
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerPort = null;
    // ทำให้คำขอค้างทั้งหมดล้มเหลว (เพราะ worker ถูกปิดแล้ว)
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Sign crop worker was disposed'));
      }
    }
    _pending.clear();
    await _responseSubscription?.cancel();
    _responsePort?.close();
    _responsePort = null;
  }
}

/// ฟังก์ชันเริ่มต้นของ isolate: รอรับข้อความคำขอแล้วประมวลผล crop ทีละเฟรม
/// - ข้อความแรกคือ SendPort สำหรับตอบกลับ (ตอบ SendPort ของตัวเองกลับไปก่อน)
/// - รับค่า null เพื่อบอกให้หยุดและปิด port
void _signCropWorkerEntryPoint(SendPort responsePort) async {
  final requestPort = ReceivePort();
  responsePort.send(requestPort.sendPort);

  await for (final dynamic message in requestPort) {
    if (message == null) break;
    if (message is! List || message.length < 10) continue;

    final requestId = message[0] as int;
    try {
      final frameBytes = (message[1] as TransferableTypedData)
          .materialize()
          .asUint8List();
      final result = processRealtimeFrameTask(
        RealtimeFrameTaskData(
          frameBytes: frameBytes,
          left: message[2] as double,
          top: message[3] as double,
          right: message[4] as double,
          bottom: message[5] as double,
          expectedFrameWidth: message[6] as int?,
          expectedFrameHeight: message[7] as int?,
          rotationDegrees: message[8] as int?,
          runAlternative: message[9] as bool,
        ),
      );
      // ส่งผลกลับ (crop เป็น TransferableTypedData เพื่อไม่ต้องคัดลอก)
      responsePort.send([
        requestId,
        _transferBytes(result.tightCropBytes),
        _transferBytes(result.wideCropBytes),
        null,
      ]);
    } catch (error, stackTrace) {
      responsePort.send([requestId, null, null, '$error\n$stackTrace']);
    }
  }
  requestPort.close();
}

TransferableTypedData? _transferBytes(Uint8List? bytes) {
  if (bytes == null) return null;
  return TransferableTypedData.fromList([bytes]);
}

Uint8List? _materializeBytes(dynamic data) {
  if (data is TransferableTypedData) return data.materialize().asUint8List();
  return null;
}
