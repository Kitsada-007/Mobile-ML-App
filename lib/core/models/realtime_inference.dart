import 'dart:typed_data';

import 'package:trffic_ilght_app/services/yolo_result_adapter.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

class RealtimeFramePacket {
  const RealtimeFramePacket({
    required this.frameNumber,
    required this.timestamp,
    required this.detections,
    this.frameBytes,
    this.imageWidth,
    this.imageHeight,
    this.rotationDegrees,
    this.fps,
  });

  factory RealtimeFramePacket.fromMap(
    Map<String, dynamic> data, {
    required int fallbackFrameNumber,
  }) {
    final timestampMilliseconds = _readInt(data['timestamp']);
    return RealtimeFramePacket(
      frameNumber: _readInt(data['frameNumber']) ?? fallbackFrameNumber,
      timestamp: timestampMilliseconds == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(timestampMilliseconds),
      detections: parseYoloDetections(data['detections']),
      frameBytes: data['originalImage'] is Uint8List
          ? data['originalImage'] as Uint8List
          : null,
      imageWidth: _readInt(data['imageWidth']),
      imageHeight: _readInt(data['imageHeight']),
      rotationDegrees: _readInt(data['rotationDegrees']),
      fps: data['fps'] is num ? (data['fps'] as num).toDouble() : null,
    );
  }

  final int frameNumber;
  final DateTime timestamp;
  final List<YOLOResult> detections;
  final Uint8List? frameBytes;
  final int? imageWidth;
  final int? imageHeight;
  final int? rotationDegrees;
  final double? fps;
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
