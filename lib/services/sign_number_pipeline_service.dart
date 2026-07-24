import 'dart:math';
import 'package:flutter/foundation.dart'; // สำหรับ compute
import 'package:image/image.dart' as img;
import 'package:trffic_ilght_app/services/yolo_result_adapter.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

const double digitConfidenceThreshold = 0.15;
const double digitIouThreshold = 0.80;

class CropData {
  final Uint8List imageBytes;
  final double left;
  final double top;
  final double right;
  final double bottom;

  CropData(this.imageBytes, this.left, this.top, this.right, this.bottom);
}

typedef CropBounds = ({int left, int top, int right, int bottom});

CropBounds resolveCropBounds(
  CropData data, {
  required int imageWidth,
  required int imageHeight,
}) {
  double x1 = data.left;
  double y1 = data.top;
  double x2 = data.right;
  double y2 = data.bottom;

  if (x2 <= 1.0 && y2 <= 1.0) {
    x1 *= imageWidth;
    y1 *= imageHeight;
    x2 *= imageWidth;
    y2 *= imageHeight;
  }

  final width = x2 - x1;
  final height = y2 - y1;
  final paddingW = width * 0.30;
  final paddingH = height * 0.15;

  return (
    left: max(0, (x1 - paddingW).round()),
    top: max(0, (y1 - paddingH).round()),
    right: min(imageWidth, (x2 + paddingW).round()),
    bottom: min(imageHeight, (y2 + paddingH).round()),
  );
}

@visibleForTesting
Uint8List? processSignCrop(CropData data) {
  try {
    final original = img.decodeImage(data.imageBytes);
    if (original == null) return null;

    final imgW = original.width;
    final imgH = original.height;

    final bounds = resolveCropBounds(data, imageWidth: imgW, imageHeight: imgH);

    final int cropWidth = bounds.right - bounds.left;
    final int cropHeight = bounds.bottom - bounds.top;

    if (cropWidth <= 0 || cropHeight <= 0) return null;

    // ตัดภาพ (Crop)
    img.Image cropped = img.copyCrop(
      original,
      x: bounds.left,
      y: bounds.top,
      width: cropWidth,
      height: cropHeight,
    );

    // ขยายภาพโดยรักษาสัดส่วน เพื่อไม่บีบเลขหลายหลักให้เสียรูป
    final shortestEdge = min(cropped.width, cropped.height);
    final longestEdge = max(cropped.width, cropped.height);
    var scale = max(2.0, 128 / shortestEdge);
    scale = min(scale, 640 / longestEdge);

    cropped = img.copyResize(
      cropped,
      width: max(1, (cropped.width * scale).round()),
      height: max(1, (cropped.height * scale).round()),
      interpolation: img.Interpolation.linear,
    );

    // ปรับความต่างสีโดยเก็บข้อมูลสีเดิมไว้ให้โมเดลใช้
    cropped = img.adjustColor(cropped, contrast: 1.5);

    return Uint8List.fromList(img.encodeJpg(cropped, quality: 85));
  } catch (e) {
    debugPrint('Isolate Crop Error: $e');
    return null;
  }
}

class SignNumberPipelineService {
  final YOLO digitYolo;

  SignNumberPipelineService({required this.digitYolo});

  Future<String?> detectNumberFromSign({
    required Uint8List frameBytes,
    required List<YOLOResult> detectionResults,
  }) async {
    final signResults = detectionResults
        .where((r) => r.className == 'sign_number')
        .toList();

    if (signResults.isEmpty) return null;

    signResults.sort((a, b) => b.confidence.compareTo(a.confidence));
    final sign = signResults.first;

    final normalizedRect = sign.normalizedBox;
    final rect = normalizedRect.width > 0 && normalizedRect.height > 0
        ? normalizedRect
        : sign.boundingBox;
    final cropData = CropData(
      frameBytes,
      rect.left,
      rect.top,
      rect.right,
      rect.bottom,
    );

    final processedBytes = await compute(processSignCrop, cropData);
    if (processedBytes == null) return null;

    final result = await digitYolo.predict(
      processedBytes,
      confidenceThreshold: digitConfidenceThreshold,
      iouThreshold: digitIouThreshold,
    );

    final detections = parseYoloDetections(result['detections']);
    return readDigitSequence(detections, maxDigits: 2);
  }
}
