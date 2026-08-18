import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:trffic_ilght_app/core/services/inference/sign_crop_geometry.dart';

class RealtimeFrameTaskData {
  final Uint8List frameBytes;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final int? expectedFrameWidth;
  final int? expectedFrameHeight;
  final int? rotationDegrees;
  final bool runAlternative;

  RealtimeFrameTaskData({
    required this.frameBytes,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.expectedFrameWidth,
    this.expectedFrameHeight,
    this.rotationDegrees,
    this.runAlternative = false,
  });
}

/// ผลลัพธ์การ crop เฟรม Realtime (ทั้งแบบแน่นและแบบกว้าง) — ส่งกลับมา 2 ชุด
class RealtimeFrameTaskResult {
  final Uint8List? tightCropBytes;
  final Uint8List? wideCropBytes;

  RealtimeFrameTaskResult({this.tightCropBytes, this.wideCropBytes});
}

/// ประมวลผล 1 เฟรมใน isolate: หมุนภาพ + crop 2 รูปแบบ (แน่น/กว้าง)
/// - คำนวณมุมหมุนจาก rotationDegrees หรือย้อนจากขนาดภาพที่คาดหวัง
/// - ครอบพิกัดให้อยู่ในภาพแล้วสร้าง crop ทั้งแบบ tight (padding น้อย) และ wide (padding มาก)
RealtimeFrameTaskResult processRealtimeFrameTask(RealtimeFrameTaskData data) {
  final decoded = img.decodeImage(data.frameBytes);
  if (decoded == null) return RealtimeFrameTaskResult();

  img.Image original = img.bakeOrientation(decoded);

  int degrees = 0;
  if (data.rotationDegrees != null) {
    degrees = ((data.rotationDegrees! % 360) + 360) % 360;
  } else if (data.expectedFrameWidth != null &&
      data.expectedFrameHeight != null) {
    final dimensionsAreReversed =
        original.width == data.expectedFrameHeight &&
        original.height == data.expectedFrameWidth;
    if (data.runAlternative) {
      if (dimensionsAreReversed) {
        degrees = 270;
      } else {
        degrees = 180;
      }
    } else {
      if (dimensionsAreReversed) {
        degrees = 90;
      } else {
        degrees = 0;
      }
    }
  }

  if (degrees != 0) {
    original = img.copyRotate(original, angle: degrees);
  }

  final int imageWidth = original.width;
  final int imageHeight = original.height;

  double x1 = data.left;
  double y1 = data.top;
  double x2 = data.right;
  double y2 = data.bottom;

  final bool isNormalized =
      x1 >= -0.01 && y1 >= -0.01 && x2 <= 1.01 && y2 <= 1.01;

  if (isNormalized) {
    x1 *= imageWidth;
    y1 *= imageHeight;
    x2 *= imageWidth;
    y2 *= imageHeight;
  }

  final int left = x1.floor().clamp(0, imageWidth - 1);
  final int top = y1.floor().clamp(0, imageHeight - 1);
  final int right = x2.ceil().clamp(left + 1, imageWidth);
  final int bottom = y2.ceil().clamp(top + 1, imageHeight);

  final bounds = (left: left, top: top, right: right, bottom: bottom);
  final int cropWidth = bounds.right - bounds.left;
  final int cropHeight = bounds.bottom - bounds.top;

  if (cropWidth <= 0 || cropHeight <= 0) {
    return RealtimeFrameTaskResult();
  }

  Uint8List? cropAndEncode(double hPadding, double vPadding) {
    final padded = expandCropBounds(
      bounds,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      horizontalPaddingFactor: hPadding,
      verticalPaddingFactor: vPadding,
    );

    img.Image cropped = img.copyCrop(
      original,
      x: padded.left,
      y: padded.top,
      width: padded.right - padded.left,
      height: padded.bottom - padded.top,
    );

    // จัดสเกลให้พอดีกับช่วงที่ digit model รองรับ
    final int shortestEdge = min(cropped.width, cropped.height);
    final int longestEdge = max(cropped.width, cropped.height);
    double scale;
    if (shortestEdge < minimumDigitCropEdge) {
      scale = minimumDigitCropEdge / shortestEdge;
    } else {
      scale = 1;
    }

    if (longestEdge * scale > maximumDigitCropEdge) {
      scale = maximumDigitCropEdge / longestEdge;
    }

    if ((scale - 1).abs() > 0.001) {
      cropped = img.copyResize(
        cropped,
        width: max(1, (cropped.width * scale).round()),
        height: max(1, (cropped.height * scale).round()),
        interpolation: img.Interpolation.linear,
      );
    }

    // digit model ฝึกด้วยภาพ grayscale -> แปลงเป็น grayscale แล้วเข้ารหัส JPG
    cropped = img.grayscale(cropped);
    return Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
  }

  final tightBytes = cropAndEncode(
    tightHorizontalPaddingFactor,
    tightVerticalPaddingFactor,
  );
  final wideBytes = cropAndEncode(
    wideHorizontalPaddingFactor,
    wideVerticalPaddingFactor,
  );

  return RealtimeFrameTaskResult(
    tightCropBytes: tightBytes,
    wideCropBytes: wideBytes,
  );
}
