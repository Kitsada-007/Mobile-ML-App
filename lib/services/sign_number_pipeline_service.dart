import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // สำหรับ compute
import 'package:image/image.dart' as img;
import 'package:ultralytics_yolo/models/yolo_result.dart';
import 'package:ultralytics_yolo/yolo.dart';

class CropData {
  final Uint8List imageBytes;
  final double left;
  final double top;
  final double right;
  final double bottom;

  CropData(this.imageBytes, this.left, this.top, this.right, this.bottom);
}

Uint8List? _isolateCropAndProcess(CropData data) {
  try {
    final original = img.decodeImage(data.imageBytes);
    if (original == null) return null;

    final imgW = original.width;
    final imgH = original.height;

    // หาจุดตัด ขยายกรอบ (Padding) ออกมานิดหน่อยเพื่อให้เห็นตัวเลขชัดๆ
    double x1 = data.left;
    double y1 = data.top;
    double x2 = data.right;
    double y2 = data.bottom;

    // รองรับ Normalized Box
    if (x2 <= 1.0 && y2 <= 1.0) {
      x1 *= imgW;
      y1 *= imgH;
      x2 *= imgW;
      y2 *= imgH;
    }

    final double width = x2 - x1;
    final double height = y2 - y1;

    if (width <= 0 || height <= 0) return null;

    // เผื่อขอบ (Padding) 15%
    final double paddingW = width * 0.15;
    final double paddingH = height * 0.15;

    final int cropLeft = max(0, (x1 - paddingW).round());
    final int cropTop = max(0, (y1 - paddingH).round());
    final int cropRight = min(imgW, (x2 + paddingW).round());
    final int cropBottom = min(imgH, (y2 + paddingH).round());

    final int cropWidth = cropRight - cropLeft;
    final int cropHeight = cropBottom - cropTop;

    if (cropWidth <= 0 || cropHeight <= 0) return null;

    // ตัดภาพ (Crop)
    img.Image cropped = img.copyCrop(
      original,
      x: cropLeft,
      y: cropTop,
      width: cropWidth,
      height: cropHeight,
    );

    // ขยายภาพ (Upscale) ให้โมเดลตัวเลขอ่านง่ายขึ้น
    cropped = img.copyResize(
      cropped,
      width: max(cropped.width * 2, 128),
      height: max(cropped.height * 2, 128),
      interpolation: img.Interpolation.cubic,
    );

    // 🎯 แปลงเป็นขาวดำ (Grayscale)
    cropped = img.grayscale(cropped);

    // 🎯 ปรับความต่างสี (Contrast) ให้ตัวเลขตัดกับพื้นหลังชัดเจน
    cropped = img.adjustColor(cropped, contrast: 1.5);

    return Uint8List.fromList(img.encodeJpg(cropped, quality: 100));
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

    final rect = sign.boundingBox;
    final cropData = CropData(
      frameBytes,
      rect.left,
      rect.top,
      rect.right,
      rect.bottom,
    );

    final processedBytes = await compute(_isolateCropAndProcess, cropData);
    if (processedBytes == null) return null;

    final result = await digitYolo.predict(processedBytes);

    final rawBoxes = result['boxes'];
    if (rawBoxes is! List || rawBoxes.isEmpty) return null;

    final digitBoxes = rawBoxes
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    if (digitBoxes.isEmpty) return null;

    digitBoxes.sort((a, b) {
      final ax = _readLeftX(a);
      final bx = _readLeftX(b);
      return ax.compareTo(bx);
    });
    String number = digitBoxes
        .map((e) => (e['className'] ?? e['class'] ?? '').toString().trim())
        .join();

    if (number.length > 2) {
      number = number.substring(0, 2);
    }

    return number.isEmpty ? null : number;
  }

  double _readLeftX(Map<String, dynamic> box) {
    for (final key in ['x1', 'left', 'xmin']) {
      final value = box[key];
      if (value is num) return value.toDouble();
    }
    return 0.0;
  }
}
