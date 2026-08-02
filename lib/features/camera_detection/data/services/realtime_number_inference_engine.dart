import 'dart:collection';
import 'dart:developer';
import 'dart:typed_data';

import 'package:trffic_ilght_app/features/camera_detection/data/models/realtime_inference.dart';
import 'package:trffic_ilght_app/core/services/inference/countdown_reading_stabilizer.dart';
import 'package:trffic_ilght_app/core/services/inference/sign_number_pipeline_service.dart';

class RealtimeNumberInferenceEngine {
  RealtimeNumberInferenceEngine({
    SignNumberPipelineService? service,
    Duration detectionInterval = const Duration(milliseconds: 400),
    CountdownReadingStabilizer? stabilizer,
    this.signConfidenceThreshold = 0.25,
    this.maximumDiagnostics = 20,
  }) : _service = service,
       _detectionInterval = detectionInterval,
       _stabilizer = stabilizer ?? CountdownReadingStabilizer();

  SignNumberPipelineService? _service;
  final Duration _detectionInterval;
  final CountdownReadingStabilizer _stabilizer;
  final double signConfidenceThreshold;
  final int maximumDiagnostics;

  final Queue<RealtimeInferenceDiagnostic> _diagnostics = Queue();
  DateTime? _lastDetectionTime;
  Uint8List? _lastFailedCropBytes;
  bool _isDetecting = false;
  bool _isDisposed = false;

  set service(SignNumberPipelineService? value) => _service = value;

  bool get isDetecting => _isDetecting;
  List<RealtimeInferenceDiagnostic> get diagnostics =>
      List.unmodifiable(_diagnostics);
  Uint8List? get lastFailedCropBytes => _lastFailedCropBytes;

  Future<String?> process(
    RealtimeFramePacket packet, {
    required bool enabled,
  }) async {
    if (_isDisposed || !enabled) return null;

    final hasQualifiedSign = packet.detections.any(
      (result) =>
          result.className == 'sign_number' &&
          result.confidence >= signConfidenceThreshold,
    );
    if (!hasQualifiedSign) return null;

    final service = _service;
    final frameBytes = packet.frameBytes;
    if (service == null || frameBytes == null) {
      _recordDiagnostic(
        RealtimeInferenceDiagnostic(
          frameNumber: packet.frameNumber,
          timestamp: packet.timestamp,
          elapsedMilliseconds: 0,
          cropByteLength: 0,
          error: service == null
              ? 'Number model is not ready'
              : 'Streaming frame has no originalImage',
        ),
      );
      return null;
    }
    if (_isDetecting || !_canRunDetection()) return null;

    _isDetecting = true;
    _lastDetectionTime = DateTime.now();
    final stopwatch = Stopwatch()..start();

    try {
      final analysis = await service.analyzeRealtimeFrame(
        frameBytes: frameBytes,
        detectionResults: packet.detections,
        expectedFrameWidth: packet.imageWidth,
        expectedFrameHeight: packet.imageHeight,
        rotationDegrees: packet.rotationDegrees,
      );
      stopwatch.stop();
      if (_isDisposed) return null;

      final reading = _normalizeReading(analysis.number);
      final stabilizedReading = _stabilizer.add(reading);
      if (reading == null) {
        _lastFailedCropBytes = analysis.cropBytes;
      }
      _recordDiagnostic(
        RealtimeInferenceDiagnostic(
          frameNumber: packet.frameNumber,
          timestamp: packet.timestamp,
          elapsedMilliseconds: stopwatch.elapsedMilliseconds,
          cropByteLength: analysis.cropBytes?.length ?? 0,
          reading: reading,
        ),
      );
      return stabilizedReading;
    } catch (error, stackTrace) {
      stopwatch.stop();
      if (!_isDisposed) {
        _recordDiagnostic(
          RealtimeInferenceDiagnostic(
            frameNumber: packet.frameNumber,
            timestamp: packet.timestamp,
            elapsedMilliseconds: stopwatch.elapsedMilliseconds,
            cropByteLength: 0,
            error: error.toString(),
          ),
        );
        log(
          'Real-time sign-number pipeline error on frame '
          '${packet.frameNumber}: $error',
          stackTrace: stackTrace,
        );
      }
      return null;
    } finally {
      _isDetecting = false;
    }
  }

  bool _canRunDetection() {
    final lastDetectionTime = _lastDetectionTime;
    if (lastDetectionTime == null) return true;
    return DateTime.now().difference(lastDetectionTime) >= _detectionInterval;
  }

  void _recordDiagnostic(RealtimeInferenceDiagnostic diagnostic) {
    _diagnostics.addLast(diagnostic);
    while (_diagnostics.length > maximumDiagnostics) {
      _diagnostics.removeFirst();
    }
  }

  void resetCycle() {
    _stabilizer.reset();
    _lastFailedCropBytes = null;
  }

  void dispose() {
    _isDisposed = true;
    _stabilizer.reset();
  }
}

String? _normalizeReading(String? reading) {
  final normalized = reading?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
