import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

// ---- ขนาด/ปัจจัยการ crop ป้ายตัวเลขนับถอยหลัง ----
const int minimumDigitCropEdge =
    128; // ขอบสั้นขั้นต่ำของภาพที่ส่งเข้า digit model
const int maximumDigitCropEdge =
    640; // ขอบยาวสูงสุดของภาพที่ส่งเข้า digit model
const double tightHorizontalPaddingFactor =
    0.15; // padding แนวนอนแบบแน่น (crop ตามกล่อง)
const double tightVerticalPaddingFactor = 0.10; // padding แนวตั้งแบบแน่น
const double wideHorizontalPaddingFactor =
    0.30; // padding แนวนอนแบบกว้าง (เผื่อตัวเลขล้นกล่อง)
const double wideVerticalPaddingFactor = 0.15; // padding แนวตั้งแบบกว้าง

/// พิมพ์ log ดีบักเฉพาะในโหมด debug
void _debugPipeline(String message) {
  if (kDebugMode) debugPrint(message);
}

/// ข้อมูลการ crop หนึ่งชุด: ภาพ + พิกัดกล่อง (normalized หรือ pixel) + ปัจจัย padding
class CropData {
  final Uint8List imageBytes;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double horizontalPaddingFactor;
  final double verticalPaddingFactor;

  CropData(
    this.imageBytes,
    this.left,
    this.top,
    this.right,
    this.bottom, {
    this.horizontalPaddingFactor = tightHorizontalPaddingFactor,
    this.verticalPaddingFactor = tightVerticalPaddingFactor,
  });
}

/// พิกัด crop ที่เป็นจำนวนเต็ม (pixel) ภายในภาพ
typedef CropBounds = ({int left, int top, int right, int bottom});

/// YOLOView 0.6.10 reports boxes in the upright frame coordinate space but
/// streams the camera bitmap before CameraX rotation. Normalize the bitmap
/// before applying those boxes.
/// (YOLOView 0.6.10 รายงานพิกัดกล่องในระบบพิกัดเฟรมที่ตั้งตรง แต่สตรีม bitmap
/// ของกล้องก่อนหมุนตาม CameraX -> ต้องปรับภาพให้ตรงกับพิกัดก่อนใช้กล่อง)
@visibleForTesting
Uint8List orientFrameForDetectionCoordinates(
  Uint8List frameBytes, {
  int? expectedWidth,
  int? expectedHeight,
  int? rotationDegrees,
}) {
  final decoded = img.decodeImage(frameBytes);
  if (decoded == null) return frameBytes;

  img.Image oriented = img.bakeOrientation(decoded);
  final normalizedRotation = rotationDegrees == null
      ? null
      : ((rotationDegrees % 360) + 360) % 360;
  final dimensionsAreReversed =
      expectedWidth != null &&
      expectedHeight != null &&
      oriented.width == expectedHeight &&
      oriented.height == expectedWidth;

  final degrees = normalizedRotation ?? (dimensionsAreReversed ? 90 : 0);
  if (degrees == 0) return frameBytes;

  oriented = img.copyRotate(oriented, angle: degrees);
  return Uint8List.fromList(img.encodeJpg(oriented, quality: 95));
}

/// แปลงพิกัดกล่อง (normalized หรือ pixel) ให้เป็น CropBounds เป็นพิกเซล
/// - ถ้าค่าเป็น normalized (0..1) จะคูณขนาดภาพก่อน
/// - ครอบค่าอยู่ในขอบภาพเสมอ
CropBounds resolveCropBounds(
  CropData data, {
  required int imageWidth,
  required int imageHeight,
}) {
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

  return (left: left, top: top, right: right, bottom: bottom);
}

/// ขยายกล่อง crop ออกไปตาม factor (เพื่อรวมตัวเลขที่ล้นขอบกล่องเล็กน้อย)
/// (ใช้ข้าม library โดย sign_crop_task.dart จึงไม่ใช่ @visibleForTesting แล้ว)
CropBounds expandCropBounds(
  CropBounds bounds, {
  required int imageWidth,
  required int imageHeight,
  required double horizontalPaddingFactor,
  required double verticalPaddingFactor,
}) {
  final int cropWidth = bounds.right - bounds.left;
  final int cropHeight = bounds.bottom - bounds.top;
  final int paddingX = max(2, (cropWidth * horizontalPaddingFactor).round());
  final int paddingY = max(2, (cropHeight * verticalPaddingFactor).round());

  return (
    left: max(0, bounds.left - paddingX),
    top: max(0, bounds.top - paddingY),
    right: min(imageWidth, bounds.right + paddingX),
    bottom: min(imageHeight, bounds.bottom + paddingY),
  );
}

/// ประมวลผลภาพ crop ของป้ายตัวเลขเป็นภาพ grayscale ขนาดที่เหมาะกับ digit model
/// - crop ทีละขั้นตอนแล้ว จัดสเกลให้อยู่ในช่วง [minimumDigitCropEdge, maximumDigitCropEdge]
/// - เปลี่ยนเป็น grayscale (digit model ฝึกมาจากภาพ grayscale) แต่คง 3 ช่องสีไว้
/// - รันได้ทั้งใน isolate/background isolate (เหมาะกับ compute)
/// (ใช้ข้าม library โดย SignNumberPipelineService จึงไม่ใช่ @visibleForTesting แล้ว)
Uint8List? processSignCrop(CropData data) {
  try {
    final decoded = img.decodeImage(data.imageBytes);
    if (decoded == null) return null;

    final original = img.bakeOrientation(decoded);

    final int imageWidth = original.width;
    final int imageHeight = original.height;

    final bounds = resolveCropBounds(
      data,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );

    final int cropWidth = bounds.right - bounds.left;
    final int cropHeight = bounds.bottom - bounds.top;

    if (cropWidth <= 0 || cropHeight <= 0) {
      _debugPipeline('Crop ไม่ถูกต้อง');
      return null;
    }

    final paddedBounds = expandCropBounds(
      bounds,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      horizontalPaddingFactor: data.horizontalPaddingFactor,
      verticalPaddingFactor: data.verticalPaddingFactor,
    );

    img.Image cropped = img.copyCrop(
      original,
      x: paddedBounds.left,
      y: paddedBounds.top,
      width: paddedBounds.right - paddedBounds.left,
      height: paddedBounds.bottom - paddedBounds.top,
    );

    final int shortestEdge = min(cropped.width, cropped.height);
    final int longestEdge = max(cropped.width, cropped.height);
    double scale = shortestEdge < minimumDigitCropEdge
        ? minimumDigitCropEdge / shortestEdge
        : 1;

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

    // Number model was trained with grayscale images. Keep three output
    // channels so the encoded image remains compatible with YOLO input.
    cropped = img.grayscale(cropped);

    _debugPipeline('Crop พร้อมตรวจเลข: ${cropped.width}x${cropped.height}');

    return Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
  } catch (e, stackTrace) {
    _debugPipeline('Isolate Crop Error: $e');
    _debugPipeline('$stackTrace');
    return null;
  }
}
