import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:trffic_ilght_app/core/models/models.dart';
import 'package:trffic_ilght_app/services/sign_number_pipeline_service.dart';
import 'package:trffic_ilght_app/services/yolo_result_adapter.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../../services/model_manager.dart';

@visibleForTesting
YOLO createSingleImageYolo(String modelPath) {
  return YOLO(
    modelPath: modelPath,
    task: YOLOTask.detect,
    useMultiInstance: true,
  );
}

class SingleImageScreen extends StatefulWidget {
  const SingleImageScreen({super.key});

  @override
  State<SingleImageScreen> createState() => _SingleImageScreenState();
}

class _SingleImageScreenState extends State<SingleImageScreen> {
  final ImagePicker _picker = ImagePicker();

  List<YOLOResult> _detections = [];

  Uint8List? _imageBytes;
  Uint8List? _annotatedImage;
  Uint8List? _signNumberCropImage;

  String? _digitPredictText;

  // โมเดลสำหรับตรวจป้ายจราจร
  YOLO? _trafficYolo;

  // โมเดลสำหรับตรวจตัวเลข 0–9
  YOLO? _digitYolo;

  // Service สำหรับ crop และตรวจตัวเลข
  SignNumberPipelineService? _signNumberService;

  late final ModelManager _modelManager;

  String? _trafficModelPath;
  String? _digitModelPath;

  bool _isModelsReady = false;
  bool _isPredicting = false;

  @override
  void initState() {
    super.initState();

    _modelManager = ModelManager();
    _initializeModels();
  }

  Future<void> _initializeModels() async {
    try {
      _trafficModelPath = await _modelManager.getModelPath(ModelType.traffic);

      _digitModelPath = await _modelManager.getModelPath(ModelType.number);

      debugPrint('Traffic model path: $_trafficModelPath');
      debugPrint('Digit model path: $_digitModelPath');

      if (_trafficModelPath == null || _digitModelPath == null) {
        _showSnackBar('ไม่พบไฟล์โมเดล');
        return;
      }

      final trafficYolo = await _loadYoloWithRollback(
        ModelType.traffic,
        _trafficModelPath!,
      );

      final digitYolo = await _loadYoloWithRollback(
        ModelType.number,
        _digitModelPath!,
      );

      if (!mounted) {
        await trafficYolo.dispose();
        await digitYolo.dispose();
        return;
      }

      _trafficYolo = trafficYolo;
      _digitYolo = digitYolo;

      _signNumberService = SignNumberPipelineService(digitYolo: digitYolo);

      setState(() {
        _isModelsReady = true;
      });
    } catch (e, stackTrace) {
      debugPrint('Model initialization error: $e');
      debugPrint('$stackTrace');

      if (!mounted) return;

      final error = YOLOErrorHandler.handleError(e, 'Failed to load models');

      _showSnackBar('Error loading models: ${error.message}');
    }
  }

  Future<YOLO> _loadYoloWithRollback(
    ModelType modelType,
    String initialPath,
  ) async {
    try {
      return await _loadYolo(initialPath);
    } catch (e) {
      debugPrint(
        'โหลดโมเดลไม่สำเร็จ '
        'modelType=$modelType path=$initialPath error=$e',
      );

      final replacement = await _modelManager.reportModelLoadFailure(
        modelType,
        failedPath: initialPath,
      );

      if (replacement == null || replacement == initialPath) {
        rethrow;
      }

      debugPrint('ลองโหลดโมเดลสำรอง: $replacement');

      return _loadYolo(replacement);
    }
  }

  Future<YOLO> _loadYolo(String modelPath) async {
    final yolo = createSingleImageYolo(modelPath);

    try {
      await yolo.loadModel();

      debugPrint('โหลดโมเดลสำเร็จ: $modelPath');

      return yolo;
    } catch (_) {
      await yolo.dispose();
      rethrow;
    }
  }

  Future<void> _pickAndPredict() async {
    final trafficYolo = _trafficYolo;
    final digitYolo = _digitYolo;
    final signNumberService = _signNumberService;

    if (!_isModelsReady ||
        trafficYolo == null ||
        digitYolo == null ||
        signNumberService == null) {
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
      // --------------------------------------------------
      // 1. ใช้ Traffic Model ตรวจจับป้ายจากภาพต้นฉบับ
      // --------------------------------------------------
      final trafficResult = await trafficYolo.predict(
        bytes,
        confidenceThreshold: 0.25,
        iouThreshold: 0.45,
      );

      debugPrint('Traffic result keys: ${trafficResult.keys}');

      debugPrint(
        'Raw traffic detections: '
        '${trafficResult['detections']}',
      );

      final parsedTrafficDetections = parseYoloDetections(
        trafficResult['detections'],
      );

      debugPrint(
        'Traffic detection count: '
        '${parsedTrafficDetections.length}',
      );

      for (final detection in parsedTrafficDetections) {
        debugPrint(
          'Traffic class=${detection.className}, '
          'confidence=${detection.confidence}, '
          'box=${detection.boundingBox}, '
          'normalized=${detection.normalizedBox}',
        );
      }

      final Uint8List? annotatedBytes =
          trafficResult['annotatedImage'] as Uint8List?;

      // --------------------------------------------------
      // 2. Crop sign_number และตรวจเลขด้วย pipeline เดียว
      // --------------------------------------------------
      // crop ที่คืนมาคือ byte ชุดเดียวกับที่ส่งเข้า Number model
      // จึงไม่เกิดความคลาดเคลื่อนจากการ crop ซ้ำคนละตำแหน่ง
      final signAnalysis = await signNumberService.analyzeSingleImage(
        frameBytes: bytes,
        detectionResults: parsedTrafficDetections,
      );

      final croppedSignBytes = signAnalysis.cropBytes;
      final foundNumber = signAnalysis.number;

      debugPrint(
        'Single-image result: '
        'sign=${signAnalysis.selectedSign?.confidence}, '
        'cropBytes=${croppedSignBytes?.length}, '
        'number=$foundNumber',
      );

      if (!mounted) return;

      setState(() {
        _detections = parsedTrafficDetections;
        _annotatedImage = annotatedBytes;
        _signNumberCropImage = croppedSignBytes;
        _digitPredictText = foundNumber;
      });
    } catch (e, stackTrace) {
      debugPrint('Predict error: $e');
      debugPrint('$stackTrace');

      if (mounted) {
        _showSnackBar('เกิดข้อผิดพลาด: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPredicting = false;
        });
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
      'sign_number': 'สัญญาณไฟนับถอยหลัง',
      'turn_left': 'เลี้ยวซ้าย',
      'turn_right': 'เลี้ยวขวา',
      'yellow_light': 'ไฟเหลือง',
    };

    return labels[className] ?? className;
  }

  void _showSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
            Image.memory(
              imageBytes,
              height: height,
              fit: BoxFit.contain,
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stackTrace) {
                    return const SizedBox(
                      height: 100,
                      child: Center(child: Text('ไม่สามารถแสดงภาพได้')),
                    );
                  },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultBox() {
    final String? number = _digitPredictText;

    if (number != null && number.isNotEmpty) {
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
                number,
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
            '⚠️ เจอสัญญาณไฟนับถอยหลัง '
            'แต่โมเดลเลขยังอ่านไม่ออก',
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
    unawaited(_trafficYolo?.dispose());
    unawaited(_digitYolo?.dispose());

    _signNumberService = null;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool allReady = _isModelsReady;

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
                  // -----------------------------------------
                  // 1. ภาพต้นฉบับ
                  // -----------------------------------------
                  if (_imageBytes != null) ...[
                    const Text(
                      '📸 ภาพต้นฉบับ '
                      '(ก่อนประมวลผล)',
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

                  // -----------------------------------------
                  // 2. ภาพผลตรวจจับ Traffic Model
                  // -----------------------------------------
                  if (_annotatedImage != null && !_isPredicting) ...[
                    const Text(
                      '🎯 ภาพหลังการตรวจจับ'
                      'ป้ายจราจร',
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

                  // -----------------------------------------
                  // 3. ภาพ crop ที่ส่งเข้า Number model
                  // -----------------------------------------
                  if (_signNumberCropImage != null && !_isPredicting)
                    _buildPreviewCard(
                      title: '✂️ ภาพตัดสัญญาณไฟนับถอยหลัง',
                      subtitle: 'ภาพขาวดำที่ขยายแล้วและส่งให้โมเดลเลขจริง',
                      imageBytes: _signNumberCropImage!,
                      borderColor: Colors.orange,
                      height: 140,
                    ),

                  // -----------------------------------------
                  // 4. ผลตัวเลข
                  // -----------------------------------------
                  _buildResultBox(),

                  const SizedBox(height: 10),

                  // -----------------------------------------
                  // 5. รายละเอียด Traffic detections
                  // -----------------------------------------
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
                      children: _detections.map((detection) {
                        final confidence = (detection.confidence * 100)
                            .toStringAsFixed(1);

                        return Chip(
                          label: Text(
                            '${_thaiLabel(detection.className)} ($confidence%)',
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
