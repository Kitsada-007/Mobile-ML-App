import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:trffic_ilght_app/core/services/inference/yolo_result_adapter.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

const double digitConfidenceThreshold = 0.25;
const double digitIouThreshold = 0.45;

/// IoU ที่ถือว่ากล่องเลขสองกล่อง "คือหลักเดียวกัน"
/// NMS ของโมเดลตัดกล่องซ้ำเฉพาะภายในคลาสเดียวกัน กล่องที่ทับกันแต่คนละคลาส
/// (เช่นหลักเดียวถูกทายเป็นทั้ง 1 และ 7) จึงรอดมาทั้งคู่ ถ้าไม่ตัดออกจะถูก
/// อ่านต่อกันเป็นเลขสองหลักที่ไม่มีอยู่จริง
const double digitOverlapIouThreshold = 0.5;

class NumberDetectionResult {
  const NumberDetectionResult({
    this.number,
    this.digitCount = 0,
    this.averageConfidence = 0,
  });

  final String? number;
  final int digitCount;
  final double averageConfidence;
}

/// Detects and orders digits from an already-preprocessed sign crop.
class NumberDetectionService {
  NumberDetectionService({required YOLO numberYolo}) : _numberYolo = numberYolo;

  final YOLO _numberYolo;

  Future<String?> detectNumber(Uint8List imageBytes) async {
    final result = await detect(imageBytes);
    return result.number;
  }

  Future<NumberDetectionResult> detect(Uint8List imageBytes) async {
    final prediction = await _numberYolo.predict(
      imageBytes,
      confidenceThreshold: digitConfidenceThreshold,
      iouThreshold: digitIouThreshold,
    );

    final detections = parseYoloDetections(prediction['detections']);

    final digitDetections =
        detections
            .where(
              (detection) =>
                  RegExp(r'^\d$').hasMatch(detection.className.trim()),
            )
            .toList()
          ..sort((a, b) => b.confidence.compareTo(a.confidence));
    // ตัดกล่องที่ทับกับหลักที่เลือกไปแล้วออกก่อน จึงค่อยหยิบ 2 หลักแรก
    final selectedDigits = _selectDistinctDigits(
      digitDetections,
      maximumDigits: 2,
    );
    final number = readDigitSequence(selectedDigits, maxDigits: 2);
    final averageConfidence = selectedDigits.isEmpty
        ? 0.0
        : selectedDigits
                  .map((detection) => detection.confidence)
                  .reduce((a, b) => a + b) /
              selectedDigits.length;

    if (number != null && number.isNotEmpty) {
      _debugNumberDetection(
        'เลขที่อ่านได้: $number (conf: ${averageConfidence.toStringAsFixed(2)})',
      );
    }

    return NumberDetectionResult(
      number: number,
      digitCount: selectedDigits.length,
      averageConfidence: averageConfidence,
    );
  }
}

void _debugNumberDetection(String message) {
  if (kDebugMode) debugPrint(message);
}

/// เลือกหลักที่ "ไม่ทับกัน" ตามลำดับความมั่นใจ (ต้องส่ง list ที่เรียง conf มาก->น้อย)
List<YOLOResult> _selectDistinctDigits(
  List<YOLOResult> sortedByConfidence, {
  required int maximumDigits,
}) {
  final selected = <YOLOResult>[];
  for (final detection in sortedByConfidence) {
    if (selected.length >= maximumDigits) break;
    final box = _detectionBox(detection);
    final overlapsSelected = selected.any(
      (kept) =>
          _intersectionOverUnion(_detectionBox(kept), box) >=
          digitOverlapIouThreshold,
    );
    if (overlapsSelected) continue;
    selected.add(detection);
  }
  return selected;
}

/// ใช้ normalizedBox ถ้าใช้ได้ ไม่งั้น fallback เป็น boundingBox
/// (ต้องเทียบบนระบบพิกัดเดียวกัน ไม่งั้นค่า IoU ไม่มีความหมาย)
Rect _detectionBox(YOLOResult detection) {
  final normalized = detection.normalizedBox;
  return normalized.width > 0 && normalized.height > 0
      ? normalized
      : detection.boundingBox;
}

double _intersectionOverUnion(Rect first, Rect second) {
  final intersection = first.intersect(second);
  if (intersection.width <= 0 || intersection.height <= 0) return 0;
  final intersectionArea = intersection.width * intersection.height;
  final unionArea =
      first.width * first.height +
      second.width * second.height -
      intersectionArea;
  return unionArea <= 0 ? 0 : intersectionArea / unionArea;
}
