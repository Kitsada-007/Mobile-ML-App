import 'package:flutter/foundation.dart';
import 'package:trffic_ilght_app/services/yolo_result_adapter.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

const double digitConfidenceThreshold = 0.25;
const double digitIouThreshold = 0.45;

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

    _debugNumberDetection('Raw digit detections: ${prediction['detections']}');

    final detections = parseYoloDetections(prediction['detections']);
    _debugNumberDetection('Parsed digit count: ${detections.length}');

    for (final detection in detections) {
      _debugNumberDetection(
        'เลข=${detection.className}, '
        'confidence=${detection.confidence}, '
        'box=${detection.boundingBox}',
      );
    }

    final digitDetections =
        detections
            .where(
              (detection) =>
                  RegExp(r'^\d$').hasMatch(detection.className.trim()),
            )
            .toList()
          ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final selectedDigits = digitDetections.take(2).toList();
    final number = readDigitSequence(selectedDigits, maxDigits: 2);
    final averageConfidence = selectedDigits.isEmpty
        ? 0.0
        : selectedDigits
                  .map((detection) => detection.confidence)
                  .reduce((a, b) => a + b) /
              selectedDigits.length;

    _debugNumberDetection('เลขที่อ่านได้: $number');

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
