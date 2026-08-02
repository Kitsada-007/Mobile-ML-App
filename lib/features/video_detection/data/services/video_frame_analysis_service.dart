import 'package:flutter/foundation.dart';
import 'package:trffic_ilght_app/core/services/inference/sign_number_pipeline_service.dart';
import 'package:trffic_ilght_app/core/services/inference/yolo_result_adapter.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

const double videoTrafficConfidenceThreshold = 0.25;
const double videoTrafficIouThreshold = 0.45;

class VideoFrameAnalysisResult {
  const VideoFrameAnalysisResult({
    required this.outputImageBytes,
    required this.detections,
    this.detectedNumber,
  });

  final Uint8List outputImageBytes;
  final List<YOLOResult> detections;
  final String? detectedNumber;
}

/// Runs both stages of video-frame inference: traffic objects first, then the
/// digit model only when the traffic model found a `sign_number` region.
class VideoFrameAnalysisService {
  VideoFrameAnalysisService({
    required YOLO trafficYolo,
    required SignNumberPipelineService signNumberPipeline,
  }) : _trafficYolo = trafficYolo,
       _signNumberPipeline = signNumberPipeline;

  final YOLO _trafficYolo;
  final SignNumberPipelineService _signNumberPipeline;

  Future<VideoFrameAnalysisResult> analyze(Uint8List frameBytes) async {
    final trafficResult = await _trafficYolo.predict(
      frameBytes,
      confidenceThreshold: videoTrafficConfidenceThreshold,
      iouThreshold: videoTrafficIouThreshold,
    );
    final detections = parseYoloDetections(trafficResult['detections']);
    final signAnalysis = await _signNumberPipeline.analyzeSingleImage(
      frameBytes: frameBytes,
      detectionResults: detections,
    );
    final annotatedImage = trafficResult['annotatedImage'];

    return VideoFrameAnalysisResult(
      outputImageBytes: annotatedImage is Uint8List && annotatedImage.isNotEmpty
          ? annotatedImage
          : frameBytes,
      detections: detections,
      detectedNumber: signAnalysis.number,
    );
  }
}
