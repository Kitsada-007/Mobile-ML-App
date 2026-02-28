import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:trffic_ilght_app/core/models/models.dart';
// 🌟 นำเข้า OCR Service ที่เราสร้างไว้
import 'package:trffic_ilght_app/services/sign_Number_OCR.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/utils/map_converter.dart';
import 'package:ultralytics_yolo/utils/error_handler.dart';
import '../../services/model_manager.dart';

class SingleImageScreen extends StatefulWidget {
  const SingleImageScreen({super.key});

  @override
  State<SingleImageScreen> createState() => _SingleImageScreenState();
}

class _SingleImageScreenState extends State<SingleImageScreen> {
  final _picker = ImagePicker();
  List<Map<String, dynamic>> _detections = [];
  Uint8List? _imageBytes;
  Uint8List? _annotatedImage;

  late YOLO _yolo;
  String? _modelPath;
  bool _isModelReady = false;
  bool _isPredicting = false;
  late final ModelManager _modelManager;

  // 🌟 ตัวแปรสำหรับ OCR (ประกาศแค่ชุดเดียว)
  final SingNumberOCR _ocrService = SingNumberOCR();
  String? _extractedNumber;
  Uint8List? _debugOcrImage; // 🌟 เพิ่มตัวแปรเก็บภาพที่ตัดแล้ว

  @override
  void initState() {
    super.initState();
    _modelManager = ModelManager();
    _initializeYOLO();
  }

  Future<void> _initializeYOLO() async {
    _modelPath = await _modelManager.getModelPath(ModelType.bestFloat16traffic);
    if (_modelPath == null) return;
    _yolo = YOLO(modelPath: _modelPath!, task: YOLOTask.detect);
    try {
      await _yolo.loadModel();
      if (mounted) setState(() => _isModelReady = true);
    } catch (e) {
      if (mounted) {
        final error = YOLOErrorHandler.handleError(
          e,
          'Failed to load model $_modelPath for task ${YOLOTask.detect.name}',
        );
        _showSnackBar('Error loading model: ${error.message}');
      }
    }
  }

  Future<void> _pickAndPredict() async {
    if (!_isModelReady) {
      return _showSnackBar('Model is loading, please wait...');
    }
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    final bytes = await file.readAsBytes();

    setState(() {
      _isPredicting = true;
      _imageBytes = bytes;
      _annotatedImage = null;
      _detections = [];
      _extractedNumber = null; // ล้างตัวเลขเก่า
      _debugOcrImage = null; // ล้างภาพตัดเก่า
    });

    try {
      // 1. รัน YOLO ตรวจจับวัตถุ
      final result = await _yolo.predict(bytes);

      List<Map<String, dynamic>> parsedDetections = result['boxes'] is List
          ? MapConverter.convertBoxesList(result['boxes'] as List)
          : [];

      String? foundNumber;

      // 2. 🌟 ค้นหาว่ามีป้ายตัวเลขไหม ถ้ามีให้ส่งไปทำ OCR
      for (var d in parsedDetections) {
        if (d['class'] == 'sign_number') {
          double left = (d['left'] ?? 0.0).toDouble();
          double top = (d['top'] ?? 0.0).toDouble();
          double width = (d['width'] ?? 0.0).toDouble();
          double height = (d['height'] ?? 0.0).toDouble();

          Rect bbox = Rect.fromLTWH(left, top, width, height);

          // 🌟 รับค่ากลับมาทั้งข้อความและรูปภาพ
          final ocrResult = await _ocrService.extractNumberFromBox(
            originalImageBytes: bytes,
            boundingBox: bbox,
          );

          foundNumber = ocrResult.text;

          // อัปเดตภาพ Debug ให้แสดงบนหน้าจอ
          if (mounted) {
            setState(() {
              _debugOcrImage = ocrResult.debugImageBytes;
            });
          }

          if (foundNumber != null) break; // เจอตัวเลขแล้ว หยุดหา
        }
      }

      // 3. อัปเดตหน้าจอ
      if (mounted) {
        setState(() {
          _detections = parsedDetections;
          _annotatedImage = result['annotatedImage'] as Uint8List?;
          _extractedNumber = foundNumber;
        });
      }
    } catch (e) {
      _showSnackBar('Error during prediction: $e');
    } finally {
      if (mounted) setState(() => _isPredicting = false);
    }
  }

  void _showSnackBar(String msg) => mounted
      ? ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)))
      : null;

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
        foregroundColor: const Color.fromARGB(255, 0, 0, 0),
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
            child: Column(
              children: [
                if (!_isModelReady)
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text(
                        "กำลังเตรียม AI โมเดล...",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  )
                else
                  SizedBox(
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
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🌟 ส่วนที่ 1: แสดงภาพที่ถูกตัด (Debug Image)
                  if (_debugOcrImage != null)
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.indigo, width: 2),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              "ภาพที่ส่งให้ OCR อ่าน:",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            Image.memory(
                              _debugOcrImage!,
                              height: 100, // ปรับความสูงตามต้องการ
                              fit: BoxFit.contain,
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 🌟 ส่วนที่ 2: แสดงผลลัพธ์ตัวเลข
                  if (_extractedNumber != null)
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 15,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: Colors.greenAccent,
                            width: 2,
                          ),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              "OCR อ่านได้:",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              _extractedNumber!,
                              style: const TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 60,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Digital',
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_debugOcrImage != null && !_isPredicting)
                    // กรณีโชว์ภาพตัดแล้ว แต่ OCR คืนค่าเป็น null หรือหาตัวเลขไม่เจอ
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 20),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          "⚠️ AI เห็นป้าย แต่ไม่สามารถแกะตัวเลขออกมาได้",
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ),

                  // 🌟 ส่วนที่ 3: ภาพหลักและรายละเอียด YOLO
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
                        final className = d['class']?.toString() ?? 'Unknown';
                        final confidence = d['confidence'] != null
                            ? ((d['confidence'] as double) * 100)
                                  .toStringAsFixed(1)
                            : '0.0';

                        return Chip(
                          label: Text('$className ($confidence%)'),
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
