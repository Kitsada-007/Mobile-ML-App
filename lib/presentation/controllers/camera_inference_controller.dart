import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/core/models/models.dart';
import 'package:trffic_ilght_app/services/traffic_voice_service.dart';
import 'package:trffic_ilght_app/services/sign_number_pipeline_service.dart';

import 'package:ultralytics_yolo/widgets/yolo_controller.dart';
import 'package:ultralytics_yolo/utils/error_handler.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_view.dart';

import '../../services/model_manager.dart';

class CameraInferenceController extends ChangeNotifier {
  int _detectionCount = 0;
  double _currentFps = 0.0;
  int _frameCount = 0;
  DateTime _lastFpsUpdate = DateTime.now();

  double _confidenceThreshold =
      0.5; // defult confidenceThreshold 0.5 and iouThreshold 0.45
  double _iouThreshold = 0.45;
  int _numItemsThreshold = 11;
  SliderType _activeSlider = SliderType.none;

  ModelType _selectedModel = ModelType.bestFloat16traffic;
  bool _isModelLoading = false;
  String? _modelPath;
  String _loadingMessage = '';
  double _downloadProgress = 0.0;

  double _currentZoomLevel = 1.0;
  LensFacing _lensFacing = LensFacing.back;
  bool _isFrontCamera = false;

  final _yoloController = YOLOViewController();
  final TrafficVoiceService _voiceService = TrafficVoiceService();
  late final ModelManager _modelManager;

  YOLO? _digitYolo;
  SignNumberPipelineService? _signNumberPipelineService;
  String? _detectedNumber;
  Uint8List? _latestFrameBytes;
  bool _isDetectingNumber = false;
  DateTime? _lastNumberDetectTime;

  bool _isDisposed = false;
  Future<void>? _loadingFuture;

  // ==========================================
  // อัปเดตตัวแปรเป็นแบบ List เพื่อรองรับหลาย Class พร้อมกัน
  // ==========================================
  List<String> _detectedFormalNames = [];
  List<String> _detectedAlertMessages = [];

  int get detectionCount => _detectionCount;
  double get currentFps => _currentFps;
  double get confidenceThreshold => _confidenceThreshold;
  double get iouThreshold => _iouThreshold;
  int get numItemsThreshold => _numItemsThreshold;
  SliderType get activeSlider => _activeSlider;
  ModelType get selectedModel => _selectedModel;
  bool get isModelLoading => _isModelLoading;
  String? get modelPath => _modelPath;
  String get loadingMessage => _loadingMessage;
  double get downloadProgress => _downloadProgress;
  double get currentZoomLevel => _currentZoomLevel;
  bool get isFrontCamera => _isFrontCamera;
  LensFacing get lensFacing => _lensFacing;
  YOLOViewController get yoloController => _yoloController;

  String? get detectedNumber => _detectedNumber;

  // Getter สำหรับ List ภาษาไทย
  List<String> get detectedFormalNames => _detectedFormalNames;
  List<String> get detectedAlertMessages => _detectedAlertMessages;

  CameraInferenceController() {
    _isFrontCamera = _lensFacing == LensFacing.front;

    _modelManager = ModelManager(
      onStatusUpdate: (message) {
        _loadingMessage = message;
        notifyListeners();
      },
    );
  }

  Future<void> initialize() async {
    await _loadModelForPlatform();
    await _loadDigitModel();

    _yoloController.setThresholds(
      confidenceThreshold: _confidenceThreshold,
      iouThreshold: _iouThreshold,
      numItemsThreshold: _numItemsThreshold,
    );
  }

  Future<void> _loadDigitModel() async {
    try {
      final digitModelPath = await _modelManager.getModelPath(
        ModelType.bestFloat16number,
      );

      if (digitModelPath == null) {
        throw Exception('Digit model path is null');
      }

      _digitYolo = YOLO(modelPath: digitModelPath, task: YOLOTask.detect);

      await _digitYolo!.loadModel();

      _signNumberPipelineService = SignNumberPipelineService(
        digitYolo: _digitYolo!,
      );
    } catch (e) {
      final error = YOLOErrorHandler.handleError(
        e,
        'Failed to load bestFloat16number model',
      );
      _loadingMessage = 'Digit model load failed: ${error.message}';
      notifyListeners();
    }
  }

  void updateLatestFrame(Uint8List frameBytes) {
    if (_isDisposed) return;
    _latestFrameBytes = frameBytes;
  }

  bool _canRunNumberDetection() {
    if (_lastNumberDetectTime == null) return true;
    return DateTime.now().difference(_lastNumberDetectTime!).inMilliseconds >
        700;
  }

  // ==========================================
  // อัปเดต onDetectionResults เพื่อดึงทุก Class และแปลภาษาไทย
  // ==========================================
  Future<void> onDetectionResults(List<YOLOResult> results) async {
    if (_isDisposed) return;

    if (results.isNotEmpty) {
      // เรียงลำดับจากความมั่นใจมากไปน้อย
      results.sort((a, b) => b.confidence.compareTo(a.confidence));

      List<String> tempFormalNames = [];
      List<String> tempAlerts = [];
      bool shouldNotify = false;

      for (var result in results) {
        // ข้าม Class ที่ความมั่นใจน้อยกว่าค่าที่ตั้งไว้ (เช่น น้อยกว่า 40%)
        if (result.confidence < 0.40) continue;

        // แปลงชื่อเป็นภาษาไทยผ่าน VoiceService
        final thaiFormalName = _voiceService.getFormalThaiName(
          result.className,
        );
        final thaiAlertMsg = _voiceService.getThaiMessage(result.className);

        // เก็บลง List เฉพาะชื่อที่ไม่ซ้ำกันในเฟรมเดียว
        if (!tempFormalNames.contains(thaiFormalName)) {
          tempFormalNames.add(thaiFormalName);
          tempAlerts.add(thaiAlertMsg);
        }

        if (result.className != 'sign_number') {
          // เรียกใช้งานเสียงพูดเตือน
          _voiceService.processDetection(result.className, result.confidence);
        } else {
          // ถ้าเป็นป้ายตัวเลข ให้ทำงานตรวจจับตัวเลขต่อ
          if (_latestFrameBytes != null &&
              _signNumberPipelineService != null &&
              !_isDetectingNumber &&
              _canRunNumberDetection()) {
            _isDetectingNumber = true;
            _lastNumberDetectTime = DateTime.now();

            try {
              final number = await _signNumberPipelineService!
                  .detectNumberFromSign(
                    frameBytes: _latestFrameBytes!,
                    detectionResults: results,
                  );

              if (_detectedNumber != number) {
                _detectedNumber = number;
                shouldNotify = true; // ตั้งแฟล็กเพื่อให้อัปเดต UI ตอนจบ
              }
            } catch (e) {
              log('Sign number pipeline error: $e');
            } finally {
              _isDetectingNumber = false;
            }
          }
        }
      }

      // อัปเดต List หลักและแจ้ง UI
      _detectedFormalNames = tempFormalNames;
      _detectedAlertMessages = tempAlerts;
      notifyListeners();
    } else {
      // ถ้าไม่มีผลตรวจจับเลย ให้ล้างหน้าจอ
      if (_detectedFormalNames.isNotEmpty) {
        _detectedFormalNames = [];
        _detectedAlertMessages = [];
        notifyListeners();
      }
    }

    // คำนวณ FPS ต่อตามปกติ
    _frameCount++;
    final now = DateTime.now();
    final elapsed = now.difference(_lastFpsUpdate).inMilliseconds;

    if (elapsed >= 1000) {
      _currentFps = _frameCount * 1000 / elapsed;
      _frameCount = 0;
      _lastFpsUpdate = now;
      notifyListeners();
    }

    if (_detectionCount != results.length) {
      _detectionCount = results.length;
      notifyListeners();
    }
  }

  void onPerformanceMetrics(double fps) {
    if (_isDisposed) return;

    if ((_currentFps - fps).abs() > 0.1) {
      _currentFps = fps;
      notifyListeners();
    }
  }

  void onZoomChanged(double zoomLevel) {
    if (_isDisposed) return;

    if ((_currentZoomLevel - zoomLevel).abs() > 0.01) {
      _currentZoomLevel = zoomLevel;
      notifyListeners();
    }
  }

  void toggleSlider(SliderType type) {
    if (_isDisposed) return;

    _activeSlider = _activeSlider == type ? SliderType.none : type;
    notifyListeners();
  }

  void updateSliderValue(double value) {
    if (_isDisposed) return;

    bool changed = false;
    switch (_activeSlider) {
      case SliderType.numItems:
        final newValue = value.toInt();
        if (_numItemsThreshold != newValue) {
          _numItemsThreshold = newValue;
          _yoloController.setNumItemsThreshold(_numItemsThreshold);
          changed = true;
        }
        break;

      case SliderType.confidence:
        if ((_confidenceThreshold - value).abs() > 0.01) {
          _confidenceThreshold = value;
          _yoloController.setConfidenceThreshold(value);
          changed = true;
        }
        break;

      case SliderType.iou:
        if ((_iouThreshold - value).abs() > 0.01) {
          _iouThreshold = value;
          _yoloController.setIoUThreshold(value);
          changed = true;
        }
        break;

      case SliderType.none:
        break;
    }

    if (changed) {
      notifyListeners();
    }
  }

  void setZoomLevel(double zoomLevel) {
    if (_isDisposed) return;

    if ((_currentZoomLevel - zoomLevel).abs() > 0.01) {
      _currentZoomLevel = zoomLevel;
      _yoloController.setZoomLevel(zoomLevel);
      notifyListeners();
    }
  }

  void flipCamera() {
    if (_isDisposed) return;

    _isFrontCamera = !_isFrontCamera;
    _lensFacing = _isFrontCamera ? LensFacing.front : LensFacing.back;

    if (_isFrontCamera) {
      _currentZoomLevel = 1.0;
    }

    _yoloController.switchCamera();
    notifyListeners();
  }

  void setLensFacing(LensFacing facing) {
    if (_isDisposed) return;

    if (_lensFacing != facing) {
      _lensFacing = facing;
      _isFrontCamera = facing == LensFacing.front;

      _yoloController.switchCamera();

      if (_isFrontCamera) {
        _currentZoomLevel = 1.0;
      }

      notifyListeners();
    }
  }

  Future<void> _loadModelForPlatform() async {
    if (_isDisposed) return;

    if (_loadingFuture != null) {
      await _loadingFuture;
      return;
    }

    _loadingFuture = _performModelLoading();
    try {
      await _loadingFuture;
    } finally {
      _loadingFuture = null;
    }
  }

  Future<void> _performModelLoading() async {
    if (_isDisposed) return;

    _isModelLoading = true;
    _loadingMessage = 'Loading ${_selectedModel.modelName} model...';
    _downloadProgress = 0.0;
    _detectionCount = 0;
    _currentFps = 0.0;
    _detectedNumber = null;
    notifyListeners();

    try {
      final modelPath = await _modelManager.getModelPath(_selectedModel);

      if (_isDisposed) return;

      _modelPath = modelPath;
      _isModelLoading = false;
      _loadingMessage = '';
      _downloadProgress = 0.0;
      notifyListeners();

      if (modelPath == null) {
        throw Exception('Failed to load ${_selectedModel.modelName} model');
      }
    } catch (e) {
      if (_isDisposed) return;

      final error = YOLOErrorHandler.handleError(
        e,
        'Failed to load model ${_selectedModel.modelName} for task ${_selectedModel.task.name}',
      );

      _isModelLoading = false;
      _loadingMessage = 'Failed to load model: ${error.message}';
      _downloadProgress = 0.0;
      notifyListeners();
      rethrow;
    }
  }

  @override
  void dispose() {
    _voiceService.stop();
    _isDisposed = true;
    super.dispose();
  }
}
