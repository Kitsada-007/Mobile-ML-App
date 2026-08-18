import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/core/services/inference/number_detection_service.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

class RecordingNumberYolo extends YOLO {
  RecordingNumberYolo(this.detections)
    : super(modelPath: 'unused.tflite', task: YOLOTask.detect);

  final List<Map<String, dynamic>> detections;
  Uint8List? receivedImageBytes;
  double? receivedConfidenceThreshold;
  double? receivedIouThreshold;

  @override
  Future<Map<String, dynamic>> predict(
    Uint8List imageBytes, {
    double? confidenceThreshold,
    double? iouThreshold,
  }) async {
    receivedImageBytes = imageBytes;
    receivedConfidenceThreshold = confidenceThreshold;
    receivedIouThreshold = iouThreshold;
    return {'detections': detections};
  }
}

Map<String, dynamic> numberDetection(
  String className, {
  required double left,
  required double confidence,
}) {
  return {
    'classIndex': int.tryParse(className) ?? 10,
    'className': className,
    'confidence': confidence,
    'boundingBox': {
      'left': left * 100,
      'top': 10.0,
      'right': (left + 0.1) * 100,
      'bottom': 40.0,
    },
    'normalizedBox': {
      'left': left,
      'top': 0.1,
      'right': left + 0.1,
      'bottom': 0.4,
    },
  };
}

void main() {
  test(
    'detects the two strongest digits and orders them left to right',
    () async {
      final yolo = RecordingNumberYolo([
        numberDetection('9', left: 0.8, confidence: 0.99),
        numberDetection('2', left: 0.4, confidence: 0.50),
        numberDetection('1', left: 0.1, confidence: 0.95),
        numberDetection('noise', left: 0.2, confidence: 1),
      ]);
      final service = NumberDetectionService(numberYolo: yolo);
      final cropBytes = Uint8List.fromList([1, 2, 3]);

      final result = await service.detect(cropBytes);

      expect(result.number, '19');
      expect(result.digitCount, 2);
      expect(result.averageConfidence, closeTo(0.97, 0.001));
      expect(yolo.receivedImageBytes, same(cropBytes));
      expect(yolo.receivedConfidenceThreshold, 0.25);
      expect(yolo.receivedIouThreshold, 0.45);
    },
  );

  test(
    'drops an overlapping box instead of reading it as a second digit',
    () async {
      // NMS ตัดกล่องซ้ำเฉพาะภายในคลาสเดียวกัน หลักเดียวที่ถูกทายเป็นทั้ง 1 และ 7
      // จึงรอดมาทั้งคู่ ถ้าไม่ตัดออกจะกลายเป็นเลข "17" ที่ไม่มีอยู่จริง
      final yolo = RecordingNumberYolo([
        numberDetection('1', left: 0.30, confidence: 0.90),
        numberDetection('7', left: 0.32, confidence: 0.50),
      ]);
      final service = NumberDetectionService(numberYolo: yolo);

      final result = await service.detect(Uint8List(0));

      expect(result.number, '1');
      expect(result.digitCount, 1);
      expect(result.averageConfidence, closeTo(0.90, 0.001));
    },
  );

  test('keeps two digits that sit side by side', () async {
    final yolo = RecordingNumberYolo([
      numberDetection('1', left: 0.30, confidence: 0.90),
      numberDetection('5', left: 0.45, confidence: 0.80),
    ]);
    final service = NumberDetectionService(numberYolo: yolo);

    final result = await service.detect(Uint8List(0));

    expect(result.number, '15');
    expect(result.digitCount, 2);
  });

  test('returns an empty result when the model finds no digits', () async {
    final yolo = RecordingNumberYolo([
      numberDetection('noise', left: 0.2, confidence: 0.9),
    ]);
    final service = NumberDetectionService(numberYolo: yolo);

    final result = await service.detect(Uint8List(0));

    expect(result.number, isNull);
    expect(result.digitCount, 0);
    expect(result.averageConfidence, 0);
  });
}
