import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

// Your imports
import 'package:trffic_ilght_app/core/models/models.dart';
import 'package:trffic_ilght_app/services/sign_Number_OCR.dart';
import 'package:ultralytics_yolo/utils/error_handler.dart';
import 'package:ultralytics_yolo/utils/map_converter.dart';
import 'package:ultralytics_yolo/yolo.dart';
import '../../services/model_manager.dart';

class SingleImageScreen extends StatefulWidget {
  const SingleImageScreen({super.key});

  @override
  State<SingleImageScreen> createState() => _SingleImageScreenState();
}

class _SingleImageScreenState extends State<SingleImageScreen> {
  final ImagePicker _picker = ImagePicker();

  List<Map<String, dynamic>> _detections = [];
  Uint8List? _imageBytes;
  Uint8List? _annotatedImage;

  Uint8List? _signNumberCropImage;
  Uint8List? _debugOcrImage;
  String? _ocrVariantName;
  String? _extractedNumber;

  late final YOLO _yolo;
  late final ModelManager _modelManager;
  final SignNumberOCR _ocrService = SignNumberOCR();

  String? _modelPath;
  bool _isModelReady = false;
  bool _isPredicting = false;

  @override
  void initState() {
    super.initState();
    _modelManager = ModelManager();
    _initializeYOLO();
  }

  Future<void> _initializeYOLO() async {
    try {
      _modelPath = await _modelManager.getModelPath(
        ModelType.bestFloat16traffic,
      );

      if (_modelPath == null) {
        _showSnackBar('ไม่พบไฟล์โมเดล');
        return;
      }

      _yolo = YOLO(modelPath: _modelPath!, task: YOLOTask.detect);
      await _yolo.loadModel();

      if (mounted) {
        setState(() {
          _isModelReady = true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      final error = YOLOErrorHandler.handleError(
        e,
        'Failed to load model $_modelPath for task ${YOLOTask.detect.name}',
      );
      _showSnackBar('Error loading model: ${error.message}');
    }
  }

  Future<void> _pickAndPredict() async {
    if (!_isModelReady) {
      _showSnackBar('กรุณารอโมเดลโหลดสักครู่...');
      return;
    }

    final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    final Uint8List bytes = await file.readAsBytes();

    setState(() {
      _isPredicting = true;
      _imageBytes = bytes;
      _annotatedImage = null;
      _extractedNumber = null;
      _debugOcrImage = null;
    });

    try {
      // 1. YOLO Prediction
      final result = await _yolo.predict(bytes);
      final List<Map<String, dynamic>> parsedDetections =
          result['boxes'] is List
          ? MapConverter.convertBoxesList(result['boxes'] as List)
          : [];

      debugPrint('=== YOLO DETECTION RESULTS ===');
      debugPrint('จำนวน detections: ${parsedDetections.length}');
      for (int i = 0; i < parsedDetections.length; i++) {
        final d = parsedDetections[i];
        debugPrint('Detection $i:');
        debugPrint(
          '  className: ${d['className']} | type: ${d['className'].runtimeType}',
        );
        debugPrint('  confidence: ${d['confidence']}');
      }
      debugPrint('=============================');

      // 2. จัดการเรื่อง Crop และ Image Preprocessing ใน Isolate
      final Uint8List? signCrop = await _cropSignNumberImageAsync(
        originalImageBytes: bytes,
        detections: parsedDetections,
      );

      String? foundNumber;
      Uint8List? debugImage;
      String? debugVariantName;

      // ค้นหาเป้าหมาย OCR
      for (final d in parsedDetections) {
        String className = (d['className'] ?? d['class'] ?? '')
            .toString()
            .toLowerCase()
            .trim();

        debugPrint('🔍 Checking className: "$className"');

        final bool isCandidateForOcr =
            className == 'sign_number' ||
            className.contains('sign') ||
            className.contains('number') ||
            className.contains('speed') ||
            className.contains('warning');

        if (!isCandidateForOcr) {
          continue;
        }

        debugPrint('  ✅ This could have numbers, trying OCR...');

        final Rect? bbox = _convertToRect(d, bytes);
        if (bbox == null) {
          debugPrint('  ⚠️ Failed to convert bbox');
          continue;
        }

        // 3. เริ่มทำ OCR (ระบบ OCR ควรรับภาพที่ถูก Preprocess ไปประมวลผลได้ดีขึ้น)
        final OcrResult ocrResult = await _ocrService.extractNumberFromBox(
          originalImageBytes: bytes,
          boundingBox: bbox,
        );

        debugPrint(
          '  📊 OCR Result: "${ocrResult.text}" | Variant: ${ocrResult.debugVariantName}',
        );

        debugImage = ocrResult.debugImageBytes;
        debugVariantName = ocrResult.debugVariantName;

        if (ocrResult.text != null && ocrResult.text!.isNotEmpty) {
          foundNumber = ocrResult.text;
          debugPrint('  🎉 Found number: $foundNumber');
        }
      }

      if (!mounted) return;

      setState(() {
        _detections = parsedDetections;
        _annotatedImage = result['annotatedImage'] as Uint8List?;
        // ภาพที่โชว์จะเป็นภาพที่ผ่านการแต่งสีดำ/ขาวแล้ว
        _signNumberCropImage = signCrop;
        _debugOcrImage = debugImage;
        _ocrVariantName = debugVariantName;
        _extractedNumber = foundNumber;
      });
    } catch (e) {
      _showSnackBar('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _isPredicting = false);
    }
  }

  // ✅ ปรับปรุงให้รองรับค่า Normalized (0.0 - 1.0) หากเจอ
  Rect? _convertToRect(Map<String, dynamic> d, Uint8List originalBytes) {
    double x1 = (d['x1'] ?? 0.0).toDouble();
    double y1 = (d['y1'] ?? 0.0).toDouble();
    double x2 = (d['x2'] ?? 0.0).toDouble();
    double y2 = (d['y2'] ?? 0.0).toDouble();

    return Rect.fromLTRB(x1, y1, x2, y2);
  }

  // ✅ Isolate สำหรับดึงภาพ ย่อ และปรับแต่งสี (Preprocessing)
  Future<Uint8List?> _cropSignNumberImageAsync({
    required Uint8List originalImageBytes,
    required List<Map<String, dynamic>> detections,
  }) async {
    final mapData = {'bytes': originalImageBytes, 'detections': detections};

    return await Isolate.run(() {
      try {
        final Uint8List bytes = mapData['bytes'] as Uint8List;
        final List<Map<String, dynamic>> dets =
            mapData['detections'] as List<Map<String, dynamic>>;

        final decoded = img.decodeImage(bytes);
        if (decoded == null) {
          debugPrint('Crop: decodeImage failed');
          return null;
        }

        final int imgW = decoded.width;
        final int imgH = decoded.height;

        for (final d in dets) {
          final String className = (d['className'] ?? d['class'] ?? '')
              .toString()
              .toLowerCase()
              .trim();

          if (className != 'sign_number') continue;

          double x1 = (d['x1'] ?? 0.0).toDouble();
          double y1 = (d['y1'] ?? 0.0).toDouble();
          double x2 = (d['x2'] ?? 0.0).toDouble();
          double y2 = (d['y2'] ?? 0.0).toDouble();

          if (x2 <= 1.0 && y2 <= 1.0) {
            x1 *= imgW;
            y1 *= imgH;
            x2 *= imgW;
            y2 *= imgH;
          }

          final double width = x2 - x1;
          final double height = y2 - y1;

          if (width <= 0 || height <= 0) return null;

          final double paddingW = width * 0.20;
          final double paddingH = height * 0.20;

          final int cropLeft = max(0, (x1 - paddingW).round());
          final int cropTop = max(0, (y1 - paddingH).round());
          final int cropRight = min(imgW, (x2 + paddingW).round());
          final int cropBottom = min(imgH, (y2 + paddingH).round());

          final int cropWidth = cropRight - cropLeft;
          final int cropHeight = cropBottom - cropTop;

          if (cropWidth < 5 || cropHeight < 5) return null;

          // 1. ตัดภาพดั้งเดิม
          final cropped = img.copyCrop(
            decoded,
            x: cropLeft,
            y: cropTop,
            width: cropWidth,
            height: cropHeight,
          );

          // ---------------------------------------------------------
          // 🛠️ IMAGE PREPROCESSING สำหรับป้าย LED (ทำใน Isolate)
          // ---------------------------------------------------------

          // แปลงเป็นขาวดำ
          img.Image processed = img.grayscale(cropped);

          // ปรับ Contrast ให้ไฟ LED เด่นขึ้นมา (ปรับค่า 1.5 - 2.0 ตามความเหมาะสม)
          processed = img.adjustColor(processed, contrast: 1.8);

          // Thresholding แยกความสว่างและมืดขาดจากกัน (ใช้ 0.6 เป็นค่าเริ่มต้น)
          processed = img.luminanceThreshold(processed, threshold: 0.6);

          // Invert สี เพื่อให้พื้นหลังขาว ตัวเลขดำ (OCR จะอ่านง่ายที่สุด)
          img.invert(processed);

          // ส่งออกเป็น Jpg
          return Uint8List.fromList(img.encodeJpg(processed, quality: 100));
        }

        return null;
      } catch (e) {
        debugPrint('Crop sign_number isolate error: $e');
        return null;
      }
    });
  }

  String _thaiLabel(String className) {
    const Map<String, String> labels = {
      'dont_go_straight_arrow': 'ห้ามตรงไป',
      'dont_turn_left': 'ห้ามเลี้ยวซ้าย',
      'dont_turn_right': 'ห้ามเลี้ยวขวา',
      'go_straight_arrow': 'ตรงไป',
      'green_light_circle': 'ไฟเขียว',
      'off_light': 'ไฟดับ',
      'red_light_circle': 'ไฟแดง',
      'sign_number': 'ป้ายตัวเลข',
      'turn_left': 'เลี้ยวซ้าย',
      'turn_right': 'เลี้ยวขวา',
      'yellow_light': 'ไฟเหลือง',
    };

    return labels[className] ?? className;
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _buildPreviewCard({
    required String title,
    required Uint8List imageBytes,
    Color borderColor = Colors.indigo,
    String? subtitle,
    double height = 120,
  }) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(fontWeight: FontWeight.bold, color: borderColor),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 10),
            Image.memory(imageBytes, height: height, fit: BoxFit.contain),
          ],
        ),
      ),
    );
  }

  Widget _buildResultBox() {
    if (_extractedNumber != null) {
      return Center(
        child: Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.greenAccent, width: 2),
          ),
          child: Column(
            children: [
              const Text(
                'OCR อ่านได้:',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Text(
                _extractedNumber!,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 60,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_ocrVariantName != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Variant: $_ocrVariantName',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (_debugOcrImage != null && !_isPredicting) {
      return Center(
        child: Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Column(
            children: [
              const Text(
                '⚠️ AI เห็นป้าย แต่ไม่สามารถแกะตัวเลขออกมาได้',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              if (_ocrVariantName != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Variant ล่าสุด: $_ocrVariantName',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    _ocrService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'ทดสอบ OCR รูปภาพ',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: !_isModelReady
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'กำลังเตรียม AI โมเดล...',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  )
                : SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isPredicting ? null : _pickAndPredict,
                      icon: const Icon(Icons.add_photo_alternate_rounded),
                      label: Text(
                        _isPredicting
                            ? 'กำลังวิเคราะห์...'
                            : 'เลือกรูปภาพจากแกลเลอรี',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_signNumberCropImage != null)
                    _buildPreviewCard(
                      title: 'ภาพ crop ที่ผ่านการกรองสี (Preprocessed)',
                      subtitle: 'ภาพขาว-ดำ แบบ Invert พร้อมส่งเข้า OCR',
                      imageBytes: _signNumberCropImage!,
                      borderColor: Colors.orange,
                    ),

                  if (_debugOcrImage != null)
                    _buildPreviewCard(
                      title: 'ภาพที่ส่งให้ OCR อ่านจริง',
                      subtitle: _ocrVariantName != null
                          ? 'Preprocess: $_ocrVariantName'
                          : 'ภาพหลัง preprocess ภายใน Service',
                      imageBytes: _debugOcrImage!,
                      borderColor: Colors.indigo,
                    ),

                  _buildResultBox(),

                  if (_imageBytes != null)
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 10),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.memory(
                            _annotatedImage ?? _imageBytes!,
                            fit: BoxFit.contain,
                          ),
                          if (_isPredicting)
                            Container(
                              color: Colors.black45,
                              padding: const EdgeInsets.all(20),
                              child: const CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  if (_detections.isNotEmpty) ...[
                    const Text(
                      'รายละเอียดที่ตรวจพบ:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _detections.map((d) {
                        final String className =
                            d['className']?.toString() ??
                            d['class']?.toString() ??
                            'Unknown';

                        final String confidence = d['confidence'] != null
                            ? ((d['confidence'] as double) * 100)
                                  .toStringAsFixed(1)
                            : '0.0';

                        return Chip(
                          label: Text(
                            '${_thaiLabel(className)} ($confidence%)',
                          ),
                          backgroundColor: Colors.indigo[50],
                          labelStyle: const TextStyle(
                            color: Colors.indigo,
                            fontWeight: FontWeight.bold,
                          ),
                          side: BorderSide(color: Colors.indigo[200]!),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
