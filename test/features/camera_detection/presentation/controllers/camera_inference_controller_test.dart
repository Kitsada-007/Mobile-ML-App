import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/controllers/camera_inference_controller.dart';
import 'package:trffic_ilght_app/core/services/inference/sign_number_pipeline_service.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

class RecordingDigitYolo extends YOLO {
  RecordingDigitYolo()
    : super(modelPath: 'unused.tflite', task: YOLOTask.detect);

  int predictCallCount = 0;
  Uint8List? receivedImageBytes;

  @override
  Future<Map<String, dynamic>> predict(
    Uint8List imageBytes, {
    double? confidenceThreshold,
    double? iouThreshold,
  }) async {
    predictCallCount += 1;
    receivedImageBytes = imageBytes;
    return {
      'detections': [
        _digitDetection('1', left: 0.2),
        _digitDetection('2', left: 0.6),
      ],
    };
  }
}

class BlockingDigitYolo extends RecordingDigitYolo {
  final firstPredictionStarted = Completer<void>();
  final releaseFirstPrediction = Completer<void>();

  @override
  Future<Map<String, dynamic>> predict(
    Uint8List imageBytes, {
    double? confidenceThreshold,
    double? iouThreshold,
  }) async {
    if (predictCallCount == 0) {
      firstPredictionStarted.complete();
      await releaseFirstPrediction.future;
    }
    return super.predict(
      imageBytes,
      confidenceThreshold: confidenceThreshold,
      iouThreshold: iouThreshold,
    );
  }
}

Map<String, dynamic> _digitDetection(String digit, {required double left}) {
  return {
    'classIndex': int.parse(digit),
    'className': digit,
    'confidence': 0.9,
    'boundingBox': {
      'left': left * 100,
      'top': 10.0,
      'right': (left + 0.2) * 100,
      'bottom': 40.0,
    },
    'normalizedBox': {
      'left': left,
      'top': 0.1,
      'right': left + 0.2,
      'bottom': 0.4,
    },
  };
}

Map<String, dynamic> _signDetection() {
  return {
    'classIndex': 0,
    'className': 'sign_number',
    'confidence': 0.9,
    'boundingBox': {'left': 25.0, 'top': 40.0, 'right': 75.0, 'bottom': 160.0},
    'normalizedBox': {'left': 0.25, 'top': 0.20, 'right': 0.75, 'bottom': 0.80},
  };
}

YOLOResult _trafficLightDetection(
  String className, {
  double confidence = 0.9,
  double left = 0.4,
  double right = 0.6,
}) {
  return YOLOResult.fromMap({
    'classIndex': switch (className) {
      'red_light_circle' => 1,
      'yellow_light' => 2,
      'green_light_circle' => 3,
      _ => 0,
    },
    'className': className,
    'confidence': confidence,
    'boundingBox': {
      'left': left * 100,
      'top': 10.0,
      'right': right * 100,
      'bottom': 30.0,
    },
    'normalizedBox': {'left': left, 'top': 0.1, 'right': right, 'bottom': 0.3},
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({'isVoiceEnabled': false});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        (call) async => 1,
      );

  test('accepts the first valid countdown reading immediately', () {
    expect(acceptCountdownReading('12'), '12');
  });

  test('ignores an empty countdown reading', () {
    expect(acceptCountdownReading(''), isNull);
    expect(acceptCountdownReading(null), isNull);
  });

  test('native threshold keeps sign detections down to 0.25', () {
    expect(nativeRealtimeConfidenceThreshold(0.50), 0.25);
    expect(nativeRealtimeConfidenceThreshold(0.10), 0.10);
  });

  test('downstream threshold preserves the setting for non-sign classes', () {
    expect(realtimeDetectionConfidenceThreshold('sign_number', 0.80), 0.25);
    expect(
      realtimeDetectionConfidenceThreshold('red_light_circle', 0.80),
      0.80,
    );
  });

  test('real-time stream skips the Number model when no sign exists', () async {
    final digitYolo = RecordingDigitYolo();
    final controller = CameraInferenceController(
      signNumberPipelineService: SignNumberPipelineService(
        digitYolo: digitYolo,
      ),
      numberDetectionInterval: Duration.zero,
    );
    final frame = img.Image(width: 200, height: 100);

    await controller.onStreamingData({
      'detections': <Map<String, dynamic>>[],
      'originalImage': Uint8List.fromList(img.encodeJpg(frame)),
      'imageWidth': 100,
      'imageHeight': 200,
    });

    expect(digitYolo.predictCallCount, 0);
    controller.dispose();
  });

  test(
    'real-time stream crops the same sign frame before Number inference',
    () async {
      final digitYolo = RecordingDigitYolo();
      final controller = CameraInferenceController(
        signNumberPipelineService: SignNumberPipelineService(
          digitYolo: digitYolo,
        ),
        numberDetectionInterval: Duration.zero,
      );
      final frame = img.Image(width: 200, height: 100);
      img.fill(frame, color: img.ColorRgb8(220, 30, 20));
      final frameBytes = Uint8List.fromList(img.encodeJpg(frame));

      await controller.onStreamingData({
        'frameNumber': 1,
        'detections': [_signDetection()],
        'originalImage': frameBytes,
        'imageWidth': 200,
        'imageHeight': 100,
      });

      expect(digitYolo.predictCallCount, 1);
      expect(digitYolo.receivedImageBytes, isNot(same(frameBytes)));
      expect(controller.detectedNumber, isNull);

      await controller.onStreamingData({
        'frameNumber': 2,
        'detections': [_signDetection()],
        'originalImage': frameBytes,
        'imageWidth': 200,
        'imageHeight': 100,
      });

      expect(digitYolo.predictCallCount, 2);
      expect(controller.detectedNumber, '12');
      controller.dispose();
    },
  );

  test(
    'real-time queue processes one frame and keeps only the latest',
    () async {
      final digitYolo = BlockingDigitYolo();
      final controller = CameraInferenceController(
        signNumberPipelineService: SignNumberPipelineService(
          digitYolo: digitYolo,
        ),
        numberDetectionInterval: Duration.zero,
      );
      final frame = img.Image(width: 200, height: 100);
      final frameBytes = Uint8List.fromList(img.encodeJpg(frame));

      Map<String, dynamic> packet(int frameNumber) => {
        'frameNumber': frameNumber,
        'detections': [_signDetection()],
        'originalImage': frameBytes,
        'imageWidth': 200,
        'imageHeight': 100,
      };

      final drain = controller.onStreamingData(packet(1));
      await digitYolo.firstPredictionStarted.future;
      unawaited(controller.onStreamingData(packet(2)));
      unawaited(controller.onStreamingData(packet(3)));
      digitYolo.releaseFirstPrediction.complete();
      await drain;

      expect(digitYolo.predictCallCount, 2);
      expect(controller.realtimeDiagnostics.map((event) => event.frameNumber), [
        1,
        3,
      ]);
      expect(controller.droppedStreamFrameCount, 1);
      controller.dispose();
    },
  );

  test(
    'disposing during Number inference does not apply a stale result',
    () async {
      final digitYolo = BlockingDigitYolo();
      final controller = CameraInferenceController(
        signNumberPipelineService: SignNumberPipelineService(
          digitYolo: digitYolo,
        ),
        numberDetectionInterval: Duration.zero,
      );
      final frame = img.Image(width: 200, height: 100);
      final frameBytes = Uint8List.fromList(img.encodeJpg(frame));

      final drain = controller.onStreamingData({
        'frameNumber': 1,
        'detections': [_signDetection()],
        'originalImage': frameBytes,
        'imageWidth': 200,
        'imageHeight': 100,
      });
      await digitYolo.firstPredictionStarted.future;

      controller.dispose();
      digitYolo.releaseFirstPrediction.complete();
      await drain;

      expect(controller.detectedNumber, isNull);
    },
  );

  test('real-time diagnostics retain only the latest twenty events', () async {
    final digitYolo = RecordingDigitYolo();
    final controller = CameraInferenceController(
      signNumberPipelineService: SignNumberPipelineService(
        digitYolo: digitYolo,
      ),
      numberDetectionInterval: Duration.zero,
    );

    for (var frameNumber = 1; frameNumber <= 25; frameNumber++) {
      await controller.onStreamingData({
        'frameNumber': frameNumber,
        'detections': [_signDetection()],
      });
    }

    expect(controller.realtimeDiagnostics, hasLength(20));
    expect(controller.realtimeDiagnostics.first.frameNumber, 6);
    expect(controller.realtimeDiagnostics.last.frameNumber, 25);
    controller.dispose();
  });

  test('traffic light state is exposed only after confirmation', () async {
    final controller = CameraInferenceController();
    final redLight = _trafficLightDetection('red_light_circle');

    await controller.onDetectionResults([redLight]);
    expect(controller.confirmedTrafficLightClassName, isNull);

    await controller.onDetectionResults([redLight]);
    expect(controller.confirmedTrafficLightClassName, 'red_light_circle');
    controller.dispose();
  });

  test('traffic light tracking selects the centered relevant light', () async {
    final controller = CameraInferenceController();
    final detections = [
      _trafficLightDetection(
        'green_light_circle',
        confidence: 0.99,
        left: 0.78,
        right: 0.94,
      ),
      _trafficLightDetection('red_light_circle', confidence: 0.86),
    ];

    await controller.onDetectionResults(detections);
    await controller.onDetectionResults(detections);

    expect(controller.confirmedTrafficLightClassName, 'red_light_circle');
    controller.dispose();
  });
}
