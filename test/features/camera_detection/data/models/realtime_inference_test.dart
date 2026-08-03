import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/features/camera_detection/data/models/realtime_inference.dart';

void main() {
  test('parses one camera callback into a typed frame packet', () {
    final imageBytes = Uint8List.fromList([1, 2, 3]);
    final packet = RealtimeFramePacket.fromMap({
      'frameNumber': 7,
      'timestamp': 1234,
      'detections': [
        {
          'classIndex': 0,
          'className': 'sign_number',
          'confidence': 0.9,
          'boundingBox': {
            'left': 10.0,
            'top': 20.0,
            'right': 30.0,
            'bottom': 40.0,
          },
          'normalizedBox': {
            'left': 0.1,
            'top': 0.2,
            'right': 0.3,
            'bottom': 0.4,
          },
        },
      ],
      'originalImage': imageBytes,
      'imageWidth': 640,
      'imageHeight': 480,
      'rotationDegrees': 90,
      'fps': 7,
    }, fallbackFrameNumber: 99);

    expect(packet.frameNumber, 7);
    expect(packet.timestamp, DateTime.fromMillisecondsSinceEpoch(1234));
    expect(packet.detections.single.className, 'sign_number');
    expect(packet.frameBytes, same(imageBytes));
    expect(packet.imageWidth, 640);
    expect(packet.imageHeight, 480);
    expect(packet.rotationDegrees, 90);
    expect(packet.fps, 7.0);
  });

  test('uses safe fallbacks for malformed camera metadata', () {
    final before = DateTime.now();
    final packet = RealtimeFramePacket.fromMap({
      'frameNumber': 'bad',
      'timestamp': 'bad',
      'detections': 'bad',
      'originalImage': <int>[1, 2, 3],
      'imageWidth': '640',
      'fps': '7',
    }, fallbackFrameNumber: 11);
    final after = DateTime.now();

    expect(packet.frameNumber, 11);
    expect(
      packet.timestamp.isBefore(before) || packet.timestamp.isAfter(after),
      isFalse,
    );
    expect(packet.detections, isEmpty);
    expect(packet.frameBytes, isNull);
    expect(packet.imageWidth, isNull);
    expect(packet.fps, isNull);
  });

  test('derives capture timing and stage metrics from native metadata', () {
    final receivedAt = DateTime.fromMillisecondsSinceEpoch(1400);
    final packet = RealtimeFramePacket.fromMap(
      {
        'frameNumber': 8,
        'timestamp': 1300,
        'processingTimeMs': 50,
        'preMs': 5,
        'inferenceMs': 35,
        'postMs': 10,
        'detections': [_signDetection()],
        'originalImage': Uint8List.fromList([4, 5, 6]),
      },
      fallbackFrameNumber: 99,
      receivedAt: receivedAt,
    );

    expect(packet.resultProducedAt, DateTime.fromMillisecondsSinceEpoch(1300));
    expect(
      packet.estimatedCapturedAt,
      DateTime.fromMillisecondsSinceEpoch(1250),
    );
    expect(packet.receivedAt, receivedAt);
    expect(packet.processingTimeMilliseconds, 50);
    expect(packet.preProcessingMilliseconds, 5);
    expect(packet.inferenceMilliseconds, 35);
    expect(packet.postProcessingMilliseconds, 10);
  });

  test('retains full frame bytes only when a number sign needs a crop', () {
    final imageBytes = Uint8List.fromList([1, 2, 3]);

    final ordinaryPacket = RealtimeFramePacket.fromMap({
      'detections': [_detection('red_light_circle')],
      'originalImage': imageBytes,
    }, fallbackFrameNumber: 1);
    final signPacket = RealtimeFramePacket.fromMap({
      'detections': [_signDetection()],
      'originalImage': imageBytes,
    }, fallbackFrameNumber: 2);

    expect(ordinaryPacket.frameBytes, isNull);
    expect(signPacket.frameBytes, same(imageBytes));
  });
}

Map<String, dynamic> _signDetection() => _detection('sign_number');

Map<String, dynamic> _detection(String className) => {
  'classIndex': 0,
  'className': className,
  'confidence': 0.9,
  'boundingBox': {'left': 10.0, 'top': 20.0, 'right': 30.0, 'bottom': 40.0},
  'normalizedBox': {'left': 0.1, 'top': 0.2, 'right': 0.3, 'bottom': 0.4},
};
