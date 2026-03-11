import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:trffic_ilght_app/core/models/models.dart';
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
  String? _digitPredictText;

  late YOLO _yolo; // model หลัก detect traffic light / sign
  late YOLO _digitYolo; // model สำหรับ detect digit 0-9
  late final ModelManager _modelManager;

  String? _modelPath;
  String? _digitModelPath;

  bool _isModelReady = false;
  bool _isDigitModelReady = false;
  bool _isPredicting = false;

  @override
  void initState() {
    super.initState();
    _modelManager = ModelManager();
    // ✅ เรียกใช้ฟังก์ชันโหลดโดยไม่สร้าง YOLO ทันที ป้องกันแอปเด้ง
    _initializeModels();
  }

  Future<void> _initializeModels() async {
    try {
      _modelPath = await _modelManager.getModelPath(
        ModelType.bestFloat16traffic,
      );

      _digitModelPath = await _modelManager.getModelPath(
        ModelType.bestFloat16number,
      );

      if (_modelPath == null) {
        _showSnackBar('ไม่พบไฟล์โมเดลหลัก');
        return;
      }

      if (_digitModelPath == null) {
        _showSnackBar('ไม่พบไฟล์โมเดลเลข');
        return;
      }

      // ✅ ย้ายการสร้าง YOLO มาไว้ตรงนี้ (หลังจากมั่นใจว่า Path ไม่ใช่ null)
      _yolo = YOLO(modelPath: _modelPath!, task: YOLOTask.detect);
      _digitYolo = YOLO(modelPath: _digitModelPath!, task: YOLOTask.detect);

      await _yolo.loadModel();
      await _digitYolo.loadModel();

      if (!mounted) return;
      setState(() {
        _isModelReady = true;
        _isDigitModelReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      final error = YOLOErrorHandler.handleError(
        e,
        'Failed to load models: main=$_modelPath digit=$_digitModelPath',
      );
      _showSnackBar('Error loading model: ${error.message}');
    }
  }

  Future<void> _pickAndPredict() async {
    if (!_isModelReady || !_isDigitModelReady) {
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
      _detections = [];
      _signNumberCropImage = null;
      _digitPredictText = null;
    });

    try {
      // =========================================================
      // 1) predict ภาพหลัก
      // =========================================================
      final result = await _yolo.predict(bytes);
      final List<Map<String, dynamic>> parsedDetections =
          result['boxes'] is List
          ? MapConverter.convertBoxesList(result['boxes'] as List)
          : [];

      debugPrint('=== YOLO MAIN DETECTION RESULTS ===');
      debugPrint('จำนวน detections: ${parsedDetections.length}');
      for (int i = 0; i < parsedDetections.length; i++) {
        final d = parsedDetections[i];
        debugPrint(
          'Detection $i => class=${d['className']} conf=${d['confidence']} '
          'box=(${d['x1']}, ${d['y1']}, ${d['x2']}, ${d['y2']})',
        );
      }
      debugPrint('==================================');

      // =========================================================
      // 2) crop sign_number
      // =========================================================
      final Uint8List? signCrop = await _cropSignNumberImageAsync(
        originalImageBytes: bytes,
        detections: parsedDetections,
      );

      String? foundNumber;

      // =========================================================
      // 3) ถ้ามี crop -> ใช้ YOLO ตัวที่ 2 อ่านเลข
      // =========================================================
      if (signCrop != null) {
        foundNumber = await _predictDigitsFromCrop(signCrop);
      }

      if (!mounted) return;

      setState(() {
        _detections = parsedDetections;
        _annotatedImage = result['annotatedImage'] as Uint8List?;
        _signNumberCropImage = signCrop;
        _digitPredictText = foundNumber;
      });
    } catch (e) {
      _showSnackBar('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) {
        setState(() => _isPredicting = false);
      }
    }
  }

  // =========================================================
  // ใช้ YOLO ตัวที่ 2 อ่านเลขจาก crop
  // =========================================================
  Future<String?> _predictDigitsFromCrop(Uint8List cropBytes) async {
    try {
      final result = await _digitYolo.predict(cropBytes);

      final List<Map<String, dynamic>> digitDetections = result['boxes'] is List
          ? MapConverter.convertBoxesList(result['boxes'] as List)
          : [];

      // 🎯 กรองเอาเฉพาะตัวเลข 0-9
      final filtered = digitDetections.where((d) {
        final cls = (d['className'] ?? d['class'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        return RegExp(r'^\d$').hasMatch(cls);
      }).toList();

      if (filtered.isEmpty) return null;

      // 🎯 เรียงจากซ้ายไปขวา
      filtered.sort((a, b) {
        final ax = (a['x1'] ?? 0).toDouble();
        final bx = (b['x1'] ?? 0).toDouble();
        return ax.compareTo(bx);
      });

      // นำมาต่อกัน
      String text = filtered
          .map((d) => (d['className'] ?? '').toString())
          .join();

      // 🎯 ตัดให้เหลือแค่ 2 หลัก (สำหรับป้ายจำกัดความเร็ว)
      if (text.length > 2) {
        text = text.substring(0, 2);
      }

      final value = int.tryParse(text);
      if (value == null || value < 0 || value > 99) {
        return null;
      }

      return text;
    } catch (e) {
      debugPrint('Digit YOLO predict error: $e');
      return null;
    }
  }

  // =========================================================
  // crop sign_number แล้วแปลงขาวดำ / ปรับแสง ใน Background Isolate
  // =========================================================
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
        if (decoded == null) return null;

        final int imgW = decoded.width;
        final int imgH = decoded.height;

        Map<String, dynamic>? bestSign;
        double bestConf = -1;

        for (final d in dets) {
          final String className = (d['className'] ?? d['class'] ?? '')
              .toString()
              .toLowerCase()
              .trim();

          if (className != 'sign_number') continue;

          final conf = (d['confidence'] ?? 0.0).toDouble();
          if (conf > bestConf) {
            bestConf = conf;
            bestSign = d;
          }
        }

        if (bestSign == null) return null;

        double x1 = (bestSign['x1'] ?? 0.0).toDouble();
        double y1 = (bestSign['y1'] ?? 0.0).toDouble();
        double x2 = (bestSign['x2'] ?? 0.0).toDouble();
        double y2 = (bestSign['y2'] ?? 0.0).toDouble();

        if (x2 <= 1.0 && y2 <= 1.0) {
          x1 *= imgW;
          y1 *= imgH;
          x2 *= imgW;
          y2 *= imgH;
        }

        final double width = x2 - x1;
        final double height = y2 - y1;

        if (width <= 0 || height <= 0) return null;

        // 🎯 เผื่อขอบ (Padding) 15%
        final double paddingW = width * 0.15;
        final double paddingH = height * 0.15;

        final int cropLeft = max(0, (x1 - paddingW).round());
        final int cropTop = max(0, (y1 - paddingH).round());
        final int cropRight = min(imgW, (x2 + paddingW).round());
        final int cropBottom = min(imgH, (y2 + paddingH).round());

        final int cropWidth = cropRight - cropLeft;
        final int cropHeight = cropBottom - cropTop;

        if (cropWidth < 8 || cropHeight < 8) return null;

        img.Image cropped = img.copyCrop(
          decoded,
          x: cropLeft,
          y: cropTop,
          width: cropWidth,
          height: cropHeight,
        );

        // 🎯 ขยายให้โมเดลอ่านง่ายขึ้น
        cropped = img.copyResize(
          cropped,
          width: max(cropped.width * 2, 128),
          height: max(cropped.height * 2, 128),
          interpolation: img.Interpolation.cubic,
        );

        // 🎯 แปลงเป็นขาวดำ (Grayscale)
        cropped = img.grayscale(cropped);

        // 🎯 ปรับ Contrast ให้ตัดกับพื้นหลัง
        cropped = img.adjustColor(cropped, contrast: 1.5);

        return Uint8List.fromList(img.encodeJpg(cropped, quality: 100));
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
    if (_digitPredictText != null) {
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
                'YOLO อ่านเลขได้:',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Text(
                _digitPredictText!,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 60,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_signNumberCropImage != null && !_isPredicting) {
      return Center(
        child: Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red[50],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: const Text(
            '⚠️ เจอป้ายตัวเลขแล้ว แต่โมเดลเลขยังอ่านไม่ออก',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool allReady = _isModelReady && _isDigitModelReady;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'ทดสอบ YOLO รูปภาพ',
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
            child: !allReady
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
                  // 1. ภาพต้นฉบับ (แสดงตลอดเมื่อเลือกรูป)
                  if (_imageBytes != null) ...[
                    const Text(
                      '📸 ภาพต้นฉบับ (ก่อนประมวลผล)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(height: 10),
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
                          Image.memory(_imageBytes!, fit: BoxFit.contain),
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
                  ],

                  // 2. ภาพที่ตีเส้นขอบเขตแล้ว (แสดงหลังประมวลผลเสร็จ)
                  if (_annotatedImage != null && !_isPredicting) ...[
                    const Text(
                      '🎯 ภาพหลังการตรวจจับป้ายจราจร (YOLO)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: Colors.indigo, width: 2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.memory(
                        _annotatedImage!,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // 3. ภาพขาวดำที่ครอบส่วนป้าย
                  if (_signNumberCropImage != null && !_isPredicting)
                    _buildPreviewCard(
                      title: '✂️ ภาพตัดเฉพาะป้ายตัวเลข',
                      subtitle: 'ภาพที่ส่งให้ YOLO โมเดลเลขอ่านต่อ (ขาวดำ)',
                      imageBytes: _signNumberCropImage!,
                      borderColor: Colors.orange,
                      height: 140,
                    ),

                  // 4. ผลลัพธ์ตัวเลข
                  _buildResultBox(),

                  const SizedBox(height: 10),

                  // 5. ป้ายกำกับสิ่งที่เจอทั้งหมด
                  if (_detections.isNotEmpty && !_isPredicting) ...[
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
