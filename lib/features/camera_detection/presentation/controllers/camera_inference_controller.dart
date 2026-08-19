import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:trffic_ilght_app/core/services/detection/detection_alert_config.dart';
import 'package:trffic_ilght_app/core/services/detection/detection_stabilizer.dart';
import 'package:trffic_ilght_app/core/services/detection/traffic_detection_label_formatter.dart';
import 'package:trffic_ilght_app/shared/models/model_types.dart';
import 'package:trffic_ilght_app/features/camera_detection/data/models/realtime_inference.dart';
import 'package:trffic_ilght_app/core/services/inference/countdown_reading_stabilizer.dart';
import 'package:trffic_ilght_app/core/services/inference/signal_interpreter.dart';
import 'package:trffic_ilght_app/features/camera_detection/data/services/latest_frame_queue.dart';
import 'package:trffic_ilght_app/features/camera_detection/data/services/realtime_pipeline_monitor.dart';
import 'package:trffic_ilght_app/core/services/inference/number_detection_service.dart';
import 'package:trffic_ilght_app/features/camera_detection/data/services/realtime_number_inference_engine.dart';
import 'package:trffic_ilght_app/core/services/voice/traffic_voice_service.dart';
import 'package:trffic_ilght_app/core/services/voice/voice_alert_controller.dart';
import 'package:trffic_ilght_app/core/services/inference/sign_number_pipeline_service.dart';

import 'package:ultralytics_yolo/widgets/yolo_controller.dart';
import 'package:ultralytics_yolo/utils/error_handler.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_view.dart';

import 'package:trffic_ilght_app/core/services/model_management/model_manager.dart';

export 'package:trffic_ilght_app/features/camera_detection/data/models/realtime_inference.dart'
    show RealtimeInferenceDiagnostic;

/// ค่า confidence threshold ขั้นต่ำสำหรับป้าย sign_number (ในโหมด realtime)
const double realtimeSignConfidenceThreshold = 0.25;

/// แปลง threshold ที่ผู้ใช้เลือกลงไปให้ YOLO native ใช้
/// - ค่าที่ผู้ใช้เลือกจะถูกฝังเป็นค่าที่สูงสุดเท่ากับ realtimeSignConfidenceThreshold
///   เพราะ native stream ต้องเห็นตั้งแต่ confidence ต่ำจึงจะปล่อยสัญญาณมาให้ฝั่ง Dart
double nativeRealtimeConfidenceThreshold(double selectedThreshold) {
  if (selectedThreshold < realtimeSignConfidenceThreshold) {
    return selectedThreshold;
  }
  return realtimeSignConfidenceThreshold;
}

class CameraInferenceController extends ChangeNotifier {
  int _detectionCount = 0;
  double _currentFps = 0.0;
  int _frameCount = 0;
  DateTime _lastFpsUpdate = DateTime.now();

  double _confidenceThreshold = 0.5;
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
  bool _isCameraEnabled = true;
  bool _isCameraSuspended = false; // กล้องถูกพักตามแอป/route lifecycle หรือไม่

  final _yoloController = YOLOViewController();
  late final TrafficVoiceService _voiceService;
  late final ModelManager _modelManager;

  YOLO? _digitYolo;
  String? _detectedNumber;
  late final RealtimeNumberInferenceEngine _numberInferenceEngine;
  late final LatestFrameQueue<RealtimeFramePacket> _streamQueue;
  late final DetectionStabilizer _detectionStabilizer;
  late final VoiceAlertController _voiceAlertController;
  static const DetectionAlertConfig _detectionConfig = DetectionAlertConfig();
  late final RealtimeFrameFreshnessGuard _frameFreshnessGuard;
  late final RealtimePipelineMonitor _pipelineMonitor;
  late final DateTime Function() _clock; // ฟังก์ชันเวลาที่แทรกได้ (เพื่อเทสต์)
  late final Duration _maximumFrameAge;
  late final bool _enableFreshnessWatchdog;
  Timer? _freshnessWatchdog;
  RealtimePipelineSnapshot _pipelineSnapshot =
      const RealtimePipelineSnapshot.empty();
  DateTime? _lastFreshFrameCapturedAt;
  bool _isRealtimePipelineStale = true;
  int _nextStreamSequence = 0;

  bool _isDisposed = false;
  Future<void>? _loadingFuture; // งานโหลดโมเดล (กันโหลดซ้ำซ้อน)
  Future<void>? _modelRecoveryFuture; // งานกู้คืนโมเดล (กันซ้ำซ้อน)

  List<String> _detectedFormalNames = [];
  List<String> _detectedAlertMessages = [];
  double? _lastDetectionConfidence; // confidence สูงสุดของการตรวจจับเฟรมล่าสุด

  /// ค่าว่างของแบนเนอร์คำสั่งคนขับ (ไม่มีสัญญาณ -> แผงซ่อนแบนเนอร์)
  static const DriverSignalResult _emptyDriverSignal = DriverSignalResult(
    message: '',
    action: SignalAction.none,
  );
  DriverSignalResult _driverSignalResult = _emptyDriverSignal;

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
  bool get isCameraEnabled => _isCameraEnabled;
  bool get isCameraSuspended => _isCameraSuspended;
  bool get isCameraActive => _isCameraEnabled && !_isCameraSuspended;
  LensFacing get lensFacing => _lensFacing;
  YOLOViewController get yoloController => _yoloController;

  String? get detectedNumber => _detectedNumber;
  int get droppedStreamFrameCount => _streamQueue.droppedCount;
  List<RealtimeInferenceDiagnostic> get realtimeDiagnostics =>
      _numberInferenceEngine.diagnostics;
  Uint8List? get lastFailedNumberCropBytes =>
      _numberInferenceEngine.lastFailedCropBytes;
  bool get isDetectingNumber => _numberInferenceEngine.isDetecting;
  String? get confirmedTrafficLightClassName {
    final trafficLights = _stableTrafficLights;
    if (trafficLights.isEmpty) {
      return null;
    }
    return trafficLights.first.className;
  }

  /// คลาสไฟจราจรเสถียรสำหรับ UI ป้ายนับถอยหลัง (เรียงตาม priority)
  String? get stableTrafficLightClassName {
    final lights = _detectionStabilizer.stableDetections
        .where(
          (detection) =>
              DetectionAlertConfig.trafficLightClasses.contains(
                detection.className,
              ) ||
              detection.className == 'turn_left' ||
              detection.className == 'turn_right' ||
              detection.className == 'go_straight_arrow',
        )
        .toList();
    lights.sort((first, second) {
      final firstPriority = _detectionConfig.ruleFor(first.className).priority;
      final secondPriority = _detectionConfig
          .ruleFor(second.className)
          .priority;
      return firstPriority.compareTo(secondPriority);
    });
    if (lights.isEmpty) {
      return null;
    }
    return lights.first.className;
  }

  int? get activeTrafficLightTrackingId {
    final trafficLights = _stableTrafficLights;
    if (trafficLights.isEmpty) {
      return null;
    }
    return trafficLights.first.trackId;
  }

  RealtimePipelineSnapshot get pipelineSnapshot => _pipelineSnapshot;
  bool get isRealtimePipelineStale => _isRealtimePipelineStale;

  List<String> get detectedFormalNames => _detectedFormalNames;
  List<String> get detectedAlertMessages => _detectedAlertMessages;
  double? get lastDetectionConfidence => _lastDetectionConfidence;

  /// แบนเนอร์คำสั่งคนขับ (เช่น "ไฟแดง - หยุดรอ") จาก [SignalInterpreter]
  DriverSignalResult get driverSignalResult => _driverSignalResult;

  bool get isVoiceEnabled => _voiceService.isEnabled;

  /// สลับเปิด/ปิดเสียงประกาศ (signature ตรงกับฝั่ง video controller)
  void toggleVoice() {
    _voiceService.setEnabled(!_voiceService.isEnabled);
    if (!_voiceService.isEnabled) {
      unawaited(_voiceService.stop());
    }
    notifyListeners();
  }

  /// สถานะการตรวจจับโดยรวม (ใช้แสดงใน UI แบบข้อความ)
  String get detectionStatus {
    if (!_isCameraEnabled) return 'กล้องปิดอยู่';
    if (_isModelLoading) {
      if (_loadingMessage.isEmpty) {
        return 'กำลังโหลดโมเดล';
      }
      return _loadingMessage;
    }
    if (_modelPath == null) {
      if (_loadingMessage.isEmpty) {
        return 'ไม่พบโมเดล';
      }
      return _loadingMessage;
    }
    if (_isRealtimePipelineStale) return 'กล้องไม่พร้อมหรือกำลังรอสัญญาณภาพ';
    if (_lastDetectionConfidence != null &&
        _lastDetectionConfidence! < _confidenceThreshold) {
      return 'ความมั่นใจต่ำ';
    }
    return 'กำลังตรวจจับ';
  }

  /// พารามิเตอร์ @visibleForTesting: ให้ฝังปลอม (fake) แทนของจริงเพื่อเขียนเทสต์
  CameraInferenceController({
    @visibleForTesting SignNumberPipelineService? signNumberPipelineService,
    @visibleForTesting
    Duration numberDetectionInterval = const Duration(milliseconds: 400),
    @visibleForTesting CountdownReadingStabilizer? countdownStabilizer,
    @visibleForTesting DetectionStabilizer? detectionStabilizer,
    // ไม่ใช่พารามิเตอร์สำหรับเทสต์อย่างเดียว: production ส่ง TrafficVoiceService
    // ตัวที่แชร์ทั้งแอปเข้ามา เพื่อให้ค่าเสียงจากหน้า Settings มีผลกับหน้ากล้องด้วย
    TrafficVoiceService? voiceService,
    @visibleForTesting VoiceAlertController? voiceAlertController,
    @visibleForTesting DateTime Function()? clock,
    @visibleForTesting
    Duration maximumFrameAge = defaultRealtimeMaximumFrameAge,
    @visibleForTesting bool enableFreshnessWatchdog = true,
    @visibleForTesting ModelManager? modelManager,
  }) {
    if (clock == null) {
      _clock = DateTime.now;
    } else {
      _clock = clock;
    }
    _maximumFrameAge = maximumFrameAge;
    _enableFreshnessWatchdog = enableFreshnessWatchdog;
    if (voiceService == null) {
      _voiceService = TrafficVoiceService();
    } else {
      _voiceService = voiceService;
    }
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
    if (detectionStabilizer == null) {
      _detectionStabilizer = DetectionStabilizer(config: _detectionConfig);
    } else {
      _detectionStabilizer = detectionStabilizer;
    }
    if (voiceAlertController == null) {
      _voiceAlertController = VoiceAlertController(
        config: _detectionConfig,
        speakClassName: _speakStableClass,
      );
    } else {
      _voiceAlertController = voiceAlertController;
    }
    _isFrontCamera = _lensFacing == LensFacing.front;

    if (modelManager == null) {
      _modelManager = ModelManager(
        onStatusUpdate: (message) {
          if (_isDisposed) return;
          _loadingMessage = message;
          notifyListeners();
        },
      );
    } else {
      _modelManager = modelManager;
    }
  }

  /// เริ่มต้นระบบ: เปิด watchdog + โหลดโมเดลทั้ง 2 ตัว
  ///
  /// ค่า threshold ไม่ได้อ่านเองจาก SharedPreferences แล้ว แต่รับผ่าน
  /// [applyDetectionSettings] ที่หน้าจอส่งมาจาก SettingsProvider เพื่อให้มีแหล่งความจริง
  /// แหล่งเดียว (ไม่งั้นค่าที่ผู้ใช้เพิ่งเปลี่ยนจะถูกค่าที่อ่านไว้ตอนเริ่มทับ)
  Future<void> initialize() async {
    _startFreshnessWatchdog();

    await _loadModelForPlatform();
    await _loadDigitModel();
    if (_isDisposed) return;

    // ตั้ง threshold ให้กับ YOLO (native) โดยค่าของ sign_number ถูกบังคับเป็นค่าต่ำสุด
    _yoloController.setThresholds(
      confidenceThreshold: nativeRealtimeConfidenceThreshold(
        _confidenceThreshold,
      ),
      iouThreshold: _iouThreshold,
      numItemsThreshold: _numItemsThreshold,
    );
  }

  /// รับค่า threshold จาก SettingsProvider มาใช้ทันที (ไม่ต้องรีสตาร์ทแอป)
  ///
  /// เรียกได้ตั้งแต่ก่อน YOLOView ผูกกับ native แล้ว เพราะ YOLOViewController
  /// จำค่าไว้และส่งซ้ำให้เองตอน platform view พร้อม
  void applyDetectionSettings({
    required double confidenceThreshold,
    required double iouThreshold,
    required int numItemsThreshold,
  }) {
    if (_isDisposed) return;

    bool changed = false;
    if ((_confidenceThreshold - confidenceThreshold).abs() > 0.001) {
      _confidenceThreshold = confidenceThreshold;
      changed = true;
    }
    if ((_iouThreshold - iouThreshold).abs() > 0.001) {
      _iouThreshold = iouThreshold;
      changed = true;
    }
    if (_numItemsThreshold != numItemsThreshold) {
      _numItemsThreshold = numItemsThreshold;
      changed = true;
    }
    if (!changed) return;

    // ค่าของ sign_number ถูกบังคับเป็นค่าต่ำสุดเหมือนตอน initialize()
    _yoloController.setThresholds(
      confidenceThreshold: nativeRealtimeConfidenceThreshold(
        _confidenceThreshold,
      ),
      iouThreshold: _iouThreshold,
      numItemsThreshold: _numItemsThreshold,
    );
    notifyListeners();
  }

  /// เริ่ม Timer (watchdog) ที่คอยเรียก expireStaleResults ทุก 200ms
  void _startFreshnessWatchdog() {
    if (!_enableFreshnessWatchdog || _freshnessWatchdog != null) return;
    _freshnessWatchdog = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => expireStaleResults(),
    );
  }

  /// โหลดโมเดลตัวเลข (with rollback)
  Future<void> _loadDigitModel() async {
    try {
      final digitYolo = await _loadYoloWithRollback(ModelType.number);
      if (_isDisposed) {
        await digitYolo.dispose(); // โหลดเสร็จแต่ถูก dispose ไปก่อน -> ปล่อย
        return;
      }
      final oldDigitYolo = _digitYolo;
      _digitYolo = digitYolo;
      await oldDigitYolo?.dispose();

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

  /// โหลด YOLO พร้อม rollback: ถ้า path แรกโหลดไม่ได้ ขอ path ทดแทนจาก ModelManager
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
        await yolo.dispose(); // โหลดไม่สำเร็จ -> ปล่อย instance
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

  /// จัดการ error จากโมเดลไฟจราจรที่รายงานมาจาก YOLOView
  Future<void> onModelLoadError(Object error, String failedPath) async {
    if (_isDisposed || failedPath != _modelPath) {
      return;
    }

    final running = _modelRecoveryFuture;
    if (running != null) {
      await running; // กันซ้ำซ้อนถ้ามีงานกู้คืนกำลังทำงานอยู่
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

  /// กู้คืนโมเดลไฟจราจร: ขอ path ทดแทนจาก ModelManager
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

  // รับ output model: ฟังก์ชันที่ YOLOView เรียกเมื่อมีผลเฟรมสตรีมสดจากกล้อง
  Future<void> onStreamingData(Map<String, dynamic> data) {
    if (_isDisposed || !isCameraActive) {
      return Future.value();
    }

    final packet = RealtimeFramePacket.fromMap(
      data,
      fallbackFrameNumber: ++_nextStreamSequence,
      receivedAt: _clock(),
    );
    return _streamQueue.submit(packet);
  }

  /// สลับเปิด/ปิดกล้อง (pause/resume ย่อมส่งผลให้หยุดรับสตรีม)
  Future<void> toggleCamera() async {
    if (_isDisposed || _modelPath == null) return;
    final nextEnabled = !_isCameraEnabled;

    // ตั้ง state และแจ้ง UI ให้เสร็จก่อนสั่ง native เสมอ
    // - ตอนปิด: isCameraActive เป็น false ทันที เฟรมที่ยังค้างในท่อจะถูก
    //   onStreamingData ปฏิเสธตั้งแต่ต้น ไม่ต้องรอ pause() ให้เสร็จก่อน
    // - ตอนเปิด: widget ได้ rebuild ให้ YOLOView พร้อมก่อนที่ resume() จะยิงถึง
    _isCameraEnabled = nextEnabled;
    _resetDetectionSession();
    // ต้องรีเซ็ต guard/monitor ด้วย ไม่ใช่แค่ตั้ง flag:
    // กล้อง native เริ่มนับ frameNumber ใหม่หลัง resume ถ้าไม่ล้างเลขเฟรมล่าสุด
    // เฟรมชุดใหม่จะถูกตัดเป็น outOfOrder ทั้งหมดจนกว่าจะเลยเลขเดิม
    _resetRealtimePipeline();
    notifyListeners();

    try {
      if (nextEnabled) {
        // ถูกพักด้วย route/app lifecycle อยู่ -> ยังไม่ต้อง resume
        // resumeCamera() จะสั่งให้เองเมื่อกลับมาที่หน้านี้
        if (_isCameraSuspended) return;
        await _yoloController.resume();
      } else {
        await _yoloController.pause();
      }
    } catch (error) {
      if (_isDisposed) return;

      String failureMessage;
      if (nextEnabled) {
        failureMessage = 'ไม่สามารถเปิดกล้องได้: $error';
      } else {
        failureMessage = 'ไม่สามารถปิดกล้องได้: $error';
      }

      // native ปฏิเสธคำสั่ง -> ย้อน flag กลับให้ตรงกับความจริง
      // ข้ามการย้อนถ้าผู้ใช้กดสลับซ้ำระหว่างรอ await (state ไม่ใช่ของรอบนี้แล้ว)
      if (_isCameraEnabled == nextEnabled) {
        _isCameraEnabled = !nextEnabled;
      }
      _loadingMessage = failureMessage;
      notifyListeners();
    }
  }

  /// หยุดกล้องเมื่อหน้าไม่แสดง โดยไม่เปลี่ยนค่าปุ่มเปิด/ปิดที่ผู้ใช้เลือกไว้
  Future<void> pauseCamera() async {
    if (_isDisposed || _isCameraSuspended) return;

    _isCameraSuspended = true;
    _resetDetectionSession();
    _resetRealtimePipeline();
    notifyListeners();
    await _yoloController.pause();
  }

  /// เปิดกล้องต่อเมื่อกลับมาที่หน้าเดิม เฉพาะกรณีที่ผู้ใช้ไม่ได้ปิดกล้องไว้
  Future<void> resumeCamera() async {
    if (_isDisposed || !_isCameraSuspended) return;

    _isCameraSuspended = false;
    _resetDetectionSession();
    _resetRealtimePipeline();
    notifyListeners();
    if (_isCameraEnabled) {
      await _yoloController.resume();
    }
  }

  /// ประมวลผลเฟรม 1 แพ็กเก็ตจากคิว (เรียกแบบ serial โดย LatestFrameQueue)
  Future<void> _processStreamPacket(RealtimeFramePacket packet) async {
    if (_isDisposed || !isCameraActive) return;

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

    // อ่านเลขจาก raw frame ต่อได้ แต่แสดงเมื่อ sign_number ผ่าน temporal smoothing แล้ว
    final stabilizedReading = await _numberInferenceEngine.process(
      packet,
      enabled: true,
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

  /// อัปเดตสแนปช็อตสถิติ pipeline จาก monitor
  void _refreshPipelineSnapshot(DateTime now) {
    _pipelineSnapshot = _pipelineMonitor.snapshot(
      droppedFrameCount: _streamQueue.droppedCount,
      now: now,
    );
  }

  /// เช็คว่าเฟรมล่าสุดเก่าเกินไปหรือยัง (ถูกเรียกจาก watchdog ทุก 200ms)
  @visibleForTesting
  void expireStaleResults({DateTime? now}) {
    if (_isDisposed) return;

    DateTime checkedAt;
    if (now == null) {
      checkedAt = _clock();
    } else {
      checkedAt = now;
    }
    final lastCapturedAt = _lastFreshFrameCapturedAt;
    if (lastCapturedAt == null ||
        checkedAt.difference(lastCapturedAt) <= _maximumFrameAge) {
      return;
    }
    if (_isRealtimePipelineStale) return; // ล้าสมัยอยู่แล้ว -> ไม่ต้องทำซ้ำ

    _isRealtimePipelineStale = true;
    _clearRealtimeResults();
    _refreshPipelineSnapshot(checkedAt);
    notifyListeners();
  }

  /// ล้างผลลัพธ์เรียลไทม์ทั้งหมด (คืนค่าว่ามีอะไรเปลี่ยนไปบ้าง)
  bool _clearRealtimeResults() {
    final changed =
        _detectionCount != 0 ||
        _detectedFormalNames.isNotEmpty ||
        _detectedAlertMessages.isNotEmpty ||
        _detectedNumber != null ||
        _lastDetectionConfidence != null ||
        _driverSignalResult != _emptyDriverSignal ||
        _detectionStabilizer.stableDetections.isNotEmpty;

    _detectionCount = 0;
    _detectedFormalNames = [];
    _detectedAlertMessages = [];
    // ค่า confidence ต้องหายไปพร้อมผลลัพธ์ ไม่งั้นชิป CONF ค้างค่าเก่าบนแผงที่ว่างแล้ว
    _lastDetectionConfidence = null;
    _resetDetectionSession(stopVoice: false);
    return changed;
  }

  /// รีเซ็ตสถานะ pipeline ทั้งหมด (ใช้เมื่อสลับกล้อง/เริ่มรอบใหม่)
  void _resetRealtimePipeline() {
    _frameFreshnessGuard.reset();
    _pipelineMonitor.reset();
    _pipelineSnapshot = const RealtimePipelineSnapshot.empty();
    _lastFreshFrameCapturedAt = null;
    _isRealtimePipelineStale = true;
    // เลขลำดับสำรองต้องเริ่มใหม่พร้อมกับ guard ที่ล้าง _lastAcceptedFrameNumber
    _nextStreamSequence = 0;
    // ค่า FPS ต้องล้างด้วย ไม่งั้นเลขเก่าค้างบนจอหลังปิดกล้อง
    // ทำให้เข้าใจผิดว่ากล้องยังทำงานอยู่ทั้งที่สตรีมหยุดแล้ว
    // _lastFpsUpdate สำคัญไม่แพ้กัน: ถ้าไม่รีเซ็ต elapsed รอบแรกหลังเปิดใหม่
    // จะกลายเป็นค่ามหาศาล ทำให้ FPS ที่คำนวณได้เพี้ยนไปเลย
    _currentFps = 0.0;
    _frameCount = 0;
    _lastFpsUpdate = DateTime.now();
  }

  /// เลขใช้สำหรับ UI เท่านั้น ส่วนเสียง sign_number มาจาก stable detected event
  void _applyDetectedNumber(String reading) {
    if (_isDisposed) return;
    _detectedNumber = reading;
    notifyListeners();
  }

  void _resetDetectionSession({bool stopVoice = true}) {
    _detectionStabilizer.reset();
    _voiceAlertController.reset();
    _detectedNumber = null;
    // แบนเนอร์คำสั่งคนขับผูกกับผล stable -> รีเซ็ต stabilizer แล้วต้องล้างด้วย
    _driverSignalResult = _emptyDriverSignal;
    _numberInferenceEngine.resetCycle();
    if (stopVoice) unawaited(_voiceService.stop());
  }

  /// รับผลการตรวจจับจากกล้อง (ผลรายเฟรม) แล้วประมวลผลเป็นขั้น:
  /// - แยก raw boxes ออกจากผล stable ที่ผ่าน tracking และ temporal smoothing
  /// - แปลชื่อคลาส stable เป็นภาษาไทย + สร้างข้อความแจ้งเตือน
  /// - ส่งเฉพาะ detected/changed event เข้าระบบเสียง
  /// - อัปเดต FPS และจำนวนการตรวจจับ
  Future<void> onDetectionResults(
    List<YOLOResult> results, {
    DateTime? timestamp,
  }) async {
    if (_isDisposed || !isCameraActive) return;

    var shouldNotify = false;
    DateTime observationTime;
    if (timestamp == null) {
      observationTime = _clock();
    } else {
      observationTime = timestamp;
    }
    final qualifiedDetections = results.where((result) {
      double threshold;
      if (result.className == 'sign_number') {
        threshold = realtimeSignConfidenceThreshold;
      } else {
        threshold = _confidenceThreshold;
      }
      return result.confidence >= threshold;
    });
    final stabilization = _detectionStabilizer.update(
      qualifiedDetections,
      timestamp: observationTime,
    );
    final stableDetections = List<StableDetection>.from(
      stabilization.stableDetections,
    );
    stableDetections.sort((first, second) {
      final firstPriority = _detectionConfig.ruleFor(first.className).priority;
      final secondPriority = _detectionConfig
          .ruleFor(second.className)
          .priority;
      final priorityOrder = firstPriority.compareTo(secondPriority);
      if (priorityOrder != 0) {
        return priorityOrder;
      }
      return second.confidence.compareTo(first.confidence);
    });

    if (stabilization.events.any(
      (event) =>
          event.type != DetectionEventType.lost &&
          (event.detection.className == 'green_light_circle' ||
              event.detection.className == 'green_light'),
    )) {
      // Allowed: numbers will be detected and shown in green color
    }

    // ตีความผล stable เป็นคำสั่งคนขับ (แดง ⇒ หยุดเสมอ อยู่ใน SignalInterpreter)
    final driverSignal = SignalInterpreter.interpret(
      stableDetections
          .map((detection) => detection.toYoloResult())
          .toList(growable: false),
    );
    if (_driverSignalResult != driverSignal) {
      _driverSignalResult = driverSignal;
      shouldNotify = true;
    }

    final formalNames = <String>[];
    final alertMessages = <String>[];
    for (final detection in stableDetections) {
      final formalName = videoFormalThaiName(detection.className);
      if (formalNames.contains(formalName)) continue;
      formalNames.add(formalName);
      alertMessages.add(_voiceService.getThaiMessage(detection.className));
    }
    final stableConfidences = stableDetections.map(
      (detection) => detection.confidence,
    );
    double? stableConfidence;
    if (stableDetections.isEmpty) {
      stableConfidence = null;
    } else {
      stableConfidence = stableConfidences.reduce((first, second) {
        if (first > second) {
          return first;
        }
        return second;
      });
    }

    if (!listEquals(_detectedFormalNames, formalNames) ||
        !listEquals(_detectedAlertMessages, alertMessages) ||
        _lastDetectionConfidence != stableConfidence) {
      _detectedFormalNames = formalNames;
      _detectedAlertMessages = alertMessages;
      _lastDetectionConfidence = stableConfidence;
      shouldNotify = true;
    }

    // ผู้ใช้ปิดเสียงใน settings แล้วต้องไม่พูด (เหมือนที่ video controller ทำ)
    final shouldAnnounce = _voiceService.isEnabled;
    if (shouldAnnounce) {
      unawaited(_voiceAlertController.handleEvents(stabilization.events));
    }

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

  List<StableDetection> get _stableTrafficLights {
    final trafficLights = _detectionStabilizer.stableDetections
        .where(
          (detection) => DetectionAlertConfig.trafficLightClasses.contains(
            detection.className,
          ),
        )
        .toList();
    trafficLights.sort((first, second) {
      final firstPriority = _detectionConfig.ruleFor(first.className).priority;
      final secondPriority = _detectionConfig
          .ruleFor(second.className)
          .priority;
      return firstPriority.compareTo(secondPriority);
    });
    return trafficLights;
  }

  Future<void> _speakStableClass(String className) {
    final formalName = videoFormalThaiName(className);
    final alertMessage = _voiceService.getThaiMessage(className);
    String message;
    if (alertMessage.isEmpty) {
      message = formalName;
    } else {
      message = '$formalName: $alertMessage';
    }
    return _voiceService.speak(message);
  }

  /// รับการแจ้ง FPS จากกล้อง (ใช้ก็ต่อเมื่อค่าเปลี่ยนจริง)
  void onPerformanceMetrics(double fps) {
    if (_isDisposed) return;

    if ((_currentFps - fps).abs() > 0.1) {
      _currentFps = fps;
      notifyListeners();
    }
  }

  /// รับการแจ้ง zoom เปลี่ยนจากกล้อง
  void onZoomChanged(double zoomLevel) {
    if (_isDisposed) return;

    if ((_currentZoomLevel - zoomLevel).abs() > 0.01) {
      _currentZoomLevel = zoomLevel;
      notifyListeners();
    }
  }

  /// สลับแสดง/ซ่อน slider (กดปุ่มเดิมอีกครั้ง = ปิด)
  void toggleSlider(SliderType type) {
    if (_isDisposed) return;

    if (_activeSlider == type) {
      _activeSlider = SliderType.none;
    } else {
      _activeSlider = type;
    }
    notifyListeners();
  }

  /// อัปเดตค่าจาก slider ที่กำลังแสดงอยู่ แล้วส่งต่อไปยัง YOLO
  ///
  /// มีผลเฉพาะรอบการใช้งานนี้ ไม่บันทึกลง SharedPreferences เอง เพราะการบันทึกเป็น
  /// หน้าที่ของ SettingsProvider ที่เดียว (เขียนสองที่แล้วค่าจะไม่ตรงกัน)
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
          // ส่งค่าแบบ native-friendly (sign_number ถูกบังคับต่ำสุดไว้)
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
        }
        break;

      case SliderType.none:
        break;
    }

    if (changed) {
      notifyListeners();
    }
  }

  /// ตั้งระดับ zoom (ผู้ใช้เลื่อน)
  void setZoomLevel(double zoomLevel) {
    if (_isDisposed) return;

    if ((_currentZoomLevel - zoomLevel).abs() > 0.01) {
      _currentZoomLevel = zoomLevel;
      _yoloController.setZoomLevel(zoomLevel);
      notifyListeners();
    }
  }

  /// สลับกล้องหน้า/หลัง โดยรีเซ็ตสถานะ pipeline และการ track ไฟก่อน
  void flipCamera() {
    if (_isDisposed) return;

    _resetDetectionSession();
    _resetRealtimePipeline();
    _isFrontCamera = !_isFrontCamera;
    if (_isFrontCamera) {
      _lensFacing = LensFacing.front;
    } else {
      _lensFacing = LensFacing.back;
    }

    if (_isFrontCamera) {
      _currentZoomLevel = 1.0;
    }

    _yoloController.switchCamera();
    notifyListeners();
  }

  /// กำหนดทิศทางกล้อง (front/back) ตรง ๆ
  void setLensFacing(LensFacing facing) {
    if (_isDisposed) return;

    if (_lensFacing != facing) {
      _resetDetectionSession();
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

  /// โหลดโมเดลไฟจราจรตามแพลตฟอร์ม (กันการโหลดซ้ำซ้อนด้วย _loadingFuture)
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

  /// ขั้นตอนจริงของการโหลดโมเดลไฟจราจร (รับ path + รีเซ็ตสถานะ)
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
      rethrow; // ให้ผู้เรียก (เช่นหน้า page) จับ error ไปแสดง
    }
  }

  /// ปล่อยทรัพยากรทั้งหมดเมื่อ controller ถูก dispose
  @override
  void dispose() {
    _isDisposed = true; // ปิด flag กันงาน async ดำเนินต่อหลังปิด
    _freshnessWatchdog?.cancel();
    _streamQueue.dispose();
    _resetDetectionSession();
    _numberInferenceEngine.dispose();

    final digitYolo = _digitYolo;
    final runningStream = _streamQueue.running;
    if (digitYolo != null) {
      // ปล่อยโมเดลตัวเลข (รอคิวที่กำลังรันเสร็จก่อน ถ้ามี)
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
