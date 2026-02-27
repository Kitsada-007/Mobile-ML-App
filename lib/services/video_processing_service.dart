import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ultralytics_yolo/yolo.dart';

class VideoProcessingService {
  /// รับไฟล์วิดีโอต้นฉบับ โมเดล YOLO และ Callback สำหรับอัปเดต UI
  /// คืนค่า Path ของวิดีโอผลลัพธ์ (หรือ null ถ้าล้มเหลว)
  Future<String?> processVideo({
    required String inputVideoPath,
    required YOLO yolo,
    required Function(double progress, String message) onProgress,
  }) async {
    try {
      final directory = await getTemporaryDirectory();
      final String inputFolder = '${directory.path}/yolo_frames_in';
      final String outputFolder = '${directory.path}/yolo_frames_out';
      final String finalVideoPath = '${directory.path}/result_video.mp4';

      // 1. เตรียมโฟลเดอร์
      for (String path in [inputFolder, outputFolder]) {
        final dir = Directory(path);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
        dir.createSync(recursive: true);
      }

      onProgress(0.0, "กำลังเตรียมไฟล์วิดีโอ...");

      // 2. หา FPS ต้นฉบับ
      String originalFps = "30";
      final infoSession = await FFprobeKit.getMediaInformation(inputVideoPath);
      final info = infoSession.getMediaInformation();
      if (info != null) {
        for (var stream in info.getStreams()) {
          if (stream.getType() == 'video') {
            originalFps = stream.getRealFrameRate() ?? "30";
            break;
          }
        }
      }

      // 3. สกัดเฟรม
      onProgress(0.0, "กำลังสกัดเฟรมจากวิดีโอ...");
      final String extractCmd =
          "-i $inputVideoPath -vf \"scale=640:-1\" -q:v 5 -y $inputFolder/frame_%05d.jpg";
      await FFmpegKit.execute(extractCmd);

      final dirIn = Directory(inputFolder);
      final List<FileSystemEntity> frameFiles = dirIn.listSync()
        ..sort((a, b) => a.path.compareTo(b.path));

      int totalFrames = frameFiles.length;
      int currentFrame = 0;

      // 4. ส่งเข้า YOLO ทีละเฟรม
      for (var fileEntity in frameFiles) {
        if (fileEntity is File) {
          currentFrame++;

          // ส่งสถานะกลับไปให้ UI อัปเดต
          onProgress(
            currentFrame / totalFrames,
            "กำลังประมวลผล $currentFrame / $totalFrames เฟรม",
          );

          final bytes = await fileEntity.readAsBytes();
          final result = await yolo.predict(bytes);
          final annotatedBytes = result['annotatedImage'] as Uint8List?;

          if (annotatedBytes != null) {
            final String fileName = fileEntity.uri.pathSegments.last;
            final File outFile = File('$outputFolder/$fileName');
            await outFile.writeAsBytes(annotatedBytes);
          }
          await fileEntity.delete();
        }
      }

      // 5. รวมไฟล์เป็น MP4
      onProgress(0.0, "กำลังรวมไฟล์วิดีโอกลับคืน พร้อมใส่เสียง...");
      final String stitchCmd =
          "-framerate $originalFps -i $outputFolder/frame_%05d.jpg -i $inputVideoPath -c:v libx264 -pix_fmt yuv420p -c:a copy -map 0:v:0 -map 1:a:0? -y $finalVideoPath";

      final stitchSession = await FFmpegKit.execute(stitchCmd);
      final returnCode = await stitchSession.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        return finalVideoPath; // ประมวลผลสำเร็จ คืนค่า Path กลับไป
      } else {
        return null; // ล้มเหลว
      }
    } catch (e) {
      debugPrint("VideoProcessingService Error: $e");
      return null;
    }
  }
}
