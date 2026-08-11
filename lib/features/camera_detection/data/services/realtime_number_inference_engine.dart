import 'dart:async'; // ใช้ unawaited
import 'dart:collection'; // ใช้ Queue
import 'dart:developer'; // ใช้ log
import 'dart:typed_data'; // ใช้ Uint8List

import 'package:trffic_ilght_app/features/camera_detection/data/models/realtime_inference.dart'; // โครงสร้าง RealtimeFramePacket
import 'package:trffic_ilght_app/core/services/inference/countdown_reading_stabilizer.dart'; // กันเลขสั่นไหว
import 'package:trffic_ilght_app/core/services/inference/sign_number_pipeline_service.dart'; // pipeline อ่านตัวเลขป้าย

/// เอนจินสำหรับอ่านตัวเลขนับถอยหลังแบบเรียลไทม์จากเฟรมกล้อง
/// - เรียก pipeline อ่านตัวเลขเมื่อเจอป้าย sign_number ที่สอดคล้อง threshold
/// - คุมอัตราการตรวจ (detectionInterval) เพื่อไม่ให้ทำงานถี่เกินไป
/// - ใช้ CountdownReadingStabilizer เพื่อให้เลขอ่านได้เสถียร (กันค่ากระโดด)
/// - เก็บ diagnostics สำหรับ debug
class RealtimeNumberInferenceEngine {
  RealtimeNumberInferenceEngine({
    SignNumberPipelineService?
    service, // บริการอ่านตัวเลข (มีเมื่อโหลดโมเดลแล้ว)
    Duration detectionInterval = const Duration(
      milliseconds: 400,
    ), // เวลาห่างขั้นต่ำระหว่างรอบ (default 400ms)
    CountdownReadingStabilizer? stabilizer, // ตัวกันเลขสั่นไหว
    this.signConfidenceThreshold =
        0.25, // ค่า confidence ต่ำสุดของป้าย sign_number
    this.maximumDiagnostics = 20, // จำกัดจำนวน diagnostic ที่เก็บไว้
  }) : _service = service,
       _detectionInterval = detectionInterval,
       _stabilizer = stabilizer ?? CountdownReadingStabilizer();

  SignNumberPipelineService?
  _service; // บริการอ่านตัวเลข (เปลี่ยนได้ตอนโหลดโมเดลเสร็จ)
  final Duration _detectionInterval; // ช่วงเวลาขั้นต่ำระหว่างการตรวจจับ
  final CountdownReadingStabilizer _stabilizer; // กันเลขสั่นไหว
  final double signConfidenceThreshold; // threshold สำหรับป้ายตัวเลข
  final int maximumDiagnostics; // จำนวน diagnostic สูงสุด

  final Queue<RealtimeInferenceDiagnostic> _diagnostics =
      Queue(); // เก็บประวัติ debug
  DateTime? _lastDetectionTime; // เวลาของรอบตรวจจับล่าสุด (ใช้คุมอัตรา)
  Uint8List?
  _lastFailedCropBytes; // ภาพ crop ล่าสุดที่อ่านเลขไม่สำเร็จ (สำหรับ debug)
  bool _isDetecting = false; // กำลังตรวจจับอยู่หรือไม่ (กันงานซ้อน)
  bool _isDisposed = false; // ถูก dispose แล้วหรือยัง

  /// ตั้ง service ใหม่ (เมื่อโหลดโมเดลตัวเลขเสร็จ)
  /// - ปล่อย service ตัวเก่าออกถ้าเปลี่ยนเป็นตัวใหม่
  set service(SignNumberPipelineService? value) {
    final previous = _service;
    _service = value;
    if (previous != null && !identical(previous, value)) {
      unawaited(previous.dispose()); // ปล่อย service เก่า
    }
  }

  bool get isDetecting => _isDetecting;
  List<RealtimeInferenceDiagnostic> get diagnostics =>
      List.unmodifiable(_diagnostics); // อ่านได้อย่างเดียว
  Uint8List? get lastFailedCropBytes => _lastFailedCropBytes;

  /// ประมวลผล 1 เฟรมเพื่ออ่านตัวเลข
  /// - คืนค่าตัวเลขนับถอยหลัง (ผ่าน stabilizer) หรือ null
  Future<String?> process(
    RealtimeFramePacket packet, {
    required bool
    enabled, // เปิดการอ่านตัวเลขหรือไม่ (เช่น หลังพูด "เก็ตเรดี้" แล้วปิด)
  }) async {
    if (_isDisposed || !enabled) return null;

    // ตรวจว่ามีป้าย sign_number ที่ confidence ผ่านเกณฑ์ในเฟรมนี้หรือไม่
    final hasQualifiedSign = packet.detections.any(
      (result) =>
          result.className == 'sign_number' &&
          result.confidence >= signConfidenceThreshold,
    );
    if (!hasQualifiedSign) return null;

    final service = _service;
    final frameBytes = packet.frameBytes;
    // ถ้ายังไม่มี service หรือไม่มีภาพต้นฉบับ -> บันทึก diagnostic แล้วคืน null
    if (service == null || frameBytes == null) {
      _recordDiagnostic(
        RealtimeInferenceDiagnostic(
          frameNumber: packet.frameNumber,
          timestamp: packet.timestamp,
          elapsedMilliseconds: 0,
          cropByteLength: 0,
          error: service == null
              ? 'Number model is not ready' // โมเดลตัวเลขยังไม่พร้อม
              : 'Streaming frame has no originalImage', // เฟรมไม่มีภาพต้นฉบับ
        ),
      );
      return null;
    }
    // กันงานซ้อน + ตรวจอัตรา (ยังไม่ถึงช่วงเวลาขั้นต่ำ -> ข้ามเฟรมนี้)
    if (_isDetecting || !_canRunDetection()) return null;

    _isDetecting = true;
    _lastDetectionTime = DateTime.now();
    final stopwatch = Stopwatch()..start(); // จับเวลา

    try {
      // เรียก pipeline อ่านตัวเลขจากเฟรม (ใช้ภาพต้นฉบับ + ผลตรวจจับจากไฟจราจร)
      final analysis = await service.analyzeRealtimeFrame(
        frameBytes: frameBytes,
        detectionResults: packet.detections,
        expectedFrameWidth: packet.imageWidth,
        expectedFrameHeight: packet.imageHeight,
        rotationDegrees: packet.rotationDegrees,
      );
      stopwatch.stop();
      if (_isDisposed) return null;

      final reading = _normalizeReading(analysis.number); // ตัดช่องว่าง
      final stabilizedReading = _stabilizer.add(reading); // กันเลขสั่นไหว
      if (reading == null) {
        _lastFailedCropBytes =
            analysis.cropBytes; // เก็บ crop ที่อ่านไม่ได้ไว้ debug
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
      _diagnostics.removeFirst(); // ถ้าเกินให้ลบตัวที่เก่าที่สุด
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
    if (service != null) unawaited(service.dispose()); // ปล่อย service
  }
}

/// ทำความสะอาดค่าตัวเลข (ตัดช่องว่าง) — คืน null ถ้าเป็น string ว่าง
String? _normalizeReading(String? reading) {
  final normalized = reading?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
