import 'dart:developer';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:trffic_ilght_app/core/services/inference/countdown_reading_stabilizer.dart';
import 'package:trffic_ilght_app/features/video_detection/data/services/video_frame_analysis_service.dart';
import 'package:ultralytics_yolo/yolo.dart';

// หมายเหตุ: ไฟล์นี้ "ไม่" ประกาศ SignalInterpreter / DriverSignalResult /
// SignalAction / TrafficSignalClasses ซ้ำ เพราะมีอยู่แล้วที่
// core/services/inference/signal_interpreter.dart และ
// VideoInferenceController เป็นผู้เรียกใช้ตีความแบบ real-time ต่อเฟรมเอง
// (ผ่าน TrafficVoiceService ที่มีทั้ง formal name และ alert message)
// service ชั้นนี้มีหน้าที่แค่ extract + predict + stabilize เลขนับถอยหลัง
// แล้วส่ง raw detections กลับไปให้ controller ตีความเท่านั้น

/// Single frame analysis result — เก็บแค่ raw data จาก inference
/// ไม่ตีความ business logic ในชั้นนี้ (ให้ controller ทำ เพื่อไม่ให้ซ้ำซ้อน)
class FrameAnalysisResult {
  const FrameAnalysisResult({
    required this.detections,
    this.detectedNumber,
    this.signPresent = false,
  });

  final List<YOLOResult> detections;
  final String? detectedNumber;

  /// true เมื่อเฟรมนี้ "ถือว่ามีป้ายนับถอยหลัง" — ครอบคลุมทั้งเฟรมที่ตรวจเจอ
  /// กล่อง sign_number จริง และเฟรมที่อยู่ในช่วง hold เลขล่าสุด (กรณีป้าย LED
  /// กะพริบ/PWM ทำให้บางเฟรมตรวจไม่เจอกล่อง) — controller ต้องใช้ค่านี้เป็น
  /// single source of truth ห้ามนับ raw detection ซ้ำเอง ไม่งั้นเลขที่ hold ไว้
  /// จะถูกทิ้งทันทีที่ป้ายหายไป 1 เฟรม
  final bool signPresent;
}

/// Result data from realtime video processing pipeline.
class VideoProcessingResult {
  const VideoProcessingResult({
    required this.finalVideoPath,
    required this.frameResults,
    this.targetFps = 5,
  });

  final String finalVideoPath;
  final Map<int, FrameAnalysisResult> frameResults;
  final int targetFps;
}

/// ผลการตัดสินเลขนับถอยหลังของเฟรมเดียวจาก [CountdownHoldTracker]
typedef CountdownHoldFrame = ({String? finalNumber, bool signPresent});

/// ตัวติดตามการ hold เลขนับถอยหลังข้ามเฟรม — แยกออกมาจาก loop ประมวลผล
/// เพื่อให้เทสต์พฤติกรรม hold ได้โดยไม่ต้องพึ่ง FFmpeg/ไฟล์จริง
/// กติกา: เฟรมที่ stabilizer ยอมรับเลขใหม่จะเติม hold ให้เต็ม [maxHoldFrames]
/// เฟรมถัดไปที่อ่านเลขไม่ได้จะกินโควตา hold ทีละเฟรมโดยยังคงเลขเดิมไว้
/// (กัน motion blur / ป้าย LED กะพริบ) — หมดโควตาเมื่อไรจึงล้างเป็น null
class CountdownHoldTracker {
  CountdownHoldTracker({required this.maxHoldFrames});

  final int maxHoldFrames;
  String? _lastAcceptedNumber;
  int _holdFrameCount = 0;

  CountdownHoldFrame process({
    required String? stabilizedNumber,
    required bool hasSignDetection,
  }) {
    String? finalNumber;
    if (stabilizedNumber != null && stabilizedNumber.isNotEmpty) {
      _lastAcceptedNumber = stabilizedNumber;
      _holdFrameCount = maxHoldFrames;
      finalNumber = stabilizedNumber;
    } else if (_holdFrameCount > 0 && _lastAcceptedNumber != null) {
      _holdFrameCount--;
      finalNumber = _lastAcceptedNumber;
    } else {
      _lastAcceptedNumber = null;
      _holdFrameCount = 0;
    }
    // ป้าย "ถือว่ายังอยู่" ทั้งเฟรมที่เจอกล่องจริงและเฟรมที่ยังอยู่ในช่วง hold
    // เพื่อให้ controller ไม่ทิ้งเลขที่ hold ไว้ (ดู FrameAnalysisResult.signPresent)
    return (
      finalNumber: finalNumber,
      signPresent: hasSignDetection || finalNumber != null,
    );
  }
}

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
    // default 6: ค่าเดิม 4 อยู่ที่ขอบ Nyquist สำหรับไฟกะพริบ ~1 Hz
    // ทำให้การตรวจสถานะกะพริบ (flashing_*) พลาดง่ายในวิดีโอบางไฟล์
    int targetFps = 4,
    // จำนวนเฟรม (ที่ extract มาแล้ว) ที่ยอมให้ "hold" ค่าเลขล่าสุดไว้
    // เผื่อกรณี motion blur ทำให้บางเฟรม predict เลขไม่ได้
    // ที่ 6 fps → hold = 3/6 = 0.5s ยังครอบคลุมช่วงดับของป้าย LED PWM
    // (ครึ่งคาบของการกะพริบ ~1 Hz) จึงคงค่า 3 เฟรมไว้ตามเดิม
    int maxHoldFrames = 3,
  }) async {
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final String inputFolder = '${directory.path}/yolo_frames_in_$timestamp';
    log(directory.toString());

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
      final extractStopwatch = Stopwatch()..start();

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
      extractStopwatch.stop();

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
      frameAnalysisService.resetTiming();
      final analysisStopwatch = Stopwatch()..start();
      final holdTracker = CountdownHoldTracker(maxHoldFrames: maxHoldFrames);

      int currentFrame = 0;
      for (final fileEntity in frameFiles) {
        if (isCancelled?.call() == true) {
          debugPrint('Video processing cancelled at frame $currentFrame.');
          break;
        }
        if (fileEntity is! File) continue;

        final displayFrame = currentFrame + 1;
        onProgress(displayFrame / totalFrames, 'กำลังวิเคราะห์วิดีโอ...');

        try {
          final bytes = await fileEntity.readAsBytes();
          final result = await frameAnalysisService.analyze(bytes);

          // เฟรมนี้มีกล่อง sign_number จริงหรือไม่ (ยังไม่รวมช่วง hold)
          final hasSignDetection = result.detections.any(
            (detection) => detection.className == 'sign_number',
          );

          final stabilizedNumber = countdownStabilizer.add(
            result.detectedNumber,
          );
          if (stabilizedNumber != null && stabilizedNumber.isNotEmpty) {
            log(stabilizedNumber.toString());
          }
          final holdFrame = holdTracker.process(
            stabilizedNumber: stabilizedNumber,
            hasSignDetection: hasSignDetection,
          );

          // ไม่ตีความเป็นข้อความเดียวที่นี่ — ส่ง raw detections + finalNumber
          // กลับไปให้ VideoInferenceController ตีความผ่าน SignalInterpreter
          // แบบ real-time ตอนเล่นวิดีโอแทน (single source of truth)
          frameResults[currentFrame] = FrameAnalysisResult(
            detections: result.detections,
            detectedNumber: holdFrame.finalNumber,
            // ช่วง hold (finalNumber ยังไม่หมดอายุ) ต้องนับว่าป้ายยังอยู่ด้วย
            // ไม่งั้น hold logic ไม่มีผลใด ๆ ในเคสป้ายกะพริบ
            signPresent: holdFrame.signPresent,
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

      analysisStopwatch.stop();
      // สรุปเวลาแต่ละขั้นตอน (ใช้เทียบ before/after ตอนวัดประสิทธิภาพ)
      // ไม่พิมพ์ใน release build — แต่พิมพ์ใน profile mode ซึ่งเป็นโหมดที่ควรใช้วัด
      if (!kReleaseMode) {
        debugPrint(
          '[video-perf] extract=${extractStopwatch.elapsedMilliseconds}ms '
          'analysisLoop=${analysisStopwatch.elapsedMilliseconds}ms '
          '(${frameAnalysisService.timingSummary()})',
        );
      }

      onProgress(1.0, 'วิเคราะห์วิดีโอเรียบร้อย พร้อมเล่นแบบ Real-time');

      return VideoProcessingResult(
        finalVideoPath: videoFile.path,
        frameResults: frameResults,
        targetFps: targetFps,
      );
    } finally {
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
