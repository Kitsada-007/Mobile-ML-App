import 'dart:typed_data';
import 'dart:ui';
import 'dart:math';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

// 🌟 สร้าง Class เล็กๆ เพื่อคืนค่าทั้งตัวเลขและรูปภาพ
class OcrResult {
  final String? text;
  final Uint8List? debugImageBytes;
  OcrResult({this.text, this.debugImageBytes});
}

class SingNumberOCR {
  final TextRecognizer _textRecognizer = TextRecognizer();

  Future<OcrResult> extractNumberFromBox({
    required Uint8List originalImageBytes,
    required Rect boundingBox,
  }) async {
    try {
      final image = img.decodeImage(originalImageBytes);
      if (image == null) return OcrResult(text: null, debugImageBytes: null);

      int imgW = image.width;
      int imgH = image.height;

      double left = boundingBox.left;
      double top = boundingBox.top;
      double width = boundingBox.width;
      double height = boundingBox.height;

      // 🌟 ตรวจสอบว่าพิกัดเป็น Ratio (0-1) หรือ Pixel (มากกว่า 1)
      // ถ้า YOLO ส่งมาเป็น 0.0 - 1.0 ให้คูณขนาดรูปจริง
      if (width <= 1.0 && height <= 1.0) {
        left *= imgW;
        top *= imgH;
        width *= imgW;
        height *= imgH;
      }

      // เผื่อขอบ (Padding) 10%
      double paddingW = width * 0.1;
      double paddingH = height * 0.1;

      int cropLeft = max(0, (left - paddingW).toInt());
      int cropTop = max(0, (top - paddingH).toInt());
      int cropWidth = min(imgW - cropLeft, (width + (paddingW * 2)).toInt());
      int cropHeight = min(imgH - cropTop, (height + (paddingH * 2)).toInt());

      if (cropWidth < 10 || cropHeight < 10) return OcrResult();

      // ตัดภาพ
      var cropped = img.copyCrop(
        image,
        x: cropLeft,
        y: cropTop,
        width: cropWidth,
        height: cropHeight,
      );

      // ขยายภาพ (Upscale) ถ้าเล็กไป
      if (cropped.height < 60) {
        cropped = img.copyResize(
          cropped,
          width: cropped.width * 2,
          height: cropped.height * 2,
          interpolation: img.Interpolation.cubic,
        );
      }

      // ปรับภาพให้ชัดขึ้น
      cropped = img.grayscale(cropped);

      // 🌟 แปลงภาพที่ผ่านกระบวนการแล้วกลับเป็น Bytes เพื่อเอาไปโชว์ให้เราดู
      Uint8List debugBytes = Uint8List.fromList(img.encodeJpg(cropped));

      // ส่งให้ ML Kit
      final inputImage = InputImage.fromBytes(
        bytes: debugBytes,
        metadata: InputImageMetadata(
          size: Size(cropped.width.toDouble(), cropped.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: cropped.width,
        ),
      );

      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );
      String cleanText = recognizedText.text.replaceAll(RegExp(r'[^0-9]'), '');

      // คืนค่ากลับไปทั้งข้อความ (ถ้ามี) และรูปภาพ
      return OcrResult(
        text: (cleanText.isNotEmpty && cleanText.length <= 3)
            ? cleanText
            : null,
        debugImageBytes: debugBytes,
      );
    } catch (e) {
      print("OCR Error: $e");
      return OcrResult();
    }
  }

  void dispose() {
    _textRecognizer.close();
  }
}
