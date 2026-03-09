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
// Data Classes
// ============================================================================

class OcrVariantPreview {
  final String name;
  final Uint8List imageBytes;
  final String rawText;
  final String cleanText;
  final int score;

  OcrVariantPreview({
    required this.name,
    required this.imageBytes,
    required this.rawText,
    required this.cleanText,
    required this.score,
  });
}

class OcrResult {
  final String? text;
  final int? value;
  final Uint8List? debugImageBytes;
  final String? debugVariantName;
  final List<OcrVariantPreview> variantPreviews;

  const OcrResult({
    this.text,
    this.value,
    this.debugImageBytes,
    this.debugVariantName,
    this.variantPreviews = const [],
  });

  bool get hasValue => value != null;
}

// ============================================================================
// OCR Service
// ============================================================================

class SignNumberOCR {
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  Future<OcrResult> extractNumberFromBox({
    required Uint8List originalImageBytes,
    required Rect boundingBox,
  }) async {
    try {
      final isolateData = <String, dynamic>{
        'imageBytes': originalImageBytes,
        'left': boundingBox.left,
        'top': boundingBox.top,
        'width': boundingBox.width,
        'height': boundingBox.height,
      };

      final Map<String, Uint8List>? processedVariants = await Isolate.run(
        () => _processImageInIsolate(isolateData),
      );

      if (processedVariants == null || processedVariants.isEmpty) {
        debugPrint('OCR: Isolate failed to process image');
        return const OcrResult();
      }

      final List<OcrVariantPreview> previews = [];

      String? bestText;
      int? bestValue;
      Uint8List? bestImage;
      String? bestVariant;
      int bestScore = -1;

      String? fallbackText;
      int? fallbackValue;
      Uint8List? fallbackImage;
      String? fallbackVariant;

      for (final entry in processedVariants.entries) {
        final String variantName = entry.key;
        final Uint8List bytes = entry.value;

        final String raw = await _runMlKitWithAutoCleanup(bytes);
        final String clean = _cleanDigits(raw);
        final int score = _scoreText(clean);
        final int? parsedValue = _parseTrafficLightNumber(clean);

        previews.add(
          OcrVariantPreview(
            name: variantName,
            imageBytes: bytes,
            rawText: raw,
            cleanText: clean,
            score: score,
          ),
        );

        debugPrint(
          '✅ OCR [$variantName] RAW => "$raw" | CLEAN => "$clean" | SCORE => $score | VALUE => $parsedValue',
        );

        if (fallbackText == null && clean.isNotEmpty) {
          fallbackText = clean;
          fallbackValue = parsedValue;
          fallbackImage = bytes;
          fallbackVariant = variantName;
          debugPrint('  └─ Set as fallback: $fallbackText');
        }

        if (score > bestScore) {
          bestScore = score;
          bestText = clean;
          bestValue = parsedValue;
          bestImage = bytes;
          bestVariant = variantName;
          debugPrint('  └─ New best! Score: $score');
        }
      }

      debugPrint(
        '🎯 Final OCR Result: text=$bestText, value=$bestValue, variant=$bestVariant, score=$bestScore',
      );

      // ✅ ถ้า best score < 50 ให้ใช้ fallback หรือไม่ส่งผล
      if (bestScore < 50) {
        debugPrint(
          '⚠️ Best score too low ($bestScore < 50), using fallback instead',
        );
        bestText = fallbackText;
        bestValue = fallbackValue;
        bestImage = fallbackImage;
        bestVariant = fallbackVariant;
      }

      bestText ??= fallbackText;
      bestValue ??= fallbackValue;
      bestImage ??= fallbackImage;
      bestVariant ??= fallbackVariant;

      return OcrResult(
        text: bestText,
        value: bestValue,
        debugImageBytes: bestImage,
        debugVariantName: bestVariant,
        variantPreviews: previews,
      );
    } catch (e, st) {
      debugPrint('OCR Error: $e');
      debugPrint('$st');
      return const OcrResult();
    }
  }

  Future<String> _runMlKitWithAutoCleanup(Uint8List imageBytes) async {
    File? tempFile;
    try {
      final tempDir = await getTemporaryDirectory();
      tempFile = File(
        '${tempDir.path}/ocr_${DateTime.now().microsecondsSinceEpoch}.png',
      );

      await tempFile.writeAsBytes(imageBytes, flush: true);

      final inputImage = InputImage.fromFilePath(tempFile.path);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      return recognizedText.text;
    } catch (e) {
      debugPrint('ML Kit Process Error: $e');
      return '';
    } finally {
      if (tempFile != null) {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (e) {
          debugPrint('Failed to delete temp OCR file: $e');
        }
      }
    }
  }

  String _cleanDigits(String raw) {
    if (raw.isEmpty) return '';

    String normalized = raw
        .replaceAll('O', '0')
        .replaceAll('o', '0')
        .replaceAll('D', '0')
        .replaceAll('Q', '0')
        .replaceAll('I', '1')
        .replaceAll('l', '1')
        .replaceAll('|', '1')
        .replaceAll('!', '1')
        .replaceAll('S', '5')
        .replaceAll('s', '5')
        .replaceAll('B', '8')
        .replaceAll('Z', '2');

    normalized = normalized.replaceAll(RegExp(r'\s+'), '');

    final matches = RegExp(r'\d{1,2}').allMatches(normalized);
    for (final m in matches) {
      final text = m.group(0)!;
      final value = int.tryParse(text);
      if (value != null && value >= 0 && value <= 99) {
        return text;
      }
    }

    final digitsOnly = normalized.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length <= 2) return digitsOnly;
    return digitsOnly.substring(0, 2);
  }

  int? _parseTrafficLightNumber(String text) {
    if (text.isEmpty) return null;
    final int? value = int.tryParse(text);
    if (value == null) return null;
    if (value < 0 || value > 99) return null;
    return value;
  }

  bool _isGoodResult(String text) {
    return _parseTrafficLightNumber(text) != null;
  }

  int _scoreText(String text) {
    if (text.isEmpty) return 0;

    final int? value = _parseTrafficLightNumber(text);
    if (value == null) return 0;

    int score = 50;

    if (text.length == 2) {
      score += 25;
    } else if (text.length == 1) {
      score += 10;
    }

    if (value <= 60) {
      score += 15;
    }

    if (value <= 30) {
      score += 5;
    }

    if (_isGoodResult(text)) {
      score += 5;
    }

    return score;
  }

  void dispose() {
    _textRecognizer.close();
  }
}

// ============================================================================
// Isolate image processing
// ============================================================================

Future<Map<String, Uint8List>?> _processImageInIsolate(
  Map<String, dynamic> data,
) async {
  try {
    final Uint8List originalImageBytes = data['imageBytes'] as Uint8List;
    double left = (data['left'] as num).toDouble();
    double top = (data['top'] as num).toDouble();
    double width = (data['width'] as num).toDouble();
    double height = (data['height'] as num).toDouble();

    debugPrint(
      '🔧 OCR Crop Input: left=$left, top=$top, width=$width, height=$height',
    );

    final img.Image? image = img.decodeImage(originalImageBytes);
    if (image == null) {
      debugPrint('❌ Failed to decode image');
      return null;
    }

    final int imgW = image.width;
    final int imgH = image.height;

    debugPrint('📐 Image size: ${imgW}x${imgH}');

    if (width <= 0 || height <= 0) {
      debugPrint('❌ Invalid width/height: $width x $height');
      return null;
    }

    // รองรับ normalized bounding box
    if (left <= 1.0 && top <= 1.0 && width <= 1.0 && height <= 1.0) {
      left *= imgW;
      top *= imgH;
      width *= imgW;
      height *= imgH;
      debugPrint(
        '📐 Converted from normalized to pixel: left=$left, top=$top, width=$width, height=$height',
      );
    }

    // padding เพิ่มขึ้น (จาก 3% เป็น 10%) เพื่อไม่ให้ตัดเลขขอบ
    final double paddingW = width * 0.10;
    final double paddingH = height * 0.10;

    final int cropLeft = max(0, (left - paddingW).round());
    final int cropTop = max(0, (top - paddingH).round());
    final int cropRight = min(imgW, (left + width + paddingW).round());
    final int cropBottom = min(imgH, (top + height + paddingH).round());

    final int cropWidth = cropRight - cropLeft;
    final int cropHeight = cropBottom - cropTop;

    debugPrint(
      '🖼️ Crop region: left=$cropLeft, top=$cropTop, width=$cropWidth, height=$cropHeight',
    );

    if (cropWidth < 6 || cropHeight < 6) {
      debugPrint('❌ Crop too small: ${cropWidth}x${cropHeight}');
      return null;
    }

    img.Image baseCrop = img.copyCrop(
      image,
      x: cropLeft,
      y: cropTop,
      width: cropWidth,
      height: cropHeight,
    );

    baseCrop = img.copyResize(
      baseCrop,
      width: max(baseCrop.width * 4, 64),
      height: max(baseCrop.height * 4, 64),
      interpolation: img.Interpolation.cubic,
    );

    debugPrint('🔍 Upscaled to: ${baseCrop.width}x${baseCrop.height}');

    final Map<String, img.Image> variants = {};

    // ✅ v0: ภาพต้นฉบับ upscaled - ดีที่สุด ใช้นี่เลย
    variants['v0_original_upscaled'] = baseCrop.clone();

    // ✅ v1: ลบ noise ด้วย morphological operation (erosion-dilation)
    img.Image v1 = _denoiseImage(baseCrop.clone());
    variants['v1_denoised'] = v1;

    // ✅ v2: Sharp + Threshold (เหมือน v6 แต่เก่า ให้ลองทั้ง 2 version)
    img.Image v2 = img.grayscale(baseCrop.clone());
    v2 = img.adjustColor(v2, contrast: 1.5);
    img.Image v2_sharpened = _sharpenImage(v2.clone());
    v2_sharpened = _applyPixelThreshold(v2_sharpened.clone(), 120);
    variants['v2_sharp_threshold'] = v2_sharpened;

    final Map<String, Uint8List> resultBytes = {};
    for (final entry in variants.entries) {
      resultBytes[entry.key] = Uint8List.fromList(img.encodePng(entry.value));
    }

    // 🔍 DEBUG: บันทึกรูป crop ทั้งหมดไว้เพื่อ debug
    await _saveDebugImages(resultBytes, baseCrop);

    return resultBytes;
  } catch (e, st) {
    debugPrint('Isolate Error: $e');
    debugPrint('$st');
    return null;
  }
}

img.Image _applyPixelThreshold(img.Image src, int threshold) {
  final img.Image result = src.clone();

  for (int y = 0; y < result.height; y++) {
    for (int x = 0; x < result.width; x++) {
      final pixel = result.getPixel(x, y);

      // คำนวณ grayscale value ที่ถูกต้อง (ไม่ใช่แค่ red channel)
      final int gray =
          ((pixel.r.toInt() * 299 +
                      pixel.g.toInt() * 587 +
                      pixel.b.toInt() * 114) /
                  1000)
              .round();

      if (gray > threshold) {
        result.setPixelRgb(x, y, 255, 255, 255);
      } else {
        result.setPixelRgb(x, y, 0, 0, 0);
      }
    }
  }

  return result;
}

img.Image _sharpenImage(img.Image src) {
  return img.convolution(src, filter: <num>[0, -1, 0, -1, 5, -1, 0, -1, 0]);
}

img.Image _denoiseImage(img.Image src) {
  // ✅ erosion + dilation = morphological opening (ลบ noise ขาวเล็ก)
  // แล้ว dilation + erosion = closing (เติมช่องว่างเล็กดำ)

  // ✅ ทำ erosion 1 ครั้ง (ลบ noise)
  img.Image eroded = _morphErode(src.clone(), 2);

  // ✅ ทำ dilation 1 ครั้ง (คืนขนาด)
  img.Image denoised = _morphDilate(eroded, 2);

  return denoised;
}

img.Image _morphErode(img.Image src, int size) {
  final img.Image result = src.clone();

  for (int y = size; y < result.height - size; y++) {
    for (int x = size; x < result.width - size; x++) {
      // หาค่า min ในวงของ size x size
      int minGray = 255;
      for (int dy = -size; dy <= size; dy++) {
        for (int dx = -size; dx <= size; dx++) {
          final pixel = result.getPixel(x + dx, y + dy);
          final int gray =
              ((pixel.r.toInt() * 299 +
                          pixel.g.toInt() * 587 +
                          pixel.b.toInt() * 114) /
                      1000)
                  .round();
          minGray = (gray < minGray) ? gray : minGray;
        }
      }
      result.setPixelRgb(x, y, minGray, minGray, minGray);
    }
  }

  return result;
}

img.Image _morphDilate(img.Image src, int size) {
  final img.Image result = src.clone();

  for (int y = size; y < result.height - size; y++) {
    for (int x = size; x < result.width - size; x++) {
      // หาค่า max ในวงของ size x size
      int maxGray = 0;
      for (int dy = -size; dy <= size; dy++) {
        for (int dx = -size; dx <= size; dx++) {
          final pixel = result.getPixel(x + dx, y + dy);
          final int gray =
              ((pixel.r.toInt() * 299 +
                          pixel.g.toInt() * 587 +
                          pixel.b.toInt() * 114) /
                      1000)
                  .round();
          maxGray = (gray > maxGray) ? gray : maxGray;
        }
      }
      result.setPixelRgb(x, y, maxGray, maxGray, maxGray);
    }
  }

  return result;
}

img.Image _cropCenter(img.Image src, double widthFactor, double heightFactor) {
  final int newWidth = max(1, (src.width * widthFactor).round());
  final int newHeight = max(1, (src.height * heightFactor).round());

  final int x = max(0, ((src.width - newWidth) / 2).round());
  final int y = max(0, ((src.height - newHeight) / 2).round());

  return img.copyCrop(
    src,
    x: x,
    y: y,
    width: min(newWidth, src.width - x),
    height: min(newHeight, src.height - y),
  );
}

// 🔍 DEBUG: บันทึกรูป crop ไว้เพื่อดู
Future<void> _saveDebugImages(
  Map<String, Uint8List> variants,
  img.Image baseCrop,
) async {
  try {
    final tempDir = await getTemporaryDirectory();
    final debugDir = Directory('${tempDir.path}/ocr_debug');
    if (!await debugDir.exists()) {
      await debugDir.create(recursive: true);
    }

    // บันทึกรูป base crop
    final baseFile = File('${debugDir.path}/00_base_crop.png');
    await baseFile.writeAsBytes(Uint8List.fromList(img.encodePng(baseCrop)));
    debugPrint('💾 Saved base crop to: ${baseFile.path}');

    // บันทึกแต่ละ variant
    int idx = 1;
    for (final entry in variants.entries) {
      final variantName = entry.key;
      final bytes = entry.value;
      final file = File(
        '${debugDir.path}/${idx.toString().padLeft(2, '0')}_$variantName.png',
      );
      await file.writeAsBytes(bytes);
      debugPrint('💾 Saved $variantName to: ${file.path}');
      idx++;
    }

    debugPrint('✅ Debug images saved to: ${debugDir.path}');
  } catch (e) {
    debugPrint('❌ Failed to save debug images: $e');
  }
}
