import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:trffic_ilght_app/services/sign_number_pipeline_service.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

class RecordingYolo extends YOLO {
  RecordingYolo() : super(modelPath: 'unused.tflite', task: YOLOTask.detect);

  Uint8List? receivedImageBytes;
  int predictCallCount = 0;

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
        {
          'classIndex': 2,
          'className': '2',
          'confidence': 0.9,
          'boundingBox': {
            'left': 60.0,
            'top': 10.0,
            'right': 80.0,
            'bottom': 40.0,
          },
          'normalizedBox': {
            'left': 0.6,
            'top': 0.1,
            'right': 0.8,
            'bottom': 0.4,
          },
        },
        {
          'classIndex': 1,
          'className': '1',
          'confidence': 0.95,
          'boundingBox': {
            'left': 10.0,
            'top': 10.0,
            'right': 30.0,
            'bottom': 40.0,
          },
          'normalizedBox': {
            'left': 0.1,
            'top': 0.1,
            'right': 0.3,
            'bottom': 0.4,
          },
        },
      ],
    };
  }
}

class SequencedYolo extends YOLO {
  SequencedYolo(this.responses)
    : super(modelPath: 'unused.tflite', task: YOLOTask.detect);

  final List<List<Map<String, dynamic>>> responses;
  final List<Uint8List> receivedImages = [];

  @override
  Future<Map<String, dynamic>> predict(
    Uint8List imageBytes, {
    double? confidenceThreshold,
    double? iouThreshold,
  }) async {
    receivedImages.add(imageBytes);
    final index = receivedImages.length - 1;
    return {
      'detections': responses[index < responses.length ? index : index - 1],
    };
  }
}

Map<String, dynamic> digitDetection(
  String digit, {
  required double left,
  double confidence = 0.9,
}) {
  return {
    'classIndex': int.parse(digit),
    'className': digit,
    'confidence': confidence,
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

YOLOResult trafficDetection({
  String className = 'sign_number',
  double confidence = 0.9,
  double left = 0.4,
  double top = 0.2,
  double right = 0.6,
  double bottom = 0.8,
}) {
  return YOLOResult.fromMap({
    'classIndex': 0,
    'className': className,
    'confidence': confidence,
    'boundingBox': {
      'left': left * 200,
      'top': top * 100,
      'right': right * 200,
      'bottom': bottom * 100,
    },
    'normalizedBox': {
      'left': left,
      'top': top,
      'right': right,
      'bottom': bottom,
    },
  });
}

void main() {
  group('resolveCropBounds', () {
    test('maps normalized coordinates to exact pixel bounds', () {
      final bounds = resolveCropBounds(
        CropData(Uint8List(0), 0.25, 0.20, 0.75, 0.80),
        imageWidth: 200,
        imageHeight: 100,
      );

      expect(bounds.left, 50);
      expect(bounds.top, 20);
      expect(bounds.right, 150);
      expect(bounds.bottom, 80);
    });

    test('keeps pixel coordinates in the source image coordinate space', () {
      final bounds = resolveCropBounds(
        CropData(Uint8List(0), 50, 20, 150, 80),
        imageWidth: 200,
        imageHeight: 100,
      );

      expect(bounds.left, 50);
      expect(bounds.top, 20);
      expect(bounds.right, 150);
      expect(bounds.bottom, 80);
    });

    test('expands horizontal context so an adjacent digit is not clipped', () {
      final bounds = expandCropBounds(
        (left: 50, top: 20, right: 150, bottom: 80),
        imageWidth: 200,
        imageHeight: 100,
        horizontalPaddingFactor: 0.30,
        verticalPaddingFactor: 0.15,
      );

      expect(bounds.left, 20);
      expect(bounds.top, 11);
      expect(bounds.right, 180);
      expect(bounds.bottom, 89);
    });
  });

  test('preprocessing matches the grayscale number-model training images', () {
    final source = img.Image(width: 8, height: 8);
    img.fill(source, color: img.ColorRgb8(220, 30, 20));

    final processedBytes = processSignCrop(
      CropData(Uint8List.fromList(img.encodePng(source)), 0, 0, 8, 8),
    );

    expect(processedBytes, isNotNull);
    final processed = img.decodeImage(processedBytes!);
    expect(processed, isNotNull);

    final centerPixel = processed!.getPixel(
      processed.width ~/ 2,
      processed.height ~/ 2,
    );
    expect((centerPixel.r - centerPixel.g).abs(), lessThan(5));
    expect((centerPixel.g - centerPixel.b).abs(), lessThan(5));
  });

  test(
    'preprocessing upscales a small crop and preserves its aspect ratio',
    () {
      final source = img.Image(width: 20, height: 10);
      img.fill(source, color: img.ColorRgb8(220, 30, 20));

      final processedBytes = processSignCrop(
        CropData(Uint8List.fromList(img.encodePng(source)), 0, 0, 20, 10),
      );

      final processed = img.decodeImage(processedBytes!);
      expect(
        [processed!.width, processed.height].reduce((a, b) => a < b ? a : b),
        greaterThanOrEqualTo(128),
      );
      expect(processed.width / processed.height, closeTo(2, 0.05));
    },
  );

  test(
    'real-time frame is rotated into the detection coordinate orientation',
    () {
      final source = img.Image(width: 200, height: 100);
      img.fill(source, color: img.ColorRgb8(220, 30, 20));
      final sourceBytes = Uint8List.fromList(img.encodePng(source));

      final orientedBytes = orientFrameForDetectionCoordinates(
        sourceBytes,
        expectedWidth: 100,
        expectedHeight: 200,
      );
      final oriented = img.decodeImage(orientedBytes);

      expect(oriented, isNotNull);
      expect(oriented!.width, 100);
      expect(oriented.height, 200);
    },
  );

  test(
    'single-image analysis returns the same processed crop sent to digit YOLO',
    () async {
      final source = img.Image(width: 200, height: 100);
      img.fill(source, color: img.ColorRgb8(220, 30, 20));
      final frameBytes = Uint8List.fromList(img.encodeJpg(source));
      final yolo = RecordingYolo();
      final service = SignNumberPipelineService(digitYolo: yolo);

      final result = await service.analyzeSingleImage(
        frameBytes: frameBytes,
        detectionResults: [trafficDetection()],
      );

      expect(result.cropBytes, isNotNull);
      expect(yolo.receivedImageBytes, same(result.cropBytes));
      expect(yolo.predictCallCount, 1);
      expect(result.number, '12');
      expect(result.selectedSign?.className, 'sign_number');
    },
  );

  test('single-image analysis skips digit YOLO when no sign exists', () async {
    final source = img.Image(width: 200, height: 100);
    final frameBytes = Uint8List.fromList(img.encodeJpg(source));
    final yolo = RecordingYolo();
    final service = SignNumberPipelineService(digitYolo: yolo);

    final result = await service.analyzeSingleImage(
      frameBytes: frameBytes,
      detectionResults: [trafficDetection(className: 'red_light_circle')],
    );

    expect(result.cropBytes, isNull);
    expect(result.number, isNull);
    expect(result.selectedSign, isNull);
    expect(yolo.predictCallCount, 0);
  });

  test(
    'single-image analysis retries a wider crop when the tight crop finds one digit',
    () async {
      final source = img.Image(width: 200, height: 100);
      final frameBytes = Uint8List.fromList(img.encodeJpg(source));
      final yolo = SequencedYolo([
        [digitDetection('1', left: 0.2, confidence: 0.95)],
        [
          digitDetection('1', left: 0.2, confidence: 0.90),
          digitDetection('0', left: 0.6, confidence: 0.92),
        ],
      ]);
      final service = SignNumberPipelineService(digitYolo: yolo);

      final result = await service.analyzeSingleImage(
        frameBytes: frameBytes,
        detectionResults: [trafficDetection()],
      );

      expect(yolo.receivedImages, hasLength(2));
      expect(result.cropBytes, same(yolo.receivedImages.last));
      expect(result.number, '10');
    },
  );

  test(
    'real-time analysis tries the opposite camera rotation when the first crop finds no digits',
    () async {
      final source = img.Image(width: 200, height: 100);
      final frameBytes = Uint8List.fromList(img.encodeJpg(source));
      final yolo = SequencedYolo([
        [],
        [],
        [digitDetection('1', left: 0.2), digitDetection('2', left: 0.6)],
      ]);
      final service = SignNumberPipelineService(digitYolo: yolo);

      final number = await service.detectNumberFromSign(
        frameBytes: frameBytes,
        detectionResults: [trafficDetection()],
        expectedFrameWidth: 100,
        expectedFrameHeight: 200,
      );

      expect(yolo.receivedImages, hasLength(3));
      expect(number, '12');
    },
  );

  test(
    'real-time analysis tries 180 degrees for an upside-down landscape frame',
    () async {
      final source = img.Image(width: 200, height: 100);
      final frameBytes = Uint8List.fromList(img.encodeJpg(source));
      final yolo = SequencedYolo([
        [],
        [],
        [digitDetection('1', left: 0.2), digitDetection('2', left: 0.6)],
      ]);
      final service = SignNumberPipelineService(digitYolo: yolo);

      final number = await service.detectNumberFromSign(
        frameBytes: frameBytes,
        detectionResults: [trafficDetection()],
        expectedFrameWidth: 200,
        expectedFrameHeight: 100,
      );

      expect(yolo.receivedImages, hasLength(3));
      expect(number, '12');
    },
  );

  test('real-time analysis exposes the failed crop for diagnostics', () async {
    final source = img.Image(width: 200, height: 100);
    final frameBytes = Uint8List.fromList(img.encodeJpg(source));
    final yolo = SequencedYolo([[], [], [], []]);
    final service = SignNumberPipelineService(digitYolo: yolo);

    final analysis = await service.analyzeRealtimeFrame(
      frameBytes: frameBytes,
      detectionResults: [trafficDetection()],
      expectedFrameWidth: 200,
      expectedFrameHeight: 100,
    );

    expect(analysis.number, isNull);
    expect(analysis.cropBytes, isNotNull);
    expect(analysis.selectedSign?.className, 'sign_number');
  });
}
