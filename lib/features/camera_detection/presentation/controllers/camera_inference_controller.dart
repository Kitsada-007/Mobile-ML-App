import 'dart:async';
import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trffic_ilght_app/shared/models/model_types.dart';
import 'package:trffic_ilght_app/features/camera_detection/data/models/realtime_inference.dart';
import 'package:trffic_ilght_app/core/utils/thai_number_helper.dart';
import 'package:trffic_ilght_app/core/services/inference/countdown_reading_stabilizer.dart';
import 'package:trffic_ilght_app/features/camera_detection/data/services/latest_frame_queue.dart';
import 'package:trffic_ilght_app/features/camera_detection/data/services/realtime_pipeline_monitor.dart';
import 'package:trffic_ilght_app/core/services/inference/number_detection_service.dart';
import 'package:trffic_ilght_app/features/camera_detection/data/services/realtime_number_inference_engine.dart';
import 'package:trffic_ilght_app/features/camera_detection/data/services/traffic_light_state_stabilizer.dart';
import 'package:trffic_ilght_app/core/services/voice/traffic_voice_service.dart';
import 'package:trffic_ilght_app/core/services/inference/sign_number_pipeline_service.dart';

import 'package:ultralytics_yolo/widgets/yolo_controller.dart';
import 'package:ultralytics_yolo/utils/error_handler.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_view.dart';

import 'package:trffic_ilght_app/core/services/model_management/model_manager.dart';

export 'package:trffic_ilght_app/features/camera_detection/data/models/realtime_inference.dart'
    show RealtimeInferenceDiagnostic;

String? acceptCountdownReading(String? reading) {
  final normalized = reading?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

const double realtimeSignConfidenceThreshold = 0.25;

double nativeRealtimeConfidenceThreshold(double selectedThreshold) =>
    selectedThreshold < realtimeSignConfidenceThreshold
    ? selectedThreshold
    : realtimeSignConfidenceThreshold;

double realtimeDetectionConfidenceThreshold(
  String className,
  double selectedThreshold,
) => className == 'sign_number'
    ? realtimeSignConfidenceThreshold
    : selectedThreshold;

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
  String? _detectedNumber;
  late final RealtimeNumberInferenceEngine _numberInferenceEngine;
  late final LatestFrameQueue<RealtimeFramePacket> _streamQueue;
  late final TrafficLightStateStabilizer _trafficLightStateStabilizer;
  late final RealtimeFrameFreshnessGuard _frameFreshnessGuard;
  late final RealtimePipelineMonitor _pipelineMonitor;
  late final DateTime Function() _clock;
  late final Duration _maximumFrameAge;
  late final bool _enableFreshnessWatchdog;
  Timer? _freshnessWatchdog;
  RealtimePipelineSnapshot _pipelineSnapshot =
      const RealtimePipelineSnapshot.empty();
  DateTime? _lastFreshFrameCapturedAt;
  bool _isRealtimePipelineStale = true;
  int _nextStreamSequence = 0;

  bool _hasSpokenGetReady = false;
  bool _hasSpokenInitialNumber = false;
  String? _lastSpokenNumber;
  bool _isSignCurrentlyVisible = false;
  DateTime? _lastSignSeenTime;

  bool _isDisposed = false;
  Future<void>? _loadingFuture;
  Future<void>? _modelRecoveryFuture;

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
  int get droppedStreamFrameCount => _streamQueue.droppedCount;
  List<RealtimeInferenceDiagnostic> get realtimeDiagnostics =>
      _numberInferenceEngine.diagnostics;
  Uint8List? get lastFailedNumberCropBytes =>
      _numberInferenceEngine.lastFailedCropBytes;
  bool get isDetectingNumber => _numberInferenceEngine.isDetecting;
  String? get confirmedTrafficLightClassName =>
      _trafficLightStateStabilizer.confirmedClassName;
  int? get activeTrafficLightTrackingId =>
      _trafficLightStateStabilizer.activeTrackingId;
  RealtimePipelineSnapshot get pipelineSnapshot => _pipelineSnapshot;
  bool get isRealtimePipelineStale => _isRealtimePipelineStale;

  // Getter สำหรับ List ภาษาไทย
  List<String> get detectedFormalNames => _detectedFormalNames;
  List<String> get detectedAlertMessages => _detectedAlertMessages;

  CameraInferenceController({
    @visibleForTesting SignNumberPipelineService? signNumberPipelineService,
    @visibleForTesting
    Duration numberDetectionInterval = const Duration(milliseconds: 400),
    @visibleForTesting CountdownReadingStabilizer? countdownStabilizer,
    @visibleForTesting TrafficLightStateStabilizer? trafficLightStateStabilizer,
    @visibleForTesting DateTime Function()? clock,
    @visibleForTesting
    Duration maximumFrameAge = defaultRealtimeMaximumFrameAge,
    @visibleForTesting bool enableFreshnessWatchdog = true,
  }) {
    _clock = clock ?? DateTime.now;
    _maximumFrameAge = maximumFrameAge;
    _enableFreshnessWatchdog = enableFreshnessWatchdog;
    _numberInferenceEngine = RealtimeNumberInferenceEngine(
      service: signNumberPipelineService,
      detectionInterval: numberDetectionInterval,
      stabilizer: countdownStabilizer,
      signConfidenceThreshold: realtimeSignConfidenceThreshold,
    );
    _streamQueue = LatestFrameQueue(processor: _processStreamPacket);
    _frameFreshnessGuard = RealtimeFrameFreshnessGuard(
      maximumFrameAge: maximumFrameAge,
    );
    _pipelineMonitor = RealtimePipelineMonitor();
    _trafficLightStateStabilizer =
        trafficLightStateStabilizer ?? TrafficLightStateStabilizer();
    _isFrontCamera = _lensFacing == LensFacing.front;

    _modelManager = ModelManager(
      onStatusUpdate: (message) {
        if (_isDisposed) return;
        _loadingMessage = message;
        notifyListeners();
      },
    );
  }

  Future<void> initialize() async {
    _startFreshnessWatchdog();

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
    if (_isDisposed) return;

    _yoloController.setThresholds(
      confidenceThreshold: nativeRealtimeConfidenceThreshold(
        _confidenceThreshold,
      ),
      iouThreshold: _iouThreshold,
      numItemsThreshold: _numItemsThreshold,
    );
  }

  void _startFreshnessWatchdog() {
    if (!_enableFreshnessWatchdog || _freshnessWatchdog != null) return;
    _freshnessWatchdog = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => expireStaleResults(),
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

      final numberDetectionService = NumberDetectionService(
        numberYolo: _digitYolo!,
      );
      _numberInferenceEngine.service = SignNumberPipelineService(
        numberDetectionService: numberDetectionService,
      );
    } catch (e) {
      if (_isDisposed) return;
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
      final yolo = YOLO(
        modelPath: path,
        task: modelType.task,
        useMultiInstance: true,
      );
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

  Future<void> onStreamingData(Map<String, dynamic> data) {
    if (_isDisposed) return Future.value();

    final packet = RealtimeFramePacket.fromMap(
      data,
      fallbackFrameNumber: ++_nextStreamSequence,
      receivedAt: _clock(),
    );
    return _streamQueue.submit(packet);
  }

  Future<void> _processStreamPacket(RealtimeFramePacket packet) async {
    if (_isDisposed) return;

    final processingStartedAt = _clock();
    final decision = _frameFreshnessGuard.evaluate(
      packet,
      now: processingStartedAt,
    );
    if (decision != RealtimeFrameDecision.accept) {
      _pipelineMonitor.recordRejected(decision);
      if (decision == RealtimeFrameDecision.stale) {
        _isRealtimePipelineStale = true;
        _clearRealtimeResults();
      }
      _refreshPipelineSnapshot(processingStartedAt);
      notifyListeners();
      return;
    }

    _lastFreshFrameCapturedAt = packet.estimatedCapturedAt;
    _isRealtimePipelineStale = false;

    final fps = packet.fps;
    if (fps != null) onPerformanceMetrics(fps);

    await onDetectionResults(
      packet.detections,
      timestamp: packet.estimatedCapturedAt,
    );
    if (_isDisposed) return;

    final stabilizedReading = await _numberInferenceEngine.process(
      packet,
      enabled: !_hasSpokenGetReady,
    );
    if (_isDisposed) return;

    final completedAt = _clock();
    _pipelineMonitor.recordProcessed(
      packet,
      processingStartedAt: processingStartedAt,
      completedAt: completedAt,
    );
    _refreshPipelineSnapshot(completedAt);

    if (packet.ageAt(completedAt) > _maximumFrameAge) {
      _isRealtimePipelineStale = true;
      _clearRealtimeResults();
    } else if (stabilizedReading != null) {
      _applyDetectedNumber(stabilizedReading);
    }
    notifyListeners();
  }

  void _refreshPipelineSnapshot(DateTime now) {
    _pipelineSnapshot = _pipelineMonitor.snapshot(
      droppedFrameCount: _streamQueue.droppedCount,
      now: now,
    );
  }

  @visibleForTesting
  void expireStaleResults({DateTime? now}) {
    if (_isDisposed) return;

    final checkedAt = now ?? _clock();
    final lastCapturedAt = _lastFreshFrameCapturedAt;
    if (lastCapturedAt == null ||
        checkedAt.difference(lastCapturedAt) <= _maximumFrameAge) {
      return;
    }
    if (_isRealtimePipelineStale) return;

    _isRealtimePipelineStale = true;
    _clearRealtimeResults();
    _refreshPipelineSnapshot(checkedAt);
    notifyListeners();
  }

  bool _clearRealtimeResults() {
    final changed =
        _detectionCount != 0 ||
        _detectedFormalNames.isNotEmpty ||
        _detectedAlertMessages.isNotEmpty ||
        _detectedNumber != null ||
        _trafficLightStateStabilizer.confirmedClassName != null;

    _detectionCount = 0;
    _detectedFormalNames = [];
    _detectedAlertMessages = [];
    _trafficLightStateStabilizer.reset();
    _resetSignState();
    return changed;
  }

  void _resetRealtimePipeline() {
    _frameFreshnessGuard.reset();
    _pipelineMonitor.reset();
    _pipelineSnapshot = const RealtimePipelineSnapshot.empty();
    _lastFreshFrameCapturedAt = null;
    _isRealtimePipelineStale = true;
  }

  void _applyDetectedNumber(String reading) {
    if (_isDisposed) return;

    _detectedNumber = reading;
    final value = int.tryParse(reading);
    if (value != null && value >= 1) {
      if (shouldPrepareToGo(value)) {
        if (!_hasSpokenGetReady) {
          _hasSpokenGetReady = true;
          _lastSpokenNumber = reading;
          unawaited(_voiceService.speakNumber(reading));
        }
      } else if (value <= 9) {
        if (_lastSpokenNumber != reading) {
          _lastSpokenNumber = reading;
          unawaited(_voiceService.speakNumber(reading));
        }
      } else if (!_hasSpokenInitialNumber) {
        _hasSpokenInitialNumber = true;
        _lastSpokenNumber = reading;
        unawaited(_voiceService.speakNumber(reading));
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
    _numberInferenceEngine.resetCycle();
  }

  // ==========================================
  // อัปเดต onDetectionResults เพื่อดึงทุก Class และแปลภาษาไทย
  // ==========================================
  Future<void> onDetectionResults(
    List<YOLOResult> results, {
    DateTime? timestamp,
  }) async {
    if (_isDisposed) return;

    bool shouldNotify = false;
    final observationTime = timestamp ?? _clock();

    final signNumberDetectedInThisFrame = results.any(
      (result) =>
          result.className == 'sign_number' &&
          result.confidence >= realtimeSignConfidenceThreshold,
    );
    final trafficLightUpdate = _trafficLightStateStabilizer.update(
      results
          .where(
            (result) =>
                isTrafficLightStateClass(result.className) &&
                result.confidence >=
                    realtimeDetectionConfidenceThreshold(
                      result.className,
                      _confidenceThreshold,
                    ),
          )
          .map((result) {
            final box = result.normalizedBox;
            return TrafficLightObservation(
              className: result.className,
              confidence: result.confidence,
              left: box.left,
              top: box.top,
              right: box.right,
              bottom: box.bottom,
            );
          }),
      timestamp: observationTime,
    );

    final confirmedTrafficLight = trafficLightUpdate.confirmedClassName;
    if (trafficLightUpdate.stateChanged && confirmedTrafficLight != null) {
      unawaited(
        _voiceService.processDetection(
          confirmedTrafficLight,
          1,
          isSignActive:
              signNumberDetectedInThisFrame || _isSignCurrentlyVisible,
          hasSpokenGetReady: _hasSpokenGetReady,
          announceImmediately: true,
        ),
      );
    }

    if (results.isNotEmpty) {
      // เรียงลำดับจากความมั่นใจมากไปน้อย
      results.sort((a, b) => b.confidence.compareTo(a.confidence));

      List<String> tempFormalNames = [];
      List<String> tempAlerts = [];

      for (var result in results) {
        final minimumConfidence = realtimeDetectionConfidenceThreshold(
          result.className,
          _confidenceThreshold,
        );
        if (result.confidence < minimumConfidence) continue;
        if (isTrafficLightStateClass(result.className)) continue;

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
          unawaited(
            _voiceService.processDetection(
              result.className,
              result.confidence,
              isSignActive:
                  signNumberDetectedInThisFrame || _isSignCurrentlyVisible,
              hasSpokenGetReady: _hasSpokenGetReady,
            ),
          );
        }
      }

      _appendConfirmedTrafficLight(
        confirmedTrafficLight,
        formalNames: tempFormalNames,
        alertMessages: tempAlerts,
      );

      // จัดการสถานะและเสียงสำหรับสัญญาณไฟนับถอยหลังในเฟรมนี้
      if (signNumberDetectedInThisFrame) {
        _lastSignSeenTime = observationTime;
        _isSignCurrentlyVisible = true;
      } else {
        if (_isSignCurrentlyVisible) {
          // Debounce Reset: ล้างสถานะเมื่อไม่พบป้ายติดต่อกันเกิน 1.5 วินาที
          final now = observationTime;
          final lastSeen = _lastSignSeenTime;
          if (lastSeen == null ||
              now.difference(lastSeen).inMilliseconds > 1500) {
            if (!_hasSpokenGetReady && _detectedNumber != null) {
              unawaited(_voiceService.speakNumber(_detectedNumber!));
            }
            _resetSignState();
          }
        }
      }

      // อัปเดต List หลักและแจ้ง UI เฉพาะเมื่อมีข้อมูลเปลี่ยนแปลง
      if (!listEquals(_detectedFormalNames, tempFormalNames) ||
          !listEquals(_detectedAlertMessages, tempAlerts)) {
        _detectedFormalNames = tempFormalNames;
        _detectedAlertMessages = tempAlerts;
        shouldNotify = true;
      }
    } else {
      // ถ้าไม่มีผลตรวจจับ ให้จัดการสัญญาณไฟนับถอยหลังก่อนหน้า (มีดีบาวน์)
      if (_isSignCurrentlyVisible) {
        final now = observationTime;
        final lastSeen = _lastSignSeenTime;
        if (lastSeen == null ||
            now.difference(lastSeen).inMilliseconds > 1500) {
          if (!_hasSpokenGetReady && _detectedNumber != null) {
            unawaited(_voiceService.speakNumber(_detectedNumber!));
          }
          _resetSignState();
        }
      }

      final tempFormalNames = <String>[];
      final tempAlerts = <String>[];
      _appendConfirmedTrafficLight(
        confirmedTrafficLight,
        formalNames: tempFormalNames,
        alertMessages: tempAlerts,
      );

      // คงสถานะไฟที่ track ไว้ระหว่างเฟรมหลุดสั้น ๆ และล้างเมื่อหมดเวลา
      if (!listEquals(_detectedFormalNames, tempFormalNames) ||
          !listEquals(_detectedAlertMessages, tempAlerts)) {
        _detectedFormalNames = tempFormalNames;
        _detectedAlertMessages = tempAlerts;
        shouldNotify = true;
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
      shouldNotify = true;
    }

    if (_detectionCount != results.length) {
      _detectionCount = results.length;
      shouldNotify = true;
    }

    if (shouldNotify) {
      notifyListeners();
    }
  }

  void _appendConfirmedTrafficLight(
    String? className, {
    required List<String> formalNames,
    required List<String> alertMessages,
  }) {
    if (className == null) return;

    final formalName = _voiceService.getFormalThaiName(className);
    if (formalNames.contains(formalName)) return;

    formalNames.add(formalName);
    alertMessages.add(_voiceService.getThaiMessage(className));
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
          _yoloController.setConfidenceThreshold(
            nativeRealtimeConfidenceThreshold(value),
          );
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

    _trafficLightStateStabilizer.reset();
    _resetRealtimePipeline();
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
      _trafficLightStateStabilizer.reset();
      _resetRealtimePipeline();
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
    _freshnessWatchdog?.cancel();
    _streamQueue.dispose();
    _numberInferenceEngine.dispose();
    _trafficLightStateStabilizer.reset();
    unawaited(_voiceService.stop());

    final digitYolo = _digitYolo;
    final runningStream = _streamQueue.running;
    if (digitYolo != null) {
      if (runningStream == null) {
        unawaited(digitYolo.dispose());
      } else {
        unawaited(runningStream.whenComplete(digitYolo.dispose));
      }
    }
    _yoloController.dispose();
    super.dispose();
  }
}
