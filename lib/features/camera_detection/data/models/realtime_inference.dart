import 'dart:typed_data'; // ใช้ Uint8List (ข้อมูลภาพแบบไบนารี)

import 'package:trffic_ilght_app/core/services/inference/yolo_result_adapter.dart'; // แปลงผล YOLO (raw) ให้เป็น YOLOResult
import 'package:ultralytics_yolo/ultralytics_yolo.dart'; // โมเดล YOLO

/// แพ็กเก็ตข้อมูลเฟรม 1 เฟรมที่ส่งมาจากกล้อง/สตรีมเรียลไทม์ (ผ่าน callback)
/// เก็บทั้งผลตรวจจับ, ข้อมูลภาพต้นฉบับ และข้อมูลเวลา/สถิติต่าง ๆ ของเฟรม
class RealtimeFramePacket {
  const RealtimeFramePacket({
    required this.frameNumber, // เลขลำดับเฟรม
    required this.resultProducedAt, // เวลาที่กล้องสร้างผลลัพธ์เฟรมนี้
    required this.estimatedCapturedAt, // เวลาประมาณการที่ภาพถูกจับภาพ (หลังหักเวลาเฉลี่ย)
    required this.receivedAt, // เวลาที่แอปได้รับข้อมูลเฟรมนี้
    required this.detections, // รายการวัตถุที่ตรวจพบในเฟรม
    this.frameBytes, // ข้อมูลภาพต้นฉบับ (มีเฉพาะเมื่อเจอ sign_number เพื่อ crop อ่านเลข)
    this.imageWidth, // ความกว้างภาพต้นฉบับ
    this.imageHeight, // ความสูงภาพต้นฉบับ
    this.rotationDegrees, // องศาการหมุนของภาพจากกล้อง
    this.fps, // FPS ที่กล้องรายงาน
    this.processingTimeMilliseconds, // เวลาประมวลผลทั้งหมด (ms)
    this.preProcessingMilliseconds, // เวลาก่อนประมวลผล (ms)
    this.inferenceMilliseconds, // เวลาทำ inference (ms)
    this.postProcessingMilliseconds, // เวลาหลังประมวลผล (ms)
  });

  /// สร้าง RealtimeFramePacket จาก Map ที่กล้อง YOLO ส่งกลับมา
  /// (factory — ใช้ในตอนรับข้อมูลสดจาก native stream)
  factory RealtimeFramePacket.fromMap(
    Map<String, dynamic> data, {
    required int fallbackFrameNumber, // ใช้เป็นเลขเฟรมสำรองถ้าไม่มีใน data
    DateTime? receivedAt, // เวลาที่รับข้อมูล (default = ตอนนี้)
  }) {
    final callbackReceivedAt = receivedAt ?? DateTime.now();
    final timestampMilliseconds = _readInt(
      data['timestamp'],
    ); // timestamp จากกล้อง
    final resultProducedAt = timestampMilliseconds == null
        ? callbackReceivedAt
        : DateTime.fromMillisecondsSinceEpoch(timestampMilliseconds);
    final processingTimeMilliseconds = _readDouble(data['processingTimeMs']);
    final detections = parseYoloDetections(
      data['detections'],
    ); // แปลงผลเป็น YOLOResult
    // ต้องการภาพต้นฉบับเฉพาะเมื่อตรวจพบ sign_number (เพื่ออ่านตัวเลขในขั้นถัดไป)
    final needsNumberCrop = detections.any(
      (detection) => detection.className == 'sign_number',
    );

    return RealtimeFramePacket(
      frameNumber: _readInt(data['frameNumber']) ?? fallbackFrameNumber,
      resultProducedAt: resultProducedAt,
      // ประมาณเวลาจับภาพโดยลบเวลาเฉลี่ยของกล้องออกจากเวลาที่ผลลัพธ์ถูกสร้าง
      estimatedCapturedAt: resultProducedAt.subtract(
        _durationFromMilliseconds(processingTimeMilliseconds),
      ),
      receivedAt: callbackReceivedAt,
      detections: detections,
      // มีภาพต้นฉบับเมื่อจำเป็นต้อง crop ตัวเลขเท่านั้น (ประหยัดหน่วยความจำ)
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

  /// ชื่อเดิม (เก่า) ที่ใช้ใน diagnostics — คืนค่าเดียวกับ resultProducedAt
  /// ให้โค้ดเก่าที่ยังใช้ `packet.timestamp` ยังทำงานได้
  DateTime get timestamp => resultProducedAt;

  /// คำนวณอายุของเฟรม (นานแค่ไหนตั้งแต่จับภาพถึงตอนนี้) — ใช้เช็คว่าเฟรมเก่าเกินไปไหม
  Duration ageAt(DateTime now) {
    final age = now.difference(estimatedCapturedAt);
    return age.isNegative
        ? Duration.zero
        : age; // กันค่าติดลบ (นาฬิกาไม่ตรงกัน)
  }
}

/// บันทึกผลการวินิจฉัย (diagnostic) ของการอ่านตัวเลข 1 รอบ
/// ใช้สำหรับ debug ว่าทำไมบางเฟรมถึงอ่านตัวเลขไม่ได้
class RealtimeInferenceDiagnostic {
  const RealtimeInferenceDiagnostic({
    required this.frameNumber, // เลขเฟรม
    required this.timestamp, // เวลาของเฟรม
    required this.elapsedMilliseconds, // เวลาที่ใช้ในรอบนี้ (ms)
    required this.cropByteLength, // ขนาดของภาพ crop (เก็บไว้ดูว่า crop สำเร็จไหม)
    this.reading, // ตัวเลขที่อ่านได้ (null = อ่านไม่สำเร็จ)
    this.error, // ข้อความ error (ถ้ามี)
  });

  final int frameNumber;
  final DateTime timestamp;
  final int elapsedMilliseconds;
  final int cropByteLength;
  final String? reading;
  final String? error;

  /// ตรวจพบตัวเลขหรือไม่ (อ่านได้ = มีค่า reading)
  bool get foundNumber => reading != null;
}

// ---- Helper functions สำหรับอ่านค่า Num จาก data ดิบของกล้อง ----
int? _readInt(Object? value) => value is num ? value.toInt() : null;

double? _readDouble(Object? value) => value is num ? value.toDouble() : null;

/// แปลงค่าเป็นมิลลิวินาทีเป็น Duration (กันค่าติดลบ)
Duration _durationFromMilliseconds(double? value) =>
    Duration(microseconds: value == null ? 0 : (value * 1000).round());
