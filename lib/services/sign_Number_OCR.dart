import 'dart:typed_data';
import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

class SingNumberOCR {
  final TextRecognizer _textRecognizer = TextRecognizer();

  Future<String?> extractNumberFromBox({
    required Uint8List originalImageBytes,
    required Rect boundingBox, // พิกัด 0.0 - 1.0 จาก YOLO
  }) async {
    try {
      // 1. ถอดรหัสภาพต้นฉบับ
      final image = img.decodeImage(originalImageBytes);
      if (image == null) return null;

      // --- 🎯 ส่วนการคำนวณ Scaling ---
      int imgW = image.width;
      int imgH = image.height;

      // แปลงพิกัด Ratio เป็นพิกัด Pixel จริง
      int left = (boundingBox.left * imgW).toInt().clamp(0, imgW);
      int top = (boundingBox.top * imgH).toInt().clamp(0, imgH);
      int width = (boundingBox.width * imgW).toInt().clamp(0, imgW - left);
      int height = (boundingBox.height * imgH).toInt().clamp(0, imgH - top);

      // ถ้าพื้นที่เล็กเกินไป มักจะอ่านไม่ออก ให้ข้ามเลย
      if (width < 20 || height < 20) return null;

      // 2. Crop ภาพตามพิกัดที่คำนวณได้
      var cropped = img.copyCrop(
        image,
        x: left,
        y: top,
        width: width,
        height: height,
      );

      // 3. ✨ Pre-processing: ทำให้ตัวเลขชัดขึ้น
      // ปรับเป็นขาวดำ และเพิ่ม Contrast เพื่อลดแสงฟุ้งจากไฟจราจร
      cropped = img.grayscale(img.contrast(cropped, contrast: 150));

      // 4. แปลงกลับเป็น Bytes เพื่อส่งให้ ML Kit
      final inputImage = InputImage.fromBytes(
        bytes: Uint8List.fromList(img.encodeJpg(cropped)),
        metadata: InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: width,
        ),
      );

      // 5. ประมวลผลข้อความ
      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );

      // กรองเอาเฉพาะตัวเลข
      String cleanText = recognizedText.text.replaceAll(RegExp(r'[^0-9]'), '');

      return cleanText.isNotEmpty ? cleanText : null;
    } catch (e) {
      print("OCR Error: $e");
      return null;
    }
  }

  void dispose() {
    _textRecognizer.close();
  }
}
