import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';

/// ผลลัพธ์การตรวจสอบไฟล์วิดีโอ
/// - valid: ไฟล์ผ่านการตรวจสอบ
/// - invalid: ไฟล์ไม่ผ่าน พร้อมข้อความ errorMessage ที่อธิบายสาเหตุ
class VideoValidationResult {
  const VideoValidationResult.valid() : errorMessage = null;
  const VideoValidationResult.invalid(this.errorMessage);

  final String? errorMessage;
  bool get isValid => errorMessage == null;
}

/// ตัวตรวจสอบความถูกต้องของไฟล์วิดีโอที่อัปโหลด
/// ตรวจสอบ 2 อย่าง:
/// 1. ขนาดไฟล์ไม่เกิน maxSizeBytes (ค่าเริ่มต้น 100 MB)
/// 2. ไฟล์อ่านได้และเป็นวิดีโอที่ถูกต้อง (ใช้ ffprobe)
class VideoInputValidator {
  const VideoInputValidator({this.maxSizeBytes = 100 * 1024 * 1024});

  /// ขนาดไฟล์สูงสุดที่อนุญาต (หน่วยเป็น byte) ค่าเริ่มต้น 100 MB
  final int maxSizeBytes;

  /// ตรวจสอบไฟล์วิดีโอ
  /// คืนค่า VideoValidationResult ที่บ่งชี้ว่าไฟล์ถูกต้องหรือไม่
  Future<VideoValidationResult> validate(File videoFile) async {
    // ตรวจสอบขนาดไฟล์
    final sizeInBytes = await videoFile.length();
    if (sizeInBytes > maxSizeBytes) {
      final sizeInMb = sizeInBytes / (1024 * 1024);
      return VideoValidationResult.invalid(
        'ไฟล์วิดีโอใหญ่เกินไป (${sizeInMb.toStringAsFixed(1)} MB) กรุณาเลือกไฟล์ไม่เกิน 100 MB',
      );
    }

    // ตรวจสอบว่าไฟล์อ่านได้และเป็นวิดีโอที่ถูกต้องด้วย ffprobe
    final infoSession = await FFprobeKit.getMediaInformation(videoFile.path);
    if (infoSession.getMediaInformation() == null) {
      return const VideoValidationResult.invalid(
        'ไม่สามารถอ่านข้อมูลวิดีโอนี้ได้',
      );
    }
    return const VideoValidationResult.valid();
  }
}
