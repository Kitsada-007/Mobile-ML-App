import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';

class VideoValidationResult {
  const VideoValidationResult.valid() : errorMessage = null;
  const VideoValidationResult.invalid(this.errorMessage);

  final String? errorMessage;
  bool get isValid => errorMessage == null;
}

class VideoInputValidator {
  const VideoInputValidator({this.maxSizeBytes = 50 * 1024 * 1024});

  final int maxSizeBytes;

  Future<VideoValidationResult> validate(File videoFile) async {
    final sizeInBytes = await videoFile.length();
    if (sizeInBytes > maxSizeBytes) {
      final sizeInMb = sizeInBytes / (1024 * 1024);
      return VideoValidationResult.invalid(
        'ไฟล์วิดีโอใหญ่เกินไป (${sizeInMb.toStringAsFixed(1)} MB) กรุณาเลือกไฟล์ไม่เกิน 50 MB',
      );
    }

    final infoSession = await FFprobeKit.getMediaInformation(videoFile.path);
    if (infoSession.getMediaInformation() == null) {
      return const VideoValidationResult.invalid('ไม่สามารถอ่านข้อมูลวิดีโอนี้ได้');
    }
    return const VideoValidationResult.valid();
  }
}
