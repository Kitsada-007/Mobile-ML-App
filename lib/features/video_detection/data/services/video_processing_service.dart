import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:trffic_ilght_app/core/services/inference/countdown_reading_stabilizer.dart';
import 'package:trffic_ilght_app/features/video_detection/data/services/video_frame_analysis_service.dart';
import 'package:trffic_ilght_app/features/video_detection/data/services/video_label_formatter.dart';
import 'package:ultralytics_yolo/yolo.dart';

/// Single frame analysis result
class FrameAnalysisResult {
  const FrameAnalysisResult({required this.detections, this.detectedNumber});

  final List<YOLOResult> detections;
  final String? detectedNumber;
}

/// Result data from realtime video processing pipeline.
class VideoProcessingResult {
  const VideoProcessingResult({
    required this.finalVideoPath,
    required this.frameResults,
    required this.detectedClasses,
    required this.detectedNumbers,
    this.targetFps = 5,
  });

  final String finalVideoPath;
  final Map<int, FrameAnalysisResult> frameResults;
  final Set<String> detectedClasses;
  final Set<String> detectedNumbers;
  final int targetFps;
}

/// Service for video detection pipeline:
/// Extracts frames -> Analyzes dual-stage YOLO per frame -> Builds realtime frame overlay map.
class VideoProcessingService {
  Future<VideoProcessingResult> processVideo({
    required File videoFile,
    required VideoFrameAnalysisService frameAnalysisService,
    required CountdownReadingStabilizer countdownStabilizer,
    required void Function(double progressValue, String progressText)
    onProgress,
    int targetFps = 5,
    int sampleEveryNFrames = 5,
  }) async {
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final String inputFolder = '${directory.path}/yolo_frames_in_$timestamp';

    final detectedClasses = <String>{};
    final detectedNumbers = <String>{};
    final frameResults = <int, FrameAnalysisResult>{};

    final inputDir = Directory(inputFolder);
    if (await inputDir.exists()) {
      await inputDir.delete(recursive: true);
    }
    await inputDir.create(recursive: true);

    try {
      // 1. Extract frames from video using FFmpeg
      onProgress(0.0, 'กำลังสกัดเฟรมจากวิดีโอ ($targetFps FPS)...');

      final String extractCmd =
          '-threads 0 '
          '-i "${videoFile.path}" '
          '-vf "fps=$targetFps,scale=640:-1:flags=fast_bilinear" '
          '-q:v 5 '
          '-y "$inputFolder/frame_%05d.jpg"';

      final extractSession = await FFmpegKit.execute(extractCmd);
      final extractReturnCode = await extractSession.getReturnCode();

      if (!ReturnCode.isSuccess(extractReturnCode)) {
        throw Exception('Failed to extract frames from video.');
      }

      final List<FileSystemEntity> frameFiles = inputDir.listSync()
        ..sort((a, b) => a.path.compareTo(b.path));

      final int totalFrames = frameFiles.length;
      if (totalFrames == 0) {
        throw Exception('No frames were extracted from video.');
      }

      // 2. Process frames via dual-stage pipeline
      int currentFrame = 0;
      for (final fileEntity in frameFiles) {
        if (fileEntity is! File) continue;

        final progressValue = currentFrame / totalFrames;
        onProgress(
          progressValue,
          'กำลังวิเคราะห์เฟรม $currentFrame / $totalFrames',
        );

        final bool shouldPredict = sampleEveryNFrames <= 1 ||
            ((currentFrame + 1) % sampleEveryNFrames == 0);

        if (!shouldPredict) {
          if (await fileEntity.exists()) {
            await fileEntity.delete();
          }
          currentFrame++;
          continue;
        }

        try {
          final bytes = await fileEntity.readAsBytes();
          final result = await frameAnalysisService.analyze(bytes);

          if (result.detections.isNotEmpty) {
            for (final detection in result.detections) {
              detectedClasses.add(videoFormalThaiName(detection.className));
            }
          }

          final detectedNumber = countdownStabilizer.add(result.detectedNumber);
          if (detectedNumber != null && detectedNumber.isNotEmpty) {
            detectedNumbers.add(detectedNumber);
          }

          frameResults[currentFrame] = FrameAnalysisResult(
            detections: result.detections,
            detectedNumber: detectedNumber,
          );
        } catch (frameError) {
          debugPrint('Error predicting frame $currentFrame: $frameError');
        } finally {
          currentFrame++;
          if (await fileEntity.exists()) {
            await fileEntity.delete();
          }
        }
      }

      onProgress(1.0, 'วิเคราะห์วิดีโอเรียบร้อย พร้อมเล่นแบบ Real-time');

      return VideoProcessingResult(
        finalVideoPath: videoFile.path,
        frameResults: frameResults,
        detectedClasses: detectedClasses,
        detectedNumbers: detectedNumbers,
        targetFps: targetFps,
      );
    } finally {
      // Clean up temporary input folder
      try {
        if (await inputDir.exists()) {
          await inputDir.delete(recursive: true);
        }
      } catch (cleanupError) {
        debugPrint('Failed to clean up temporary folder: $cleanupError');
      }
    }
  }
}
