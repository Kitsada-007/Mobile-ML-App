import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ultralytics_yolo/yolo.dart';

class VideoProcessingService {
  Future<String?> processVideo({
    required String inputVideoPath,
    required YOLO yolo,
    required Function(double progress, String message) onProgress,
  }) async {
    try {
      final directory = await getTemporaryDirectory();

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final String inputFolder = '${directory.path}/yolo_frames_in_$timestamp';
      final String outputFolder =
          '${directory.path}/yolo_frames_out_$timestamp';
      final String finalVideoPath =
          '${directory.path}/result_video_$timestamp.mp4';

      final inputDir = Directory(inputFolder);
      final outputDir = Directory(outputFolder);

      if (await inputDir.exists()) {
        await inputDir.delete(recursive: true);
      }
      if (await outputDir.exists()) {
        await outputDir.delete(recursive: true);
      }

      await inputDir.create(recursive: true);
      await outputDir.create(recursive: true);

      onProgress(0.0, 'กำลังเตรียมไฟล์วิดีโอ...');

      String originalFps = '30';

      final infoSession = await FFprobeKit.getMediaInformation(inputVideoPath);
      final info = infoSession.getMediaInformation();

      if (info != null) {
        final streams = info.getStreams();
        if (streams != null) {
          for (final stream in streams) {
            if (stream.getType() == 'video') {
              originalFps = stream.getRealFrameRate() ?? '30';
              break;
            }
          }
        }
      }

      onProgress(0.02, 'กำลังสกัดเฟรมจากวิดีโอ...');

      final extractCmd =
          '-i "${inputVideoPath.replaceAll('"', '\\"')}" '
          '-vf "scale=640:-1" '
          '-q:v 5 '
          '-y "$inputFolder/frame_%05d.jpg"';

      final extractSession = await FFmpegKit.execute(extractCmd);
      final extractReturnCode = await extractSession.getReturnCode();

      if (!ReturnCode.isSuccess(extractReturnCode)) {
        debugPrint('Extract frames failed');
        return null;
      }

      final List<FileSystemEntity> frameFiles = await inputDir.list().toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      final imageFrames = frameFiles.whereType<File>().toList();

      if (imageFrames.isEmpty) {
        debugPrint('No frames extracted');
        return null;
      }

      final int totalFrames = imageFrames.length;

      for (int i = 0; i < totalFrames; i++) {
        final file = imageFrames[i];

        final progress = (i + 1) / totalFrames;
        onProgress(progress, 'กำลังประมวลผล ${i + 1} / $totalFrames เฟรม');

        try {
          final bytes = await file.readAsBytes();
          final result = await yolo.predict(bytes);
          final Uint8List? annotatedBytes =
              result['annotatedImage'] as Uint8List?;

          final String fileName = file.uri.pathSegments.last;
          final File outFile = File('$outputFolder/$fileName');

          if (annotatedBytes != null && annotatedBytes.isNotEmpty) {
            await outFile.writeAsBytes(annotatedBytes);
          } else {
            // ถ้า YOLO ไม่คืนภาพ annotate ให้ใช้เฟรมเดิมแทน
            await outFile.writeAsBytes(bytes);
          }
        } catch (e) {
          debugPrint('Frame processing error at ${file.path}: $e');

          // ถ้าเฟรมนี้พัง ให้ copy เฟรมเดิมไปแทน
          final bytes = await file.readAsBytes();
          final String fileName = file.uri.pathSegments.last;
          final File outFile = File('$outputFolder/$fileName');
          await outFile.writeAsBytes(bytes);
        }
      }

      onProgress(0.95, 'กำลังรวมวิดีโอกลับพร้อมเสียง...');

      final stitchCmd =
          '-framerate $originalFps '
          '-i "$outputFolder/frame_%05d.jpg" '
          '-i "${inputVideoPath.replaceAll('"', '\\"')}" '
          '-c:v libx264 '
          '-pix_fmt yuv420p '
          '-c:a copy '
          '-map 0:v:0 '
          '-map 1:a:0? '
          '-y "$finalVideoPath"';

      final stitchSession = await FFmpegKit.execute(stitchCmd);
      final stitchReturnCode = await stitchSession.getReturnCode();

      if (ReturnCode.isSuccess(stitchReturnCode)) {
        onProgress(1.0, 'ประมวลผลเสร็จสมบูรณ์');
        return finalVideoPath;
      } else {
        debugPrint('Stitch video failed');
        return null;
      }
    } catch (e) {
      debugPrint('VideoProcessingService Error: $e');
      return null;
    }
  }
}
