import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:trffic_ilght_app/core/services/inference/number_detection_service.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

export 'package:trffic_ilght_app/core/services/inference/number_detection_service.dart'
    show digitConfidenceThreshold, digitIouThreshold;

// ---- ขนาด/ปัจจัยการ crop ป้ายตัวเลขนับถอยหลัง ----
const int minimumDigitCropEdge =
    128; // ขอบสั้นขั้นต่ำของภาพที่ส่งเข้า digit model
const int maximumDigitCropEdge =
    640; // ขอบยาวสูงสุดของภาพที่ส่งเข้า digit model
const double tightHorizontalPaddingFactor =
    0.15; // padding แนวนอนแบบแน่น (crop ตามกล่อง)
const double tightVerticalPaddingFactor = 0.10; // padding แนวตั้งแบบแน่น
const double wideHorizontalPaddingFactor =
    0.30; // padding แนวนอนแบบกว้าง (เผื่อตัวเลขล้นกล่อง)
const double wideVerticalPaddingFactor = 0.15; // padding แนวตั้งแบบกว้าง

/// พิมพ์ log ดีบักเฉพาะในโหมด debug
void _debugPipeline(String message) {
  if (kDebugMode) debugPrint(message);
}

/// ข้อมูลการ crop หนึ่งชุด: ภาพ + พิกัดกล่อง (normalized หรือ pixel) + ปัจจัย padding
class CropData {
  final Uint8List imageBytes;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double horizontalPaddingFactor;
  final double verticalPaddingFactor;

  CropData(
    this.imageBytes,
    this.left,
    this.top,
    this.right,
    this.bottom, {
    this.horizontalPaddingFactor = tightHorizontalPaddingFactor,
    this.verticalPaddingFactor = tightVerticalPaddingFactor,
  });
}

/// พิกัด crop ที่เป็นจำนวนเต็ม (pixel) ภายในภาพ
typedef CropBounds = ({int left, int top, int right, int bottom});

/// YOLOView 0.6.10 reports boxes in the upright frame coordinate space but
/// streams the camera bitmap before CameraX rotation. Normalize the bitmap
/// before applying those boxes.
/// (YOLOView 0.6.10 รายงานพิกัดกล่องในระบบพิกัดเฟรมที่ตั้งตรง แต่สตรีม bitmap
/// ของกล้องก่อนหมุนตาม CameraX -> ต้องปรับภาพให้ตรงกับพิกัดก่อนใช้กล่อง)
@visibleForTesting
Uint8List orientFrameForDetectionCoordinates(
  Uint8List frameBytes, {
  int? expectedWidth,
  int? expectedHeight,
  int? rotationDegrees,
}) {
  final decoded = img.decodeImage(frameBytes);
  if (decoded == null) return frameBytes;

  img.Image oriented = img.bakeOrientation(decoded);
  final normalizedRotation = rotationDegrees == null
      ? null
      : ((rotationDegrees % 360) + 360) % 360;
  final dimensionsAreReversed =
      expectedWidth != null &&
      expectedHeight != null &&
      oriented.width == expectedHeight &&
      oriented.height == expectedWidth;

  final degrees = normalizedRotation ?? (dimensionsAreReversed ? 90 : 0);
  if (degrees == 0) return frameBytes;

  oriented = img.copyRotate(oriented, angle: degrees);
  return Uint8List.fromList(img.encodeJpg(oriented, quality: 95));
}

class SignNumberAnalysis {
  final Uint8List? cropBytes;
  final String? number;
  final YOLOResult? selectedSign;

  const SignNumberAnalysis({this.cropBytes, this.number, this.selectedSign});
}

/// แปลงพิกัดกล่อง (normalized หรือ pixel) ให้เป็น CropBounds เป็นพิกเซล
/// - ถ้าค่าเป็น normalized (0..1) จะคูณขนาดภาพก่อน
/// - ครอบค่าอยู่ในขอบภาพเสมอ
CropBounds resolveCropBounds(
  CropData data, {
  required int imageWidth,
  required int imageHeight,
}) {
  double x1 = data.left;
  double y1 = data.top;
  double x2 = data.right;
  double y2 = data.bottom;

  final bool isNormalized =
      x1 >= -0.01 && y1 >= -0.01 && x2 <= 1.01 && y2 <= 1.01;

  if (isNormalized) {
    x1 *= imageWidth;
    y1 *= imageHeight;
    x2 *= imageWidth;
    y2 *= imageHeight;
  }

  final int left = x1.floor().clamp(0, imageWidth - 1);
  final int top = y1.floor().clamp(0, imageHeight - 1);
  final int right = x2.ceil().clamp(left + 1, imageWidth);
  final int bottom = y2.ceil().clamp(top + 1, imageHeight);

  return (left: left, top: top, right: right, bottom: bottom);
}

/// ขยายกล่อง crop ออกไปตาม factor (เพื่อรวมตัวเลขที่ล้นขอบกล่องเล็กน้อย)
@visibleForTesting
CropBounds expandCropBounds(
  CropBounds bounds, {
  required int imageWidth,
  required int imageHeight,
  required double horizontalPaddingFactor,
  required double verticalPaddingFactor,
}) {
  final int cropWidth = bounds.right - bounds.left;
  final int cropHeight = bounds.bottom - bounds.top;
  final int paddingX = max(2, (cropWidth * horizontalPaddingFactor).round());
  final int paddingY = max(2, (cropHeight * verticalPaddingFactor).round());

  return (
    left: max(0, bounds.left - paddingX),
    top: max(0, bounds.top - paddingY),
    right: min(imageWidth, bounds.right + paddingX),
    bottom: min(imageHeight, bounds.bottom + paddingY),
  );
}

/// ประมวลผลภาพ crop ของป้ายตัวเลขเป็นภาพ grayscale ขนาดที่เหมาะกับ digit model
/// - crop ทีละขั้นตอนแล้ว จัดสเกลให้อยู่ในช่วง [minimumDigitCropEdge, maximumDigitCropEdge]
/// - เปลี่ยนเป็น grayscale (digit model ฝึกมาจากภาพ grayscale) แต่คง 3 ช่องสีไว้
/// - รันได้ทั้งใน isolate/background isolate (เหมาะกับ compute)
@visibleForTesting
Uint8List? processSignCrop(CropData data) {
  try {
    final decoded = img.decodeImage(data.imageBytes);
    if (decoded == null) return null;

    final original = img.bakeOrientation(decoded);

    final int imageWidth = original.width;
    final int imageHeight = original.height;

    final bounds = resolveCropBounds(
      data,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );

    final int cropWidth = bounds.right - bounds.left;
    final int cropHeight = bounds.bottom - bounds.top;

    if (cropWidth <= 0 || cropHeight <= 0) {
      _debugPipeline('Crop ไม่ถูกต้อง');
      return null;
    }

    final paddedBounds = expandCropBounds(
      bounds,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      horizontalPaddingFactor: data.horizontalPaddingFactor,
      verticalPaddingFactor: data.verticalPaddingFactor,
    );

    img.Image cropped = img.copyCrop(
      original,
      x: paddedBounds.left,
      y: paddedBounds.top,
      width: paddedBounds.right - paddedBounds.left,
      height: paddedBounds.bottom - paddedBounds.top,
    );

    final int shortestEdge = min(cropped.width, cropped.height);
    final int longestEdge = max(cropped.width, cropped.height);
    double scale = shortestEdge < minimumDigitCropEdge
        ? minimumDigitCropEdge / shortestEdge
        : 1;

    if (longestEdge * scale > maximumDigitCropEdge) {
      scale = maximumDigitCropEdge / longestEdge;
    }

    if ((scale - 1).abs() > 0.001) {
      cropped = img.copyResize(
        cropped,
        width: max(1, (cropped.width * scale).round()),
        height: max(1, (cropped.height * scale).round()),
        interpolation: img.Interpolation.linear,
      );
    }

    // Number model was trained with grayscale images. Keep three output
    // channels so the encoded image remains compatible with YOLO input.
    cropped = img.grayscale(cropped);

    _debugPipeline('Crop พร้อมตรวจเลข: ${cropped.width}x${cropped.height}');

    return Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
  } catch (e, stackTrace) {
    _debugPipeline('Isolate Crop Error: $e');
    _debugPipeline('$stackTrace');
    return null;
  }
}

class RealtimeFrameTaskData {
  final Uint8List frameBytes;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final int? expectedFrameWidth;
  final int? expectedFrameHeight;
  final int? rotationDegrees;
  final bool runAlternative;

  RealtimeFrameTaskData({
    required this.frameBytes,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.expectedFrameWidth,
    this.expectedFrameHeight,
    this.rotationDegrees,
    this.runAlternative = false,
  });
}

/// ผลลัพธ์การ crop เฟรม Realtime (ทั้งแบบแน่นและแบบกว้าง) — ส่งกลับมา 2 ชุด
class RealtimeFrameTaskResult {
  final Uint8List? tightCropBytes;
  final Uint8List? wideCropBytes;

  RealtimeFrameTaskResult({this.tightCropBytes, this.wideCropBytes});
}

/// ประมวลผล 1 เฟรมใน isolate: หมุนภาพ + crop 2 รูปแบบ (แน่น/กว้าง)
/// - คำนวณมุมหมุนจาก rotationDegrees หรือย้อนจากขนาดภาพที่คาดหวัง
/// - ครอบพิกัดให้อยู่ในภาพแล้วสร้าง crop ทั้งแบบ tight (padding น้อย) และ wide (padding มาก)
RealtimeFrameTaskResult _processRealtimeFrameTask(RealtimeFrameTaskData data) {
  final decoded = img.decodeImage(data.frameBytes);
  if (decoded == null) return RealtimeFrameTaskResult();

  img.Image original = img.bakeOrientation(decoded);

  int degrees = 0;
  if (data.rotationDegrees != null) {
    degrees = ((data.rotationDegrees! % 360) + 360) % 360;
  } else if (data.expectedFrameWidth != null &&
      data.expectedFrameHeight != null) {
    final dimensionsAreReversed =
        original.width == data.expectedFrameHeight &&
        original.height == data.expectedFrameWidth;
    if (data.runAlternative) {
      degrees = dimensionsAreReversed ? 270 : 180;
    } else {
      degrees = dimensionsAreReversed ? 90 : 0;
    }
  }

  if (degrees != 0) {
    original = img.copyRotate(original, angle: degrees);
  }

  final int imageWidth = original.width;
  final int imageHeight = original.height;

  double x1 = data.left;
  double y1 = data.top;
  double x2 = data.right;
  double y2 = data.bottom;

  final bool isNormalized =
      x1 >= -0.01 && y1 >= -0.01 && x2 <= 1.01 && y2 <= 1.01;

  if (isNormalized) {
    x1 *= imageWidth;
    y1 *= imageHeight;
    x2 *= imageWidth;
    y2 *= imageHeight;
  }

  final int left = x1.floor().clamp(0, imageWidth - 1);
  final int top = y1.floor().clamp(0, imageHeight - 1);
  final int right = x2.ceil().clamp(left + 1, imageWidth);
  final int bottom = y2.ceil().clamp(top + 1, imageHeight);

  final bounds = (left: left, top: top, right: right, bottom: bottom);
  final int cropWidth = bounds.right - bounds.left;
  final int cropHeight = bounds.bottom - bounds.top;

  if (cropWidth <= 0 || cropHeight <= 0) {
    return RealtimeFrameTaskResult();
  }

  Uint8List? cropAndEncode(double hPadding, double vPadding) {
    final padded = expandCropBounds(
      bounds,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      horizontalPaddingFactor: hPadding,
      verticalPaddingFactor: vPadding,
    );

    img.Image cropped = img.copyCrop(
      original,
      x: padded.left,
      y: padded.top,
      width: padded.right - padded.left,
      height: padded.bottom - padded.top,
    );

    // จัดสเกลให้พอดีกับช่วงที่ digit model รองรับ
    final int shortestEdge = min(cropped.width, cropped.height);
    final int longestEdge = max(cropped.width, cropped.height);
    double scale = shortestEdge < minimumDigitCropEdge
        ? minimumDigitCropEdge / shortestEdge
        : 1;

    if (longestEdge * scale > maximumDigitCropEdge) {
      scale = maximumDigitCropEdge / longestEdge;
    }

    if ((scale - 1).abs() > 0.001) {
      cropped = img.copyResize(
        cropped,
        width: max(1, (cropped.width * scale).round()),
        height: max(1, (cropped.height * scale).round()),
        interpolation: img.Interpolation.linear,
      );
    }

    // digit model ฝึกด้วยภาพ grayscale -> แปลงเป็น grayscale แล้วเข้ารหัส JPG
    cropped = img.grayscale(cropped);
    return Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
  }

  final tightBytes = cropAndEncode(
    tightHorizontalPaddingFactor,
    tightVerticalPaddingFactor,
  );
  final wideBytes = cropAndEncode(
    wideHorizontalPaddingFactor,
    wideVerticalPaddingFactor,
  );

  return RealtimeFrameTaskResult(
    tightCropBytes: tightBytes,
    wideCropBytes: wideBytes,
  );
}

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
      final result = _processRealtimeFrameTask(
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

TransferableTypedData? _transferBytes(Uint8List? bytes) =>
    bytes == null ? null : TransferableTypedData.fromList([bytes]);

Uint8List? _materializeBytes(dynamic data) =>
    data is TransferableTypedData ? data.materialize().asUint8List() : null;

/// ตัวประมวลผลสายงานทั้งหมด: ตรวจจับป้าย -> crop -> อ่านตัวเลข
/// - โหมด Realtime: ใช้ PersistentSignCropWorker (isolate เดียว reused)
/// - โหมดภาพเดี่ยว: crop บน background isolate ผ่าน compute()
/// - เลือกผลที่ดีที่สุดระหว่าง crop แบบแน่น (tight) กับแบบกว้าง (wide)
class SignNumberPipelineService {
  SignNumberPipelineService({
    NumberDetectionService? numberDetectionService,
    YOLO? digitYolo,
    RealtimeSignCropProcessor? realtimeCropProcessor,
  }) : _numberDetectionService = _resolveNumberDetectionService(
         numberDetectionService: numberDetectionService,
         digitYolo: digitYolo,
       ),
       _realtimeCropProcessor =
           realtimeCropProcessor ?? PersistentSignCropWorker();

  final NumberDetectionService _numberDetectionService;
  final RealtimeSignCropProcessor _realtimeCropProcessor;

  /// เลือก NumberDetectionService ที่จะใช้ (ส่งตรง หรือสร้างจาก digitYolo)
  static NumberDetectionService _resolveNumberDetectionService({
    NumberDetectionService? numberDetectionService,
    YOLO? digitYolo,
  }) {
    if (numberDetectionService != null) return numberDetectionService;
    if (digitYolo != null) {
      return NumberDetectionService(numberYolo: digitYolo);
    }
    throw ArgumentError('numberDetectionService or digitYolo must be provided');
  }

  Future<String?> detectNumberFromSign({
    required Uint8List frameBytes,
    required List<YOLOResult> detectionResults,
    int? expectedFrameWidth,
    int? expectedFrameHeight,
    int? rotationDegrees,
  }) async {
    final analysis = await analyzeRealtimeFrame(
      frameBytes: frameBytes,
      detectionResults: detectionResults,
      expectedFrameWidth: expectedFrameWidth,
      expectedFrameHeight: expectedFrameHeight,
      rotationDegrees: rotationDegrees,
    );
    return analysis.number;
  }

  /// วิเคราะห์เฟรม Realtime: เลือกป้ายตัวเลขที่ดีที่สุด -> crop -> อ่านเลข
  /// - ถ้า crop แบบแน่นอ่านได้ >= 2 หลัก -> ใช้เลย
  /// - ไม่งั้นลอง crop แบบกว้าง แล้วเลือกผลที่ได้เลข/ความมั่นใจดีกว่า
  /// - ถ้ายังไม่ได้ผลและไม่มีข้อมูลการหมุน -> ลอง crop แบบหมุนอีกทิศทาง (runAlternative)
  Future<SignNumberAnalysis> analyzeRealtimeFrame({
    required Uint8List frameBytes,
    required List<YOLOResult> detectionResults,
    int? expectedFrameWidth,
    int? expectedFrameHeight,
    int? rotationDegrees,
  }) async {
    final selectedSign = _selectBestNumberSign(detectionResults);
    if (selectedSign == null) return const SignNumberAnalysis();

    final taskData = _createRealtimeFrameTaskData(
      frameBytes: frameBytes,
      selectedSign: selectedSign,
      expectedFrameWidth: expectedFrameWidth,
      expectedFrameHeight: expectedFrameHeight,
      rotationDegrees: rotationDegrees,
    );
    final taskResult = await _realtimeCropProcessor.process(taskData);

    if (taskResult.tightCropBytes == null) {
      return const SignNumberAnalysis();
    }

    final tightReading = await _numberDetectionService.detect(
      taskResult.tightCropBytes!,
    );
    if (tightReading.digitCount >= 2) {
      return SignNumberAnalysis(
        cropBytes: taskResult.tightCropBytes,
        number: tightReading.number,
        selectedSign: selectedSign,
      );
    }

    final wideReading = taskResult.wideCropBytes != null
        ? await _numberDetectionService.detect(taskResult.wideCropBytes!)
        : const NumberDetectionResult();

    final preferred = wideReading.digitCount != tightReading.digitCount
        ? (wideReading.digitCount > tightReading.digitCount
              ? wideReading
              : tightReading)
        : (wideReading.averageConfidence > tightReading.averageConfidence
              ? wideReading
              : tightReading);

    final selectedBytes = preferred == wideReading
        ? taskResult.wideCropBytes
        : taskResult.tightCropBytes;

    if (preferred.number != null ||
        rotationDegrees != null ||
        expectedFrameWidth == null ||
        expectedFrameHeight == null) {
      return SignNumberAnalysis(
        cropBytes: selectedBytes,
        number: preferred.number,
        selectedSign: selectedSign,
      );
    }

    final altResult = await _realtimeCropProcessor.process(
      _createRealtimeFrameTaskData(
        frameBytes: frameBytes,
        selectedSign: selectedSign,
        expectedFrameWidth: expectedFrameWidth,
        expectedFrameHeight: expectedFrameHeight,
        runAlternative: true,
      ),
    );

    if (altResult.tightCropBytes == null) {
      return const SignNumberAnalysis();
    }

    final altTightReading = await _numberDetectionService.detect(
      altResult.tightCropBytes!,
    );
    if (altTightReading.digitCount >= 2) {
      return SignNumberAnalysis(
        cropBytes: altResult.tightCropBytes,
        number: altTightReading.number,
        selectedSign: selectedSign,
      );
    }

    final altWideReading = altResult.wideCropBytes != null
        ? await _numberDetectionService.detect(altResult.wideCropBytes!)
        : const NumberDetectionResult();

    final altPreferred = altWideReading.digitCount != altTightReading.digitCount
        ? (altWideReading.digitCount > altTightReading.digitCount
              ? altWideReading
              : altTightReading)
        : (altWideReading.averageConfidence > altTightReading.averageConfidence
              ? altWideReading
              : altTightReading);

    final altSelectedBytes = altPreferred == altWideReading
        ? altResult.wideCropBytes
        : altResult.tightCropBytes;

    return SignNumberAnalysis(
      cropBytes: altSelectedBytes,
      number: altPreferred.number,
      selectedSign: selectedSign,
    );
  }

  Future<void> dispose() => _realtimeCropProcessor.dispose();

  /// วิเคราะห์ภาพเดี่ยว (เช่นภาพถ่าย): ค้นหาป้าย -> crop 2 แบบ -> เลือกผลที่ดีที่สุด
  /// - ใช้ compute() รัน crop บน background isolate
  Future<SignNumberAnalysis> analyzeSingleImage({
    required Uint8List frameBytes,
    required List<YOLOResult> detectionResults,
  }) async {
    final signResults = detectionResults
        .where((result) => result.className == 'sign_number')
        .toList();

    if (signResults.isEmpty) {
      _debugPipeline('ไม่พบคลาส sign_number');
      return const SignNumberAnalysis();
    }

    signResults.sort((a, b) => b.confidence.compareTo(a.confidence));

    final sign = signResults.first;
    final normalizedRect = sign.normalizedBox;

    final bool normalizedIsValid =
        normalizedRect.left >= 0 &&
        normalizedRect.top >= 0 &&
        normalizedRect.right > normalizedRect.left &&
        normalizedRect.bottom > normalizedRect.top &&
        normalizedRect.right <= 1.01 &&
        normalizedRect.bottom <= 1.01;

    final rect = normalizedIsValid ? normalizedRect : sign.boundingBox;

    _debugPipeline('Normalized box: ${sign.normalizedBox}');
    _debugPipeline('Bounding box: ${sign.boundingBox}');
    _debugPipeline('Selected crop box: $rect');

    final tightCandidate = await _analyzeCrop(
      frameBytes: frameBytes,
      rect: rect,
      horizontalPaddingFactor: tightHorizontalPaddingFactor,
      verticalPaddingFactor: tightVerticalPaddingFactor,
    );

    if (tightCandidate.reading.digitCount >= 2) {
      return SignNumberAnalysis(
        cropBytes: tightCandidate.cropBytes,
        number: tightCandidate.reading.number,
        selectedSign: sign,
      );
    }

    final wideCandidate = await _analyzeCrop(
      frameBytes: frameBytes,
      rect: rect,
      horizontalPaddingFactor: wideHorizontalPaddingFactor,
      verticalPaddingFactor: wideVerticalPaddingFactor,
    );
    final selectedCandidate = _preferDigitCandidate(
      tightCandidate,
      wideCandidate,
    );

    return SignNumberAnalysis(
      cropBytes: selectedCandidate.cropBytes,
      number: selectedCandidate.reading.number,
      selectedSign: sign,
    );
  }

  /// ลองวิเคราะห์ 1 crop (เป็น background isolate ผ่าน compute) แล้วเก็บผล
  Future<_DigitCandidate> _analyzeCrop({
    required Uint8List frameBytes,
    required Rect rect,
    required double horizontalPaddingFactor,
    required double verticalPaddingFactor,
  }) async {
    final cropData = CropData(
      frameBytes,
      rect.left,
      rect.top,
      rect.right,
      rect.bottom,
      horizontalPaddingFactor: horizontalPaddingFactor,
      verticalPaddingFactor: verticalPaddingFactor,
    );
    final processedBytes = await compute(processSignCrop, cropData);

    if (processedBytes == null) {
      _debugPipeline('สร้างภาพ crop ไม่สำเร็จ');
      return const _DigitCandidate(reading: NumberDetectionResult());
    }

    final reading = await _numberDetectionService.detect(processedBytes);
    return _DigitCandidate(cropBytes: processedBytes, reading: reading);
  }

  /// เลือก crop ที่ดีกว่าระหว่างแน่น (tight) กับกว้าง (wide):
  /// หลักมากกว่า -> ใช้; หลักเท่ากัน -> ใช้ค่าที่ confidence เฉลี่ยสูงกว่า
  _DigitCandidate _preferDigitCandidate(
    _DigitCandidate tight,
    _DigitCandidate wide,
  ) {
    if (wide.reading.digitCount != tight.reading.digitCount) {
      return wide.reading.digitCount > tight.reading.digitCount ? wide : tight;
    }
    return wide.reading.averageConfidence > tight.reading.averageConfidence
        ? wide
        : tight;
  }
}

/// เลือกป้าย sign_number ที่มีความมั่นใจสูงสุดจากผลการตรวจจับ (หรือ null ถ้าไม่พบ)
YOLOResult? _selectBestNumberSign(List<YOLOResult> detectionResults) {
  final signResults =
      detectionResults
          .where((result) => result.className == 'sign_number')
          .toList()
        ..sort((a, b) => b.confidence.compareTo(a.confidence));
  return signResults.isEmpty ? null : signResults.first;
}

RealtimeFrameTaskData _createRealtimeFrameTaskData({
  required Uint8List frameBytes,
  required YOLOResult selectedSign,
  int? expectedFrameWidth,
  int? expectedFrameHeight,
  int? rotationDegrees,
  bool runAlternative = false,
}) {
  final normalizedRect = selectedSign.normalizedBox;
  final normalizedIsValid =
      normalizedRect.left >= 0 &&
      normalizedRect.top >= 0 &&
      normalizedRect.right > normalizedRect.left &&
      normalizedRect.bottom > normalizedRect.top &&
      normalizedRect.right <= 1.01 &&
      normalizedRect.bottom <= 1.01;
  final rect = normalizedIsValid ? normalizedRect : selectedSign.boundingBox;

  return RealtimeFrameTaskData(
    frameBytes: frameBytes,
    left: rect.left,
    top: rect.top,
    right: rect.right,
    bottom: rect.bottom,
    expectedFrameWidth: expectedFrameWidth,
    expectedFrameHeight: expectedFrameHeight,
    rotationDegrees: rotationDegrees,
    runAlternative: runAlternative,
  );
}

class _DigitCandidate {
  final Uint8List? cropBytes;
  final NumberDetectionResult reading;

  const _DigitCandidate({this.cropBytes, required this.reading});
}
