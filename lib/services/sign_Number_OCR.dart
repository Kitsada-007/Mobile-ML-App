import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

// ============================================================================
// Data Classes สำหรับเก็บผลลัพธ์
// ============================================================================

class OcrVariantPreview {
  final String name;
  final Uint8List imageBytes;
  final String rawText;
  final String cleanText;

  OcrVariantPreview({
    required this.name,
    required this.imageBytes,
    required this.rawText,
    required this.cleanText,
  });
}

class OcrResult {
  final String? text;
  final Uint8List? debugImageBytes;
  final String? debugVariantName;
  final List<OcrVariantPreview> variantPreviews;

  OcrResult({
    this.text,
    this.debugImageBytes,
    this.debugVariantName,
    this.variantPreviews = const [],
  });
}

// ============================================================================
// คลาสหลักสำหรับทำ OCR
// ============================================================================

class SignNumberOCR {
  final TextRecognizer _textRecognizer = TextRecognizer();

  Future<OcrResult> extractNumberFromBox({
    required Uint8List originalImageBytes,
    required Rect boundingBox,
  }) async {
    try {
      // 1. เตรียมข้อมูลส่งให้ Isolate ทำงาน (ใช้ Map เพื่อส่งค่า Primitive)
      final isolateData = {
        'imageBytes': originalImageBytes,
        'left': boundingBox.left,
        'top': boundingBox.top,
        'width': boundingBox.width,
        'height': boundingBox.height,
      };

      // 2. 🚀 โยนงานแต่งรูปภาพหนักๆ ไปให้ Background Thread (Isolate)
      // โค้ดส่วนนี้จะไม่ทำให้หน้าจอ UI กระตุกเลย
      final Map<String, Uint8List>? processedVariants = await Isolate.run(
        () => _processImageInIsolate(isolateData),
      );

      if (processedVariants == null || processedVariants.isEmpty) {
        debugPrint('OCR: Isolate failed to process image');
        return OcrResult();
      }

      // 3. นำภาพที่แต่งเสร็จแล้วมาวนลูปส่งให้ ML Kit (ทำงานบน Main Thread ตามปกติ)
      final List<OcrVariantPreview> previews = [];
      String? bestText;
      Uint8List? bestImage;
      String? bestVariant;

      for (final entry in processedVariants.entries) {
        final String variantName = entry.key;
        final Uint8List bytes = entry.value;

        // เรียกใช้ ML Kit พร้อมการันตีว่าไฟล์ขยะถูกลบทิ้งเสมอ
        final String raw = await _runMlKitWithAutoCleanup(bytes);
        final String clean = _cleanDigits(raw);

        previews.add(
          OcrVariantPreview(
            name: variantName,
            imageBytes: bytes,
            rawText: raw,
            cleanText: clean,
          ),
        );

        debugPrint('OCR [$variantName] RAW => $raw | CLEAN => $clean');

        if (bestImage == null) {
          bestImage = bytes;
          bestVariant = variantName;
        }

        // 4. เช็คผลลัพธ์ (Early Exit) ถ้าได้เลขสวยๆ แล้ว ให้หยุดทำอันอื่นเพื่อประหยัด CPU
        if (_isGoodResult(clean) && bestText == null) {
          bestText = clean;
          bestImage = bytes;
          bestVariant = variantName;

          debugPrint(
            '🎯 ได้ผลลัพธ์ที่ต้องการแล้ว หยุดการประมวลผล Variant ที่เหลือ!',
          );
          break;
        }
      }

      return OcrResult(
        text: bestText,
        debugImageBytes: bestImage,
        debugVariantName: bestVariant,
        variantPreviews: previews,
      );
    } catch (e) {
      debugPrint('OCR Error: $e');
      return OcrResult();
    }
  }

  /// ฟังก์ชันรัน ML Kit ที่มีระบบ Auto-Cleanup ป้องกัน Storage Leak
  Future<String> _runMlKitWithAutoCleanup(Uint8List imageBytes) async {
    File? tempFile;
    try {
      final tempDir = await getTemporaryDirectory();
      tempFile = File(
        '${tempDir.path}/ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );

      await tempFile.writeAsBytes(imageBytes, flush: true);

      final inputImage = InputImage.fromFilePath(tempFile.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      return recognizedText.text;
    } catch (e) {
      debugPrint('ML Kit Process Error: $e');
      return '';
    } finally {
      // 🚨 สำคัญมาก: ลบไฟล์ขยะทิ้งเสมอไม่ว่าจะแอปพังหรือสำเร็จ
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (e) {
          debugPrint('Failed to delete temp OCR file: $e');
        }
      }
    }
  }

  String _cleanDigits(String raw) {
    return raw.replaceAll(RegExp(r'[^0-9]'), '');
  }

  bool _isGoodResult(String text) {
    // สมมติว่าป้ายจราจรควรมีแค่เลข 1 ถึง 3 หลัก
    return text.isNotEmpty && text.length <= 3 && text.length >= 1;
  }

  void dispose() {
    _textRecognizer.close();
  }
}

// ============================================================================
// ส่วนประมวลผลใน Isolate (Top-level function)
// ห้ามดึงตัวแปรจากภายนอกเข้าไปเด็ดขาด (ทำงานแยก Thread อิสระ)
// ============================================================================

Future<Map<String, Uint8List>?> _processImageInIsolate(
  Map<String, dynamic> data,
) async {
  try {
    final Uint8List originalImageBytes = data['imageBytes'];
    double left = data['left'];
    double top = data['top'];
    double width = data['width'];
    double height = data['height'];

    // 1. Decode รูปภาพ
    final image = img.decodeImage(originalImageBytes);
    if (image == null) return null;

    final int imgW = image.width;
    final int imgH = image.height;

    if (width <= 0 || height <= 0) return null;

    // รองรับ Normalized Bounding Box
    if (left <= 1.0 && top <= 1.0 && width <= 1.0 && height <= 1.0) {
      left *= imgW;
      top *= imgH;
      width *= imgW;
      height *= imgH;
    }

    // 2. คำนวณและ Crop ภาพพร้อม Padding 20%
    final double paddingW = width * 0.20;
    final double paddingH = height * 0.20;

    final int cropLeft = max(0, (left - paddingW).round());
    final int cropTop = max(0, (top - paddingH).round());
    final int cropRight = min(imgW, (left + width + paddingW).round());
    final int cropBottom = min(imgH, (top + height + paddingH).round());

    final int cropWidth = cropRight - cropLeft;
    final int cropHeight = cropBottom - cropTop;

    if (cropWidth < 8 || cropHeight < 8) return null;

    img.Image baseCrop = img.copyCrop(
      image,
      x: cropLeft,
      y: cropTop,
      width: cropWidth,
      height: cropHeight,
    );

    // 3. Upscaling ขยายภาพให้คมชัดสำหรับการอ่าน (ขยาย 4 เท่า)
    baseCrop = img.copyResize(
      baseCrop,
      width: baseCrop.width * 4,
      height: baseCrop.height * 4,
      interpolation: img.Interpolation.cubic, // เพื่อให้เส้นไม่แตก
    );

    // 4. สร้าง Variants ประสิทธิภาพสูง (เลือกมาเฉพาะที่ได้ผลดีที่สุด 4 แบบเพื่อประหยัดเวลา)
    final Map<String, img.Image> variants = {};

    // Variant 1: Grayscale + ดัน Contrast สูง (มาตรฐาน)
    img.Image v1 = img.grayscale(baseCrop.clone());
    v1 = img.adjustColor(v1, contrast: 2.2);
    variants['v1_gray_contrast'] = v1;

    // Variant 2: Thresholding 120 (แปลงเป็นขาวดำสนิท เหมาะกับภาพมืดๆ)
    img.Image v2 = _applyPixelThreshold(v1.clone(), 120);
    variants['v2_threshold_120'] = v2;

    // Variant 3: Thresholding 150 (เหมาะกับภาพที่สว่าง แสงจ้าสะท้อนป้าย)
    img.Image v3 = _applyPixelThreshold(v1.clone(), 150);
    variants['v3_threshold_150'] = v3;

    // Variant 4: Invert (กลับสี สำหรับป้ายบางชนิดที่พื้นเข้ม ตัวหนังสือสว่าง)
    img.Image v4 = img.invert(v1.clone());
    variants['v4_inverted'] = v4;

    // 5. Encode ภาพทั้งหมดกลับเป็น Uint8List (JPG)
    final Map<String, Uint8List> resultBytes = {};
    for (final entry in variants.entries) {
      resultBytes[entry.key] = Uint8List.fromList(
        img.encodeJpg(entry.value, quality: 100),
      );
    }

    return resultBytes;
  } catch (e) {
    debugPrint('Isolate Error: $e');
    return null;
  }
}

// ฟังก์ชันจำกัดสี (Threshold) ทำงานเร็วขึ้นเพราะรันใน Isolate
img.Image _applyPixelThreshold(img.Image src, int threshold) {
  final result = src.clone();
  for (int y = 0; y < result.height; y++) {
    for (int x = 0; x < result.width; x++) {
      final pixel = result.getPixel(x, y);
      // อ่านค่าความสว่างจาก Red channel (เพราะถูกแปลงเป็น Grayscale แล้ว)
      final int gray = pixel.r.toInt();
      if (gray > threshold) {
        result.setPixelRgb(x, y, 255, 255, 255); // สีขาว
      } else {
        result.setPixelRgb(x, y, 0, 0, 0); // สีดำ
      }
    }
  }
  return result;
}
