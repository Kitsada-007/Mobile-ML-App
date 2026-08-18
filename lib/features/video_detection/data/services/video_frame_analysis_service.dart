import 'package:flutter/foundation.dart';
import 'package:trffic_ilght_app/core/services/inference/sign_number_pipeline_service.dart';
import 'package:trffic_ilght_app/core/services/inference/yolo_result_adapter.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

/// ต่ำสุดที่เชื่อว่าตรวจพบจริง (กัน false positive)
const double videoTrafficConfidenceThreshold = 0.25;

/// ค่า IoU สำหรับกลบกล่องซ้ำ (NMS)
const double videoTrafficIouThreshold = 0.45;

/// ผลลัพธ์การวิเคราะห์วิดีโอ 1 เฟรม
class VideoFrameAnalysisResult {
  const VideoFrameAnalysisResult({
    required this.outputImageBytes,
    required this.detections,
    this.detectedNumber,
  });

  /// ภาพที่ annotate (วาดกล่อง) แล้ว
  final Uint8List outputImageBytes;
  final List<YOLOResult> detections;

  /// ตัวเลขนับถอยหลังที่อ่านได้จากป้าย (null = อ่านไม่ได้)
  final String? detectedNumber;
}

/// บริการวิเคราะห์เฟรมวิดีโอแบบ 2 ขั้นตอน (Dual-stage):
/// 1. ตรวจจับวัตถุไฟจราจรด้วยโมเดลหลักก่อน
/// 2. แล้วถ้าเจอบริเวณ `sign_number` (ป้ายตัวเลข) ให้รันโมเดลตัวเลขอ่านค่า
class VideoFrameAnalysisService {
  VideoFrameAnalysisService({
    required YOLO trafficYolo,
    required SignNumberPipelineService signNumberPipeline,
  }) {
    _trafficYolo = trafficYolo;
    _signNumberPipeline = signNumberPipeline;
  }

  late final YOLO _trafficYolo;
  late final SignNumberPipelineService _signNumberPipeline;

  int _trafficPredictMicros = 0;
  int _signPipelineMicros = 0;
  int _analyzedFrameCount = 0;

  /// รีเซ็ตตัวสะสมเวลา (เรียกก่อนเริ่มประมวลผลวิดีโอแต่ละไฟล์)
  void resetTiming() {
    _trafficPredictMicros = 0;
    _signPipelineMicros = 0;
    _analyzedFrameCount = 0;
  }

  /// สรุปเวลาเฉลี่ยต่อเฟรมของแต่ละขั้นตอน (ใช้เทียบ before/after ตอนวัดผล)
  String timingSummary() {
    if (_analyzedFrameCount == 0) return 'no frames analyzed';
    final avgTraffic = _trafficPredictMicros / _analyzedFrameCount / 1000;
    final avgSign = _signPipelineMicros / _analyzedFrameCount / 1000;
    return 'frames=$_analyzedFrameCount '
        'trafficPredict avg=${avgTraffic.toStringAsFixed(1)}ms '
        'signPipeline avg=${avgSign.toStringAsFixed(1)}ms';
  }

  /// วิเคราะห์ภาพ 1 เฟรม (ไบต์ภาพ) และคืนผลลัพธ์การตรวจจับทั้งหมด
  Future<VideoFrameAnalysisResult> analyze(Uint8List frameBytes) async {
    final stopwatch = Stopwatch();
    stopwatch.start();
    final trafficResult = await _trafficYolo.predict(
      frameBytes,
      confidenceThreshold: videoTrafficConfidenceThreshold,
      iouThreshold: videoTrafficIouThreshold,
    );
    _trafficPredictMicros += stopwatch.elapsedMicroseconds;
    final detections = parseYoloDetections(trafficResult['detections']);

    // ใช้เส้นทาง realtime (PersistentSignCropWorker): isolate เดียวที่ reuse,
    // decode ภาพครั้งเดียวได้ crop ทั้ง tight/wide — แทน analyzeSingleImage
    // ที่ spawn isolate ใหม่ + decode ซ้ำต่อ crop ทุกเฟรม
    // rotationDegrees: 0 เพราะเฟรมจาก ffmpeg ตั้งตรงเสมอ (ไม่ต้องเดาการหมุน
    // และเป็นการปิด fallback ลองหมุนทิศอื่นซึ่งไม่จำเป็นกับวิดีโอ)
    stopwatch.reset();
    final signAnalysis = await _signNumberPipeline.analyzeRealtimeFrame(
      frameBytes: frameBytes,
      detectionResults: detections,
      rotationDegrees: 0,
    );
    _signPipelineMicros += stopwatch.elapsedMicroseconds;
    _analyzedFrameCount += 1;

    final annotatedImage = trafficResult['annotatedImage'];

    // ถ้า native ไม่ส่งภาพ annotate กลับมา ใช้ภาพต้นฉบับแทน
    Uint8List outputImageBytes;
    if (annotatedImage is Uint8List && annotatedImage.isNotEmpty) {
      outputImageBytes = annotatedImage;
    } else {
      outputImageBytes = frameBytes;
    }

    return VideoFrameAnalysisResult(
      outputImageBytes: outputImageBytes,
      detections: detections,
      detectedNumber: signAnalysis.number,
    );
  }
}
