import 'dart:typed_data';

import 'package:trffic_ilght_app/core/services/inference/yolo_result_adapter.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

/// แพ็กเก็ตข้อมูลเฟรม 1 เฟรมที่ส่งมาจากกล้อง/สตรีมเรียลไทม์ (ผ่าน callback)
/// เก็บทั้งผลตรวจจับ, ข้อมูลภาพต้นฉบับ และข้อมูลเวลา/สถิติต่าง ๆ ของเฟรม
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

  /// สร้าง RealtimeFramePacket จาก Map ที่กล้อง YOLO ส่งกลับมา
  factory RealtimeFramePacket.fromMap(
    Map<String, dynamic> data, {
    required int fallbackFrameNumber,
    DateTime? receivedAt,
  }) {
    DateTime callbackReceivedAt;
    if (receivedAt == null) {
      callbackReceivedAt = DateTime.now();
    } else {
      callbackReceivedAt = receivedAt;
    }

    final timestampMilliseconds = _readInt(data['timestamp']);
    DateTime resultProducedAt;
    if (timestampMilliseconds == null) {
      resultProducedAt = callbackReceivedAt;
    } else {
      resultProducedAt = DateTime.fromMillisecondsSinceEpoch(
        timestampMilliseconds,
      );
    }

    final processingTimeMilliseconds = _readDouble(data['processingTimeMs']);
    final detections = parseYoloDetections(data['detections']);
    final needsNumberCrop = detections.any(
      (detection) => detection.className == 'sign_number',
    );

    final parsedFrameNumber = _readInt(data['frameNumber']);
    int frameNumber;
    if (parsedFrameNumber == null) {
      frameNumber = fallbackFrameNumber;
    } else {
      frameNumber = parsedFrameNumber;
    }

    // เก็บภาพต้นฉบับเฉพาะเมื่อต้อง crop อ่านตัวเลขเท่านั้น (ประหยัดหน่วยความจำ)
    final originalImage = data['originalImage'];
    Uint8List? frameBytes;
    if (needsNumberCrop && originalImage is Uint8List) {
      frameBytes = originalImage;
    } else {
      frameBytes = null;
    }

    return RealtimeFramePacket(
      frameNumber: frameNumber,
      resultProducedAt: resultProducedAt,
      // ประมาณเวลาจับภาพโดยลบเวลาประมวลผลของกล้องออกจากเวลาที่ผลลัพธ์ถูกสร้าง
      estimatedCapturedAt: resultProducedAt.subtract(
        _durationFromMilliseconds(processingTimeMilliseconds),
      ),
      receivedAt: callbackReceivedAt,
      detections: detections,
      frameBytes: frameBytes,
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

  /// เวลาที่คาดว่าภาพถูกจับจริง = resultProducedAt ลบเวลาประมวลผลของกล้อง
  final DateTime estimatedCapturedAt;
  final DateTime receivedAt;
  final List<YOLOResult> detections;

  /// ภาพต้นฉบับ — มีเฉพาะเฟรมที่พบ `sign_number` เท่านั้น
  final Uint8List? frameBytes;
  final int? imageWidth;
  final int? imageHeight;
  final int? rotationDegrees;
  final double? fps;
  final double? processingTimeMilliseconds;
  final double? preProcessingMilliseconds;
  final double? inferenceMilliseconds;
  final double? postProcessingMilliseconds;

  /// ชื่อพ้องของ resultProducedAt ที่ diagnostics ยังเรียกใช้อยู่
  DateTime get timestamp => resultProducedAt;

  /// อายุของเฟรมนับจากเวลาที่คาดว่าจับภาพ — ใช้เช็คว่าเฟรมเก่าเกินไปไหม
  Duration ageAt(DateTime now) {
    final age = now.difference(estimatedCapturedAt);
    // กันค่าติดลบจากนาฬิกา native/Dart ที่ไม่ตรงกัน
    if (age.isNegative) {
      return Duration.zero;
    }
    return age;
  }
}

/// บันทึกผลการวินิจฉัย (diagnostic) ของการอ่านตัวเลข 1 รอบ
/// ใช้สำหรับ debug ว่าทำไมบางเฟรมถึงอ่านตัวเลขไม่ได้
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

  /// ขนาดภาพ crop — 0 แปลว่า crop ไม่สำเร็จ
  final int cropByteLength;
  final String? reading;
  final String? error;

  bool get foundNumber => reading != null;
}

int? _readInt(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return null;
}

double? _readDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return null;
}

Duration _durationFromMilliseconds(double? value) {
  if (value == null) {
    return Duration.zero;
  }
  return Duration(microseconds: (value * 1000).round());
}
