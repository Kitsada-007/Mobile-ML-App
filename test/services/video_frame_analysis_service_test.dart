import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:trffic_ilght_app/services/sign_number_pipeline_service.dart';
import 'package:trffic_ilght_app/services/video_frame_analysis_service.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

class RecordingTrafficYolo extends YOLO {
  RecordingTrafficYolo(this.detections, this.annotatedImage)
    : super(modelPath: 'traffic.tflite', task: YOLOTask.detect);

  final List<Map<String, dynamic>> detections;
  final Uint8List annotatedImage;
  double? receivedConfidenceThreshold;
  double? receivedIouThreshold;

  @override
  Future<Map<String, dynamic>> predict(
    Uint8List imageBytes, {
    double? confidenceThreshold,
    double? iouThreshold,
  }) async {
    receivedConfidenceThreshold = confidenceThreshold;
    receivedIouThreshold = iouThreshold;
    return {'detections': detections, 'annotatedImage': annotatedImage};
  }
}

class RecordingDigitYolo extends YOLO {
  RecordingDigitYolo(this.detections)
    : super(modelPath: 'number.tflite', task: YOLOTask.detect);

  final List<Map<String, dynamic>> detections;
  int predictCallCount = 0;

  @override
  Future<Map<String, dynamic>> predict(
    Uint8List imageBytes, {
    double? confidenceThreshold,
    double? iouThreshold,
  }) async {
    predictCallCount += 1;
    return {'detections': detections};
  }
}

Map<String, dynamic> detection(
  String className, {
  required int classIndex,
  required double left,
  double confidence = 0.9,
}) {
  return {
    'classIndex': classIndex,
    'className': className,
    'confidence': confidence,
    'boundingBox': {
      'left': left * 200,
      'top': 10.0,
      'right': (left + 0.2) * 200,
      'bottom': 90.0,
    },
    'normalizedBox': {
      'left': left,
      'top': 0.1,
      'right': left + 0.2,
      'bottom': 0.9,
    },
  };
}

void main() {
  test('video frame analysis detects a number inside sign_number', () async {
    final source = img.Image(width: 200, height: 100);
    final frameBytes = Uint8List.fromList(img.encodeJpg(source));
    final annotatedBytes = Uint8List.fromList([9, 8, 7]);
    final trafficYolo = RecordingTrafficYolo([
      detection('sign_number', classIndex: 7, left: 0.2),
    ], annotatedBytes);
    final digitYolo = RecordingDigitYolo([
      detection('1', classIndex: 1, left: 0.2),
      detection('2', classIndex: 2, left: 0.6),
    ]);
    final service = VideoFrameAnalysisService(
      trafficYolo: trafficYolo,
      signNumberPipeline: SignNumberPipelineService(digitYolo: digitYolo),
    );

    final result = await service.analyze(frameBytes);

    expect(result.detections.single.className, 'sign_number');
    expect(result.detectedNumber, '12');
    expect(result.outputImageBytes, same(annotatedBytes));
    expect(trafficYolo.receivedConfidenceThreshold, 0.25);
    expect(trafficYolo.receivedIouThreshold, 0.45);
    expect(digitYolo.predictCallCount, 1);
  });

  test('video frame analysis skips the number model without a sign', () async {
    final source = img.Image(width: 200, height: 100);
    final frameBytes = Uint8List.fromList(img.encodeJpg(source));
    final trafficYolo = RecordingTrafficYolo([
      detection('red_light_circle', classIndex: 4, left: 0.2),
    ], frameBytes);
    final digitYolo = RecordingDigitYolo(const []);
    final service = VideoFrameAnalysisService(
      trafficYolo: trafficYolo,
      signNumberPipeline: SignNumberPipelineService(digitYolo: digitYolo),
    );

    final result = await service.analyze(frameBytes);

    expect(result.detectedNumber, isNull);
    expect(digitYolo.predictCallCount, 0);
  });
}
