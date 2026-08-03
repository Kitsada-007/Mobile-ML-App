import 'dart:typed_data';

import 'package:trffic_ilght_app/core/services/inference/yolo_result_adapter.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

class RealtimeFramePacket {
  const RealtimeFramePacket({
    required this.frameNumber,
    required this.resultProducedAt,
    required this.estimatedCapturedAt,
    required this.receivedAt,
    required this.detections,
    this.frameBytes,
    this.imageWidth,
    this.imageHeight,
    this.rotationDegrees,
    this.fps,
    this.processingTimeMilliseconds,
    this.preProcessingMilliseconds,
    this.inferenceMilliseconds,
    this.postProcessingMilliseconds,
  });

  factory RealtimeFramePacket.fromMap(
    Map<String, dynamic> data, {
    required int fallbackFrameNumber,
    DateTime? receivedAt,
  }) {
    final callbackReceivedAt = receivedAt ?? DateTime.now();
    final timestampMilliseconds = _readInt(data['timestamp']);
    final resultProducedAt = timestampMilliseconds == null
        ? callbackReceivedAt
        : DateTime.fromMillisecondsSinceEpoch(timestampMilliseconds);
    final processingTimeMilliseconds = _readDouble(data['processingTimeMs']);
    final detections = parseYoloDetections(data['detections']);
    final needsNumberCrop = detections.any(
      (detection) => detection.className == 'sign_number',
    );

    return RealtimeFramePacket(
      frameNumber: _readInt(data['frameNumber']) ?? fallbackFrameNumber,
      resultProducedAt: resultProducedAt,
      estimatedCapturedAt: resultProducedAt.subtract(
        _durationFromMilliseconds(processingTimeMilliseconds),
      ),
      receivedAt: callbackReceivedAt,
      detections: detections,
      frameBytes: needsNumberCrop && data['originalImage'] is Uint8List
          ? data['originalImage'] as Uint8List
          : null,
      imageWidth: _readInt(data['imageWidth']),
      imageHeight: _readInt(data['imageHeight']),
      rotationDegrees: _readInt(data['rotationDegrees']),
      fps: _readDouble(data['fps']),
      processingTimeMilliseconds: processingTimeMilliseconds,
      preProcessingMilliseconds: _readDouble(data['preMs']),
      inferenceMilliseconds: _readDouble(data['inferenceMs']),
      postProcessingMilliseconds: _readDouble(data['postMs']),
    );
  }

  final int frameNumber;
  final DateTime resultProducedAt;
  final DateTime estimatedCapturedAt;
  final DateTime receivedAt;
  final List<YOLOResult> detections;
  final Uint8List? frameBytes;
  final int? imageWidth;
  final int? imageHeight;
  final int? rotationDegrees;
  final double? fps;
  final double? processingTimeMilliseconds;
  final double? preProcessingMilliseconds;
  final double? inferenceMilliseconds;
  final double? postProcessingMilliseconds;

  /// Backwards-compatible name used by existing diagnostics.
  DateTime get timestamp => resultProducedAt;

  Duration ageAt(DateTime now) {
    final age = now.difference(estimatedCapturedAt);
    return age.isNegative ? Duration.zero : age;
  }
}

class RealtimeInferenceDiagnostic {
  const RealtimeInferenceDiagnostic({
    required this.frameNumber,
    required this.timestamp,
    required this.elapsedMilliseconds,
    required this.cropByteLength,
    this.reading,
    this.error,
  });

  final int frameNumber;
  final DateTime timestamp;
  final int elapsedMilliseconds;
  final int cropByteLength;
  final String? reading;
  final String? error;

  bool get foundNumber => reading != null;
}

int? _readInt(Object? value) => value is num ? value.toInt() : null;

double? _readDouble(Object? value) => value is num ? value.toDouble() : null;

Duration _durationFromMilliseconds(double? value) =>
    Duration(microseconds: value == null ? 0 : (value * 1000).round());
