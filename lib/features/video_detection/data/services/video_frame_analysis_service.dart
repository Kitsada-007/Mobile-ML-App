import 'package:flutter/foundation.dart'; // Uint8List (ข้อมูลภาพไบนารี)
import 'package:trffic_ilght_app/core/services/inference/sign_number_pipeline_service.dart'; // Pipeline อ่านตัวเลขจากป้ายไฟ
import 'package:trffic_ilght_app/core/services/inference/yolo_result_adapter.dart'; // แปลงผล YOLO (raw) เป็น YOLOResult
import 'package:ultralytics_yolo/ultralytics_yolo.dart'; // โมเดล YOLO

// ค่า threshold เริ่มต้นสำหรับการตรวจจับไฟจราจรในวิดีโอ
const double videoTrafficConfidenceThreshold =
    0.25; // ต่ำสุดที่เชื่อว่าตรวจพบ (กัน false positive)
const double videoTrafficIouThreshold = 0.45; // ค่า IoU สำหรับกลบกล่องซ้ำ (NMS)

/// ผลลัพธ์การวิเคราะห์วิดีโอ 1 เฟรม
class VideoFrameAnalysisResult {
  const VideoFrameAnalysisResult({
    required this.outputImageBytes,
    required this.detections,
    this.detectedNumber,
  });

  final Uint8List outputImageBytes; // ภาพที่ annotate (วาดกล่อง) แล้ว
  final List<YOLOResult> detections; // รายการวัตถุที่ตรวจพบในเฟรม
  final String? detectedNumber; // ตัวเลขนับถอยหลังที่อ่านได้จากป้าย (ถ้ามี)
}

/// บริการวิเคราะห์เฟรมวิดีโอแบบ 2 ขั้นตอน (Dual-stage):
/// 1. ตรวจจับวัตถุไฟจราจรด้วยโมเดลหลักก่อน
/// 2. แล้วถ้าเจอบริเวณ `sign_number` (ป้ายตัวเลข) ให้รันโมเดลตัวเลขอ่านค่า
class VideoFrameAnalysisService {
  VideoFrameAnalysisService({
    required YOLO trafficYolo, // โมเดลตรวจจับไฟจราจร
    required SignNumberPipelineService
    signNumberPipeline, // pipeline อ่านตัวเลข
  }) : _trafficYolo = trafficYolo,
       _signNumberPipeline = signNumberPipeline;

  final YOLO _trafficYolo; // โมเดลหลัก (ตรวจจับไฟจราจร)
  final SignNumberPipelineService
  _signNumberPipeline; // pipeline อ่านตัวเลขป้าย

  /// วิเคราะห์ภาพ 1 เฟรม (ไบต์ภาพ) และคืนผลลัพธ์การตรวจจับทั้งหมด
  Future<VideoFrameAnalysisResult> analyze(Uint8List frameBytes) async {
    // ขั้นตอนที่ 1: ตรวจจับไฟจราจรด้วยโมเดลหลัก
    final trafficResult = await _trafficYolo.predict(
      frameBytes,
      confidenceThreshold: videoTrafficConfidenceThreshold,
      iouThreshold: videoTrafficIouThreshold,
    );
    // แปลงผลตรวจจับ raw เป็น list ของ YOLOResult
    final detections = parseYoloDetections(trafficResult['detections']);

    // ขั้นตอนที่ 2: อ่านตัวเลขจากป้าย (ถ้าเจอบริเวณ sign_number)
    final signAnalysis = await _signNumberPipeline.analyzeSingleImage(
      frameBytes: frameBytes,
      detectionResults: detections,
    );

    // ภาพที่ annotate แล้ว (fallback เป็นภาพต้นฉบับถ้าไม่มี)
    final annotatedImage = trafficResult['annotatedImage'];

    return VideoFrameAnalysisResult(
      outputImageBytes: annotatedImage is Uint8List && annotatedImage.isNotEmpty
          ? annotatedImage
          : frameBytes,
      detections: detections,
      detectedNumber: signAnalysis.number, // ตัวเลขที่อ่านได้ (null ถ้าไม่มี)
    );
  }
}
