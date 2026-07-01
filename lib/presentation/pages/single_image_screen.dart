import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

  late YOLO _digitYolo; // model สำหรับ detect digit 0-9
  late final ModelManager _modelManager;

  String? _digitModelPath;

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
      _digitModelPath = await _modelManager.getModelPath(
        ModelType.bestFloat16number,
      );

      if (_digitModelPath == null) {
        _showSnackBar('ไม่พบไฟล์โมเดลเลข');
        return;
      }

      _digitYolo = YOLO(modelPath: _digitModelPath!, task: YOLOTask.detect);
      await _digitYolo.loadModel();

      if (!mounted) return;
      setState(() {
        _isDigitModelReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      final error = YOLOErrorHandler.handleError(
        e,
        'Failed to load digit model: digit=$_digitModelPath',
      );
      _showSnackBar('Error loading digit model: ${error.message}');
    }
  }

  Future<void> _pickAndPredict() async {
    if (!_isDigitModelReady) {
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
      // 1) predict ตัวเลขจากภาพหลักโดยตรง (ไม่ตัดรูปตามคำขอ)
      // =========================================================
      final result = await _digitYolo.predict(bytes);
      final List<Map<String, dynamic>> parsedDetections =
          result['boxes'] is List
          ? MapConverter.convertBoxesList(result['boxes'] as List)
          : [];

      debugPrint('=== YOLO DIGIT DETECTION RESULTS ===');
      debugPrint('จำนวน detections: ${parsedDetections.length}');
      for (int i = 0; i < parsedDetections.length; i++) {
        final d = parsedDetections[i];
        debugPrint(
          'Detection $i => class=${d['className']} conf=${d['confidence']} '
          'box=(${d['x1']}, ${d['y1']}, ${d['x2']}, ${d['y2']})',
        );
      }
      debugPrint('==================================');

      // 🎯 กรองเอาเฉพาะตัวเลข 0-9
      final filtered = parsedDetections.where((d) {
        final cls = (d['className'] ?? d['class'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        return RegExp(r'^\d$').hasMatch(cls);
      }).toList();

      String? foundNumber;
      if (filtered.isNotEmpty) {
        // 🎯 เรียงจากซ้ายไปขวา
        filtered.sort((a, b) {
          final ax = (a['x1'] ?? 0).toDouble();
          final bx = (b['x1'] ?? 0).toDouble();
          return ax.compareTo(bx);
        });

        // นำมาต่อกัน
        foundNumber = filtered
            .map((d) => (d['className'] ?? '').toString())
            .join();
      }

      if (!mounted) return;

      setState(() {
        _detections = parsedDetections;
        _annotatedImage = result['annotatedImage'] as Uint8List?;
        _signNumberCropImage = null; // ไม่ตัดรูปภาพ
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
    final bool allReady = _isDigitModelReady;

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
