import 'dart:developer';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:trffic_ilght_app/core/services/inference/countdown_reading_stabilizer.dart';
import 'package:trffic_ilght_app/features/video_detection/data/services/video_frame_analysis_service.dart';
import 'package:trffic_ilght_app/features/video_detection/data/services/video_label_formatter.dart';
import 'package:ultralytics_yolo/yolo.dart';

// หมายเหตุ: ไฟล์นี้ "ไม่" ประกาศ SignalInterpreter / DriverSignalResult /
// SignalAction / TrafficSignalClasses ซ้ำ เพราะมีอยู่แล้วที่
// core/services/inference/signal_interpreter.dart และ
// VideoInferenceController เป็นผู้เรียกใช้ตีความแบบ real-time ต่อเฟรมเอง
// (ผ่าน TrafficVoiceService ที่มีทั้ง formal name และ alert message)
// service ชั้นนี้มีหน้าที่แค่ extract + predict + stabilize เลขนับถอยหลัง
// แล้วส่ง raw detections กลับไปให้ controller ตีความเท่านั้
// =============================================================================
// DATA MODELS
// =============================================================================

/// Single frame analysis result — เก็บแค่ raw data จาก inference
/// ไม่ตีความ business logic ในชั้นนี้ (ให้ controller ทำ เพื่อไม่ให้ซ้ำซ้อน)
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

// =============================================================================
// VIDEO PROCESSING SERVICE
// =============================================================================

/// Service for video detection pipeline:
/// Extracts frames at the target detection rate -> Analyzes dual-stage YOLO
/// per frame -> Interprets multi-class detections into a single driver-facing
/// message -> Builds realtime frame overlay map.
class VideoProcessingService {
  Future<VideoProcessingResult> processVideo({
    required File videoFile,
    required VideoFrameAnalysisService frameAnalysisService,
    required CountdownReadingStabilizer countdownStabilizer,
    required void Function(double progressValue, String progressText)
    onProgress,
    bool Function()? isCancelled,
    // targetFps คือจำนวนครั้งที่ต้องการตรวจจับต่อวินาทีจริง ๆ
    // (ไม่ใช่ fps ของวิดีโอต้นฉบับ) — ffmpeg extract ที่ค่านี้ตรง ๆ เลย
    // ไม่มีชั้น sampling ซ้อนอีกชั้นเหมือนเวอร์ชันก่อนหน้า
    int targetFps = 4,
    // จำนวนเฟรม (ที่ extract มาแล้ว) ที่ยอมให้ "hold" ค่าเลขล่าสุดไว้
    // เผื่อกรณี motion blur ทำให้บางเฟรม predict เลขไม่ได้
    int maxHoldFrames = 3,
  }) async {
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final String inputFolder = '${directory.path}/yolo_frames_in_$timestamp';
    log(directory.toString());
    final detectedClasses = <String>{};
    final detectedNumbers = <String>{};

    final frameResults = <int, FrameAnalysisResult>{};

    final inputDir = Directory(inputFolder);
    if (await inputDir.exists()) {
      await inputDir.delete(recursive: true);
    }
    await inputDir.create(recursive: true);

    try {
      // 1. Extract frames from video using FFmpeg at the exact target rate.
      //    ไม่ extract ถี่กว่านี้แล้วมา skip ทีหลัง เพราะเปลืองเวลา/พื้นที่โดยไม่จำเป็น
      onProgress(0.0, 'กำลังสกัดเฟรมจากวิดีโอ ($targetFps ครั้ง/วินาที)...');

      final String extractCmd =
          '-threads 0 '
          '-i "${videoFile.path}" '
          '-vf "fps=$targetFps,scale=640:-1:flags=fast_bilinear" '
          '-q:v 5 '
          '-y "$inputFolder/frame_%05d.jpg"';

      final extractSession = await FFmpegKit.execute(extractCmd);
      final extractReturnCode = await extractSession.getReturnCode();

      if (isCancelled?.call() == true) {
        debugPrint('Video processing cancelled during frame extraction.');
        throw Exception('Video processing cancelled.');
      }

      if (!ReturnCode.isSuccess(extractReturnCode)) {
        throw Exception('Failed to extract frames from video.');
      }

      final List<FileSystemEntity> frameFiles = inputDir.listSync()
        ..sort((a, b) => a.path.compareTo(b.path));

      final int totalFrames = frameFiles.length;
      if (totalFrames == 0) {
        throw Exception('No frames were extracted from video.');
      }

      // คำนวณ hold duration แบบ dynamic จาก targetFps จริง แทนการ hardcode
      // เพราะตอนนี้ไม่มีชั้น sampleInterval ซ้อนแล้ว 1 เฟรมที่ extract มา
      // = 1 เฟรมที่ predict เสมอ (targetFps ตรงกับอัตราตรวจจับจริง)
      final double holdDurationSeconds = maxHoldFrames / targetFps;
      debugPrint(
        'Countdown hold duration: ${holdDurationSeconds.toStringAsFixed(2)}s '
        '($maxHoldFrames frames @ $targetFps fps)',
      );

      // 2. Process every extracted frame through the dual-stage pipeline
      //    with realtime stabilization & decay hold for the countdown number.
      String? lastAcceptedNumber;
      int holdFrameCount = 0;

      int currentFrame = 0;
      for (final fileEntity in frameFiles) {
        if (isCancelled?.call() == true) {
          debugPrint('Video processing cancelled at frame $currentFrame.');
          break;
        }
        if (fileEntity is! File) continue;

        final displayFrame = currentFrame + 1;
        onProgress(
          displayFrame / totalFrames,
          'กำลังวิเคราะห์วิดีโอ...',
        );

        try {
          final bytes = await fileEntity.readAsBytes();
          final result = await frameAnalysisService.analyze(bytes);

          // เก็บชื่อ class แบบ formal Thai name ไว้เป็น aggregate log ของทั้งวิดีโอ
          // (ไม่ใช่สิ่งที่ใช้แสดงผลหลักให้ user เห็น — การแสดงผลหลักต่อเฟรม
          //  เป็นหน้าที่ของ SignalInterpreter ที่ VideoInferenceController เรียกเอง)
          for (final detection in result.detections) {
            detectedClasses.add(videoFormalThaiName(detection.className));
          }

          // ---- Countdown number: stabilize + hold/decay ----
          final stabilizedNumber = countdownStabilizer.add(
            result.detectedNumber,
          );
          String? finalNumber;

          if (stabilizedNumber != null && stabilizedNumber.isNotEmpty) {
            lastAcceptedNumber = stabilizedNumber;
            holdFrameCount = maxHoldFrames;
            finalNumber = stabilizedNumber;
            log(stabilizedNumber.toString());
            detectedNumbers.add(stabilizedNumber);
          } else if (holdFrameCount > 0 && lastAcceptedNumber != null) {
            holdFrameCount--;
            finalNumber = lastAcceptedNumber;
          } else {
            lastAcceptedNumber = null;
            holdFrameCount = 0;
            finalNumber = null;
          }

          // ไม่ตีความเป็นข้อความเดียวที่นี่ — ส่ง raw detections + finalNumber
          // กลับไปให้ VideoInferenceController ตีความผ่าน SignalInterpreter
          // แบบ real-time ตอนเล่นวิดีโอแทน (single source of truth)
          frameResults[currentFrame] = FrameAnalysisResult(
            detections: result.detections,
            detectedNumber: finalNumber,
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
