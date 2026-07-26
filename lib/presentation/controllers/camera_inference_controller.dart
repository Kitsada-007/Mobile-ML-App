import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trffic_ilght_app/core/models/models.dart';
import 'package:trffic_ilght_app/core/utils/thai_number_helper.dart';
import 'package:trffic_ilght_app/services/traffic_voice_service.dart';
import 'package:trffic_ilght_app/services/sign_number_pipeline_service.dart';
import 'package:trffic_ilght_app/services/yolo_result_adapter.dart';

import 'package:ultralytics_yolo/widgets/yolo_controller.dart';
import 'package:ultralytics_yolo/utils/error_handler.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_view.dart';

import '../../services/model_manager.dart';

String? acceptCountdownReading(String? reading) {
  final normalized = reading?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

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

  final ModelType _selectedModel = ModelType.traffic;
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
  bool _isDetectingNumber = false;
  DateTime? _lastNumberDetectTime;

  bool _hasSpokenGetReady = false;
  bool _hasSpokenInitialNumber = false;
  String? _lastSpokenNumber;
  bool _isSignCurrentlyVisible = false;
  DateTime? _lastSignSeenTime;

  bool _isDisposed = false;
  Future<void>? _loadingFuture;
  Future<void>? _modelRecoveryFuture;

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
    try {
      final prefs = await SharedPreferences.getInstance();
      _iouThreshold = prefs.getDouble('iouThreshold') ?? 0.45;
      _confidenceThreshold = prefs.getDouble('confidenceThreshold') ?? 0.5;
      _numItemsThreshold = prefs.getInt('numItemsThreshold') ?? 11;
    } catch (e) {
      log('Failed to load thresholds from SharedPreferences: $e');
    }

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
      final digitYolo = await _loadYoloWithRollback(ModelType.number);
      if (_isDisposed) {
        await digitYolo.dispose();
        return;
      }
      _digitYolo = digitYolo;

      _signNumberPipelineService = SignNumberPipelineService(
        digitYolo: _digitYolo!,
      );
    } catch (e) {
      final error = YOLOErrorHandler.handleError(
        e,
        'Failed to load number model',
      );
      _loadingMessage = 'Digit model load failed: ${error.message}';
      notifyListeners();
    }
  }

  Future<YOLO> _loadYoloWithRollback(ModelType modelType) async {
    final initialPath = await _modelManager.getModelPath(modelType);
    if (initialPath == null) {
      throw StateError('${modelType.remoteId} model path is null');
    }

    Future<YOLO> load(String path) async {
      final yolo = YOLO(modelPath: path, task: modelType.task);
      try {
        await yolo.loadModel();
        return yolo;
      } catch (_) {
        await yolo.dispose();
        rethrow;
      }
    }

    try {
      return await load(initialPath);
    } catch (_) {
      final replacement = await _modelManager.reportModelLoadFailure(
        modelType,
        failedPath: initialPath,
      );
      if (replacement == null || replacement == initialPath) rethrow;
      return load(replacement);
    }
  }

  Future<void> onModelLoadError(Object error, String failedPath) async {
    if (_isDisposed || failedPath != _modelPath) return;

    final running = _modelRecoveryFuture;
    if (running != null) {
      await running;
      return;
    }

    final recovery = _recoverTrafficModel(error, failedPath);
    _modelRecoveryFuture = recovery;
    try {
      await recovery;
    } finally {
      if (identical(_modelRecoveryFuture, recovery)) {
        _modelRecoveryFuture = null;
      }
    }
  }

  Future<void> _recoverTrafficModel(Object error, String failedPath) async {
    _isModelLoading = true;
    _loadingMessage = 'โมเดลใหม่ใช้งานไม่ได้ กำลังย้อนกลับ...';
    notifyListeners();

    final replacement = await _modelManager.reportModelLoadFailure(
      _selectedModel,
      failedPath: failedPath,
    );
    if (_isDisposed) return;

    _isModelLoading = false;
    if (replacement == null || replacement == failedPath) {
      _loadingMessage = 'Failed to recover model: $error';
    } else {
      _modelPath = replacement;
      _loadingMessage = '';
    }
    notifyListeners();
  }

  Future<void> onStreamingData(Map<String, dynamic> data) async {
    if (_isDisposed) return;

    if (data.containsKey('detections')) {
      await onDetectionResults(parseYoloDetections(data['detections']));
    }

    final fps = data['fps'];
    if (fps is num) {
      onPerformanceMetrics(fps.toDouble());
    }

    final frameBytes = data['originalImage'];
    if (frameBytes is Uint8List) {
      await _readNumberFromFrame(frameBytes);
    }
  }

  bool _canRunNumberDetection() {
    if (_lastNumberDetectTime == null) return true;
    return DateTime.now().difference(_lastNumberDetectTime!).inMilliseconds >=
        500;
  }

  Future<void> _readNumberFromFrame(Uint8List frameBytes) async {
    final service = _signNumberPipelineService;
    if (_isDisposed ||
        service == null ||
        _isDetectingNumber ||
        !_canRunNumberDetection() ||
        _hasSpokenGetReady) {
      return;
    }

    _isDetectingNumber = true;
    _lastNumberDetectTime = DateTime.now();

    try {
      final number = await service.detectNumberFromFrame(
        frameBytes: frameBytes,
      );
      final reading = acceptCountdownReading(number);
      if (reading != null && _isSignCurrentlyVisible) {
        _applyDetectedNumber(reading);
      }
    } catch (e) {
      log('Whole-frame number inference error: $e');
    } finally {
      _isDetectingNumber = false;
    }
  }

  void _applyDetectedNumber(String reading) {
    _detectedNumber = reading;
    final int? val = int.tryParse(reading);
    if (val != null && val >= 1) {
      if (shouldPrepareToGo(val)) {
        if (!_hasSpokenGetReady) {
          _hasSpokenGetReady = true;
          _lastSpokenNumber = reading;
          _voiceService.speakNumber(reading);
        }
      } else if (val <= 9) {
        if (_lastSpokenNumber != reading) {
          _lastSpokenNumber = reading;
          _voiceService.speakNumber(reading);
        }
      } else if (!_hasSpokenInitialNumber) {
        _hasSpokenInitialNumber = true;
        _lastSpokenNumber = reading;
        _voiceService.speakNumber(reading);
      }
    }
    notifyListeners();
  }

  void _resetSignState() {
    _detectedNumber = null;
    _lastSpokenNumber = null;
    _hasSpokenGetReady = false;
    _hasSpokenInitialNumber = false;
    _isSignCurrentlyVisible = false;
    _lastSignSeenTime = null;
  }

  // ==========================================
  // อัปเดต onDetectionResults เพื่อดึงทุก Class และแปลภาษาไทย
  // ==========================================
  Future<void> onDetectionResults(List<YOLOResult> results) async {
    if (_isDisposed) return;

    bool signNumberDetectedInThisFrame = false;

    if (results.isNotEmpty) {
      // เรียงลำดับจากความมั่นใจมากไปน้อย
      results.sort((a, b) => b.confidence.compareTo(a.confidence));

      // ตรวจสอบว่ามี sign_number ในผลลัพธ์ของเฟรมนี้หรือไม่
      signNumberDetectedInThisFrame = results.any(
        (r) => r.className == 'sign_number' && r.confidence >= 0.25,
      );

      List<String> tempFormalNames = [];
      List<String> tempAlerts = [];

      for (var result in results) {
        // ข้าม Class ที่ความมั่นใจน้อยกว่าค่าที่ตั้งไว้ (สำหรับ sign_number ใช้ 0.25 เพื่อจับใน real-time ง่ายขึ้น)
        final minConfidence = result.className == 'sign_number' ? 0.25 : 0.40;
        if (result.confidence < minConfidence) continue;

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
          // เรียกใช้งานเสียงพูดเตือน (ส่งข้อมูลว่ามี sign_number / getReady หรือไม่ เพื่อปรับ cooldown และไม่พูดขัดกัน)
          _voiceService.processDetection(
            result.className,
            result.confidence,
            isSignActive:
                signNumberDetectedInThisFrame || _isSignCurrentlyVisible,
            hasSpokenGetReady: _hasSpokenGetReady,
          );
        } else {
          signNumberDetectedInThisFrame = true;
        }
      }

      // จัดการสถานะและเสียงสำหรับสัญญาณไฟนับถอยหลังในเฟรมนี้
      if (signNumberDetectedInThisFrame) {
        _lastSignSeenTime = DateTime.now();
        _isSignCurrentlyVisible = true;
      } else {
        if (_isSignCurrentlyVisible) {
          // Debounce Reset: ล้างสถานะเมื่อไม่พบป้ายติดต่อกันเกิน 1.5 วินาที
          final now = DateTime.now();
          final lastSeen = _lastSignSeenTime;
          if (lastSeen == null ||
              now.difference(lastSeen).inMilliseconds > 1500) {
            if (!_hasSpokenGetReady && _detectedNumber != null) {
              _voiceService.speakNumber(_detectedNumber!);
            }
            _resetSignState();
          }
        }
      }

      // อัปเดต List หลักและแจ้ง UI
      _detectedFormalNames = tempFormalNames;
      _detectedAlertMessages = tempAlerts;
      notifyListeners();
    } else {
      // ถ้าไม่มีผลตรวจจับ ให้จัดการสัญญาณไฟนับถอยหลังก่อนหน้า (มีดีบาวน์)
      if (_isSignCurrentlyVisible) {
        final now = DateTime.now();
        final lastSeen = _lastSignSeenTime;
        if (lastSeen == null ||
            now.difference(lastSeen).inMilliseconds > 1500) {
          if (!_hasSpokenGetReady && _detectedNumber != null) {
            _voiceService.speakNumber(_detectedNumber!);
          }
          _resetSignState();
        }
      }

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
          SharedPreferences.getInstance()
              .then((prefs) {
                prefs.setDouble('iouThreshold', value);
              })
              .catchError((e) {
                log('Failed to save iouThreshold to SharedPreferences: $e');
              });
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
    _isDisposed = true;
    _voiceService.stop();
    unawaited(_digitYolo?.dispose());
    _yoloController.dispose();
    super.dispose();
  }
}
