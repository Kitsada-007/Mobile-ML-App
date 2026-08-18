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

    final firstCandidate = await _readBestCropOfTask(
      _createRealtimeFrameTaskData(
        frameBytes: frameBytes,
        selectedSign: selectedSign,
        expectedFrameWidth: expectedFrameWidth,
        expectedFrameHeight: expectedFrameHeight,
        rotationDegrees: rotationDegrees,
      ),
    );
    if (firstCandidate == null) return const SignNumberAnalysis();

    // ลองหมุนอีกทิศเฉพาะตอนที่ยังไม่ได้เลขและยังพอเดามุมหมุนใหม่ได้:
    // ถ้ารู้มุมจริงอยู่แล้ว (rotationDegrees) หรือไม่รู้ขนาดเฟรมที่คาดหวัง
    // worker จะคำนวณได้ crop ชุดเดิม ลองไปก็เสีย inference เปล่า
    final bool shouldRetryRotated =
        firstCandidate.reading.number == null &&
        rotationDegrees == null &&
        expectedFrameWidth != null &&
        expectedFrameHeight != null;
    if (!shouldRetryRotated) {
      return _toAnalysis(firstCandidate, selectedSign);
    }

    final rotatedCandidate = await _readBestCropOfTask(
      _createRealtimeFrameTaskData(
        frameBytes: frameBytes,
        selectedSign: selectedSign,
        expectedFrameWidth: expectedFrameWidth,
        expectedFrameHeight: expectedFrameHeight,
        runAlternative: true,
      ),
    );
    if (rotatedCandidate == null) return const SignNumberAnalysis();

    return _toAnalysis(rotatedCandidate, selectedSign);
  }

  /// สั่ง worker crop 1 รอบ (ได้ทั้ง tight/wide จากการ decode ครั้งเดียว)
  /// แล้วอ่านเลขจาก crop ที่ได้
  ///
  /// คืน null เมื่อ crop ไม่สำเร็จ เพื่อให้ผู้เรียกแยกออกจากกรณี crop สำเร็จ
  /// แต่อ่านเลขไม่ได้ ซึ่งยังต้องคืน cropBytes ออกไปให้ UI ใช้ดูปัญหา
  Future<_DigitCandidate?> _readBestCropOfTask(
    RealtimeFrameTaskData taskData,
  ) async {
    final taskResult = await _realtimeCropProcessor.process(taskData);
    if (taskResult.tightCropBytes == null) return null;

    final tightReading = await _numberDetectionService.detect(
      taskResult.tightCropBytes!,
    );
    final tightCandidate = _DigitCandidate(
      cropBytes: taskResult.tightCropBytes,
      reading: tightReading,
    );
    // ครบ 2 หลักแล้วไม่ต้องอ่าน wide ต่อ — ประหยัด inference 1 ครั้งต่อเฟรม
    if (tightReading.digitCount >= 2) return tightCandidate;
    if (taskResult.wideCropBytes == null) return tightCandidate;

    final wideReading = await _numberDetectionService.detect(
      taskResult.wideCropBytes!,
    );
    final wideCandidate = _DigitCandidate(
      cropBytes: taskResult.wideCropBytes,
      reading: wideReading,
    );
    return _preferDigitCandidate(tightCandidate, wideCandidate);
  }

  Future<void> dispose() => _realtimeCropProcessor.dispose();

  /// วิเคราะห์ภาพเดี่ยว (เช่นภาพถ่าย): ค้นหาป้าย -> crop 2 แบบ -> เลือกผลที่ดีที่สุด
  /// - ใช้ compute() รัน crop บน background isolate
  Future<SignNumberAnalysis> analyzeSingleImage({
    required Uint8List frameBytes,
    required List<YOLOResult> detectionResults,
  }) async {
    final sign = _selectBestNumberSign(detectionResults);
    if (sign == null) {
      _debugPipeline('ไม่พบคลาส sign_number');
      return const SignNumberAnalysis();
    }

    final rect = _resolveCropRect(sign);

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
      return _toAnalysis(tightCandidate, sign);
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

    return _toAnalysis(selectedCandidate, sign);
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

/// เลือกกล่องพิกัดที่จะใช้ crop: ใช้ normalizedBox เมื่อค่าอยู่ในช่วงที่สมเหตุสมผล
/// (เผื่อถึง 1.01 เพราะกล่องที่ชนขอบภาพพอดีอาจเกิน 1.0 นิดหน่อยจาก floating-point)
/// ไม่งั้นถอยไปใช้ boundingBox ซึ่งเป็นพิกัดพิกเซล
Rect _resolveCropRect(YOLOResult sign) {
  final normalizedRect = sign.normalizedBox;
  final normalizedIsValid =
      normalizedRect.left >= 0 &&
      normalizedRect.top >= 0 &&
      normalizedRect.right > normalizedRect.left &&
      normalizedRect.bottom > normalizedRect.top &&
      normalizedRect.right <= 1.01 &&
      normalizedRect.bottom <= 1.01;
  if (normalizedIsValid) return normalizedRect;
  return sign.boundingBox;
}

/// เลือก crop ที่ดีกว่าระหว่างแน่น (tight) กับกว้าง (wide):
/// หลักมากกว่า -> ใช้; หลักเท่ากัน -> ใช้ค่าที่ confidence เฉลี่ยสูงกว่า
/// เสมอกันทั้งสองอย่างให้ tight ชนะ เพราะ crop แน่นมีสิ่งรบกวนรอบเลขน้อยกว่า
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

/// แปลงผลที่เลือกได้ให้เป็นรูปแบบที่ส่งออกนอก service
SignNumberAnalysis _toAnalysis(
  _DigitCandidate candidate,
  YOLOResult selectedSign,
) {
  return SignNumberAnalysis(
    cropBytes: candidate.cropBytes,
    number: candidate.reading.number,
    selectedSign: selectedSign,
  );
}

RealtimeFrameTaskData _createRealtimeFrameTaskData({
  required Uint8List frameBytes,
  required YOLOResult selectedSign,
  int? expectedFrameWidth,
  int? expectedFrameHeight,
  int? rotationDegrees,
  bool runAlternative = false,
}) {
  final rect = _resolveCropRect(selectedSign);

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
