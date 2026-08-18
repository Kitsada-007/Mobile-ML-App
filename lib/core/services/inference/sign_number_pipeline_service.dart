import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:trffic_ilght_app/core/services/inference/number_detection_service.dart';
import 'package:trffic_ilght_app/core/services/inference/sign_crop_geometry.dart';
import 'package:trffic_ilght_app/core/services/inference/sign_crop_task.dart';
import 'package:trffic_ilght_app/core/services/inference/sign_crop_worker.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

export 'package:trffic_ilght_app/core/services/inference/number_detection_service.dart'
    show digitConfidenceThreshold, digitIouThreshold;
export 'package:trffic_ilght_app/core/services/inference/sign_crop_geometry.dart';
export 'package:trffic_ilght_app/core/services/inference/sign_crop_task.dart';
export 'package:trffic_ilght_app/core/services/inference/sign_crop_worker.dart';

void _debugPipeline(String message) {
  if (kDebugMode) debugPrint(message);
}

class SignNumberAnalysis {
  final Uint8List? cropBytes;
  final String? number;
  final YOLOResult? selectedSign;

  const SignNumberAnalysis({this.cropBytes, this.number, this.selectedSign});
}

/// ตัวประมวลผลสายงานทั้งหมด: ตรวจจับป้าย -> crop -> อ่านตัวเลข
/// - โหมด Realtime: ใช้ PersistentSignCropWorker (isolate เดียว reused)
/// - โหมดภาพเดี่ยว: crop บน background isolate ผ่าน compute()
/// - เลือกผลที่ดีที่สุดระหว่าง crop แบบแน่น (tight) กับแบบกว้าง (wide)
class SignNumberPipelineService {
  SignNumberPipelineService({
    NumberDetectionService? numberDetectionService,
    YOLO? digitYolo,
    RealtimeSignCropProcessor? realtimeCropProcessor,
  }) {
    // ต้อง resolve service ก่อน: ถ้าอาร์กิวเมนต์ไม่ครบจะโยน ArgumentError
    // ตั้งแต่ตรงนี้ โดยยังไม่ทันสร้าง isolate worker ทิ้งค้างไว้
    _numberDetectionService = _resolveNumberDetectionService(
      numberDetectionService: numberDetectionService,
      digitYolo: digitYolo,
    );
    if (realtimeCropProcessor == null) {
      _realtimeCropProcessor = PersistentSignCropWorker();
    } else {
      _realtimeCropProcessor = realtimeCropProcessor;
    }
  }

  late final NumberDetectionService _numberDetectionService;
  late final RealtimeSignCropProcessor _realtimeCropProcessor;

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

    final NumberDetectionResult wideReading;
    if (taskResult.wideCropBytes == null) {
      wideReading = const NumberDetectionResult();
    } else {
      wideReading = await _numberDetectionService.detect(
        taskResult.wideCropBytes!,
      );
    }

    final NumberDetectionResult preferred;
    if (wideReading.digitCount != tightReading.digitCount) {
      if (wideReading.digitCount > tightReading.digitCount) {
        preferred = wideReading;
      } else {
        preferred = tightReading;
      }
    } else {
      if (wideReading.averageConfidence > tightReading.averageConfidence) {
        preferred = wideReading;
      } else {
        preferred = tightReading;
      }
    }

    final Uint8List? selectedBytes;
    if (preferred == wideReading) {
      selectedBytes = taskResult.wideCropBytes;
    } else {
      selectedBytes = taskResult.tightCropBytes;
    }

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

    final NumberDetectionResult altWideReading;
    if (altResult.wideCropBytes == null) {
      altWideReading = const NumberDetectionResult();
    } else {
      altWideReading = await _numberDetectionService.detect(
        altResult.wideCropBytes!,
      );
    }

    final NumberDetectionResult altPreferred;
    if (altWideReading.digitCount != altTightReading.digitCount) {
      if (altWideReading.digitCount > altTightReading.digitCount) {
        altPreferred = altWideReading;
      } else {
        altPreferred = altTightReading;
      }
    } else {
      final altWideConfidence = altWideReading.averageConfidence;
      final altTightConfidence = altTightReading.averageConfidence;
      if (altWideConfidence > altTightConfidence) {
        altPreferred = altWideReading;
      } else {
        altPreferred = altTightReading;
      }
    }

    final Uint8List? altSelectedBytes;
    if (altPreferred == altWideReading) {
      altSelectedBytes = altResult.wideCropBytes;
    } else {
      altSelectedBytes = altResult.tightCropBytes;
    }

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

    final Rect rect;
    if (normalizedIsValid) {
      rect = normalizedRect;
    } else {
      rect = sign.boundingBox;
    }

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
    final tightDigitCount = tight.reading.digitCount;
    final wideDigitCount = wide.reading.digitCount;
    if (wideDigitCount != tightDigitCount) {
      if (wideDigitCount > tightDigitCount) return wide;
      return tight;
    }
    final tightConfidence = tight.reading.averageConfidence;
    final wideConfidence = wide.reading.averageConfidence;
    if (wideConfidence > tightConfidence) return wide;
    return tight;
  }
}

/// เลือกป้าย sign_number ที่มีความมั่นใจสูงสุดจากผลการตรวจจับ (หรือ null ถ้าไม่พบ)
YOLOResult? _selectBestNumberSign(List<YOLOResult> detectionResults) {
  final signResults = detectionResults
      .where((result) => result.className == 'sign_number')
      .toList();
  signResults.sort((a, b) => b.confidence.compareTo(a.confidence));
  if (signResults.isEmpty) return null;
  return signResults.first;
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
  final Rect rect;
  if (normalizedIsValid) {
    rect = normalizedRect;
  } else {
    rect = selectedSign.boundingBox;
  }

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
