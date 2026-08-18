import 'dart:async';
import 'dart:collection';
import 'dart:developer';
import 'dart:typed_data';

import 'package:trffic_ilght_app/features/camera_detection/data/models/realtime_inference.dart';
import 'package:trffic_ilght_app/core/services/inference/countdown_reading_stabilizer.dart';
import 'package:trffic_ilght_app/core/services/inference/sign_number_pipeline_service.dart';

/// เอนจินสำหรับอ่านตัวเลขนับถอยหลังแบบเรียลไทม์จากเฟรมกล้อง
/// - เรียก pipeline อ่านตัวเลขเมื่อเจอป้าย sign_number ที่สอดคล้อง threshold
/// - คุมอัตราการตรวจ (detectionInterval) เพื่อไม่ให้ทำงานถี่เกินไป
/// - ใช้ CountdownReadingStabilizer เพื่อให้เลขอ่านได้เสถียร (กันค่ากระโดด)
/// - เก็บ diagnostics สำหรับ debug
class RealtimeNumberInferenceEngine {
  RealtimeNumberInferenceEngine({
    SignNumberPipelineService? service,
    Duration detectionInterval = const Duration(milliseconds: 400),
    CountdownReadingStabilizer? stabilizer,
    this.signConfidenceThreshold = 0.25,
    this.maximumDiagnostics = 20,
  }) {
    _service = service;
    _detectionInterval = detectionInterval;
    if (stabilizer == null) {
      _stabilizer = CountdownReadingStabilizer();
    } else {
      _stabilizer = stabilizer;
    }
  }

  SignNumberPipelineService? _service;
  late final Duration _detectionInterval;
  late final CountdownReadingStabilizer _stabilizer;
  final double signConfidenceThreshold;
  final int maximumDiagnostics;

  final Queue<RealtimeInferenceDiagnostic> _diagnostics = Queue();
  DateTime? _lastDetectionTime;

  /// ภาพ crop ล่าสุดที่อ่านเลขไม่สำเร็จ — เก็บไว้ให้ debug overlay ดู
  Uint8List? _lastFailedCropBytes;
  bool _isDetecting = false;
  bool _isDisposed = false;

  /// ตั้ง service ใหม่ (เมื่อโหลดโมเดลตัวเลขเสร็จ) แล้วปล่อยตัวเก่าทิ้ง
  set service(SignNumberPipelineService? value) {
    final previous = _service;
    _service = value;
    if (previous != null && !identical(previous, value)) {
      unawaited(previous.dispose());
    }
  }

  bool get isDetecting => _isDetecting;
  List<RealtimeInferenceDiagnostic> get diagnostics =>
      List.unmodifiable(_diagnostics);
  Uint8List? get lastFailedCropBytes => _lastFailedCropBytes;

  /// ประมวลผล 1 เฟรมเพื่ออ่านตัวเลข
  /// - คืนค่าตัวเลขนับถอยหลัง (ผ่าน stabilizer) หรือ null
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
      String errorMessage;
      if (service == null) {
        errorMessage = 'Number model is not ready';
      } else {
        errorMessage = 'Streaming frame has no originalImage';
      }
      _recordDiagnostic(
        RealtimeInferenceDiagnostic(
          frameNumber: packet.frameNumber,
          timestamp: packet.timestamp,
          elapsedMilliseconds: 0,
          cropByteLength: 0,
          error: errorMessage,
        ),
      );
      return null;
    }
    // กันงานซ้อน + ตรวจอัตรา (ยังไม่ถึงช่วงเวลาขั้นต่ำ -> ข้ามเฟรมนี้)
    if (_isDetecting || !_canRunDetection()) return null;

    _isDetecting = true;
    _lastDetectionTime = DateTime.now();
    final stopwatch = Stopwatch();
    stopwatch.start();

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
      final cropBytes = analysis.cropBytes;
      if (reading == null) {
        _lastFailedCropBytes = cropBytes;
      }
      int cropByteLength;
      if (cropBytes == null) {
        cropByteLength = 0;
      } else {
        cropByteLength = cropBytes.length;
      }
      _recordDiagnostic(
        RealtimeInferenceDiagnostic(
          frameNumber: packet.frameNumber,
          timestamp: packet.timestamp,
          elapsedMilliseconds: stopwatch.elapsedMilliseconds,
          cropByteLength: cropByteLength,
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
      _isDetecting = false; // สำคัญ: ปลดล็อกเพื่อให้รอบถัดไปตรวจจับได้
    }
  }

  /// ตรวจว่าผ่านช่วงเวลาขั้นต่ำระหว่างรอบหรือยัง
  bool _canRunDetection() {
    final lastDetectionTime = _lastDetectionTime;
    if (lastDetectionTime == null) return true;
    return DateTime.now().difference(lastDetectionTime) >= _detectionInterval;
  }

  /// บันทึก diagnostic (จำกัดจำนวนเพื่อไม่ให้หน่วยความจำเกิน)
  void _recordDiagnostic(RealtimeInferenceDiagnostic diagnostic) {
    _diagnostics.addLast(diagnostic);
    while (_diagnostics.length > maximumDiagnostics) {
      _diagnostics.removeFirst();
    }
  }

  /// รีเซ็ตสถานะของรอบ (เมื่อรีเซ็ตการตรวจจับ)
  void resetCycle() {
    _stabilizer.reset();
    _lastFailedCropBytes = null;
  }

  void dispose() {
    _isDisposed = true;
    _stabilizer.reset();
    final service = _service;
    _service = null;
    if (service != null) unawaited(service.dispose());
  }
}

/// ทำความสะอาดค่าตัวเลข (ตัดช่องว่าง) — คืน null ถ้าเป็น string ว่าง
String? _normalizeReading(String? reading) {
  if (reading == null) {
    return null;
  }
  final normalized = reading.trim();
  if (normalized.isEmpty) {
    return null;
  }
  return normalized;
}
