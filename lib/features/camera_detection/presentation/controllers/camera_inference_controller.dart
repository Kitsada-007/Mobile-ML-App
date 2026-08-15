import 'dart:async'; // ใช้ unawaited
import 'dart:developer'; // ใช้ log

import 'package:flutter/foundation.dart'; // ChangeNotifier + listEquals
import 'package:shared_preferences/shared_preferences.dart'; // เก็บค่า threshold ระหว่างเปิดปิดแอป
import 'package:trffic_ilght_app/core/services/detection/detection_alert_config.dart';
import 'package:trffic_ilght_app/core/services/detection/detection_stabilizer.dart';
import 'package:trffic_ilght_app/core/services/detection/traffic_detection_label_formatter.dart';
import 'package:trffic_ilght_app/shared/models/model_types.dart'; // ประเภทโมเดล (traffic/number)
import 'package:trffic_ilght_app/features/camera_detection/data/models/realtime_inference.dart'; // โครงสร้างเฟรมเรียลไทม์
import 'package:trffic_ilght_app/core/services/inference/countdown_reading_stabilizer.dart'; // กันเลขสั่นไหว
import 'package:trffic_ilght_app/core/services/inference/signal_interpreter.dart'; // ตีความผล stable เป็นคำสั่งคนขับ
import 'package:trffic_ilght_app/features/camera_detection/data/services/latest_frame_queue.dart'; // คิวเฟรมล่าสุด
import 'package:trffic_ilght_app/features/camera_detection/data/services/realtime_pipeline_monitor.dart'; // ติดตามสถิติ pipeline
import 'package:trffic_ilght_app/core/services/inference/number_detection_service.dart'; // บริการตรวจจับตัวเลข
import 'package:trffic_ilght_app/features/camera_detection/data/services/realtime_number_inference_engine.dart'; // อ่านเลขป้ายจากเฟรมสด
import 'package:trffic_ilght_app/core/services/voice/traffic_voice_service.dart'; // เสียงประกาศไทย
import 'package:trffic_ilght_app/core/services/voice/voice_alert_controller.dart';
import 'package:trffic_ilght_app/core/services/inference/sign_number_pipeline_service.dart'; // pipeline อ่านเลขป้าย

import 'package:ultralytics_yolo/widgets/yolo_controller.dart'; // ควบคุม YOLOView (กล้อง)
import 'package:ultralytics_yolo/utils/error_handler.dart'; // จัดการ error โมเดล
import 'package:ultralytics_yolo/yolo.dart'; // ชนิดข้อมูล YOLO
import 'package:ultralytics_yolo/yolo_view.dart'; // วิดเจ็ตกล้อง YOLO

import 'package:trffic_ilght_app/core/services/model_management/model_manager.dart'; // จัดการโมเดล

export 'package:trffic_ilght_app/features/camera_detection/data/models/realtime_inference.dart'
    show RealtimeInferenceDiagnostic;

/// ฟังก์ชันยอมรับตัวเลขนับถอยหลัง:
/// - ตัดช่องว่างหัว/ท้าย แล้วคืน null ถ้าเป็น string ว่าง (ตัวเลขไม่ผ่านการยอมรับ)
String? acceptCountdownReading(String? reading) {
  final normalized = reading?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

/// ค่า confidence threshold ขั้นต่ำสำหรับป้าย sign_number (ในโหมด realtime)
const double realtimeSignConfidenceThreshold = 0.25;

/// ผลการตัดสินสัญญาณไฟ: ไปได้ / หยุด / ระวัง / ไม่รู้
enum TrafficSignalVerdict { go, stop, caution, unknown }

/// แปลง threshold ที่ผู้ใช้เลือกลงไปให้ YOLO native ใช้
/// - ค่าที่ผู้ใช้เลือกจะถูกฝังเป็นค่าที่สูงสุดเท่ากับ realtimeSignConfidenceThreshold
///   เพราะ native stream ต้องเห็นตั้งแต่ confidence ต่ำจึงจะปล่อยสัญญาณมาให้ฝั่ง Dart
double nativeRealtimeConfidenceThreshold(double selectedThreshold) =>
    selectedThreshold < realtimeSignConfidenceThreshold
    ? selectedThreshold
    : realtimeSignConfidenceThreshold;

/// threshold ต่อคลาส: ป้าย sign_number ใช้ค่าคงที่ต่ำ (0.25) เสมอ
/// ส่วนไฟจราจรใช้ค่าที่ผู้ใช้เลือก
double realtimeDetectionConfidenceThreshold(
  String className,
  double selectedThreshold,
) => className == 'sign_number'
    ? realtimeSignConfidenceThreshold
    : selectedThreshold;

class CameraInferenceController extends ChangeNotifier {
  // ---- สถิติการตรวจจับ / FPS ----
  int _detectionCount = 0; // จำนวนวัตถุที่ตรวจพบในเฟรมล่าสุด
  double _currentFps = 0.0; // FPS ปัจจุบันที่ประมาณได้
  int _frameCount = 0; // ตัวนับเฟรม (สำหรับคำนวณ FPS)
  DateTime _lastFpsUpdate = DateTime.now(); // เวลาอัปเดต FPS ครั้งล่าสุด

  // ---- ค่า threshold ของโมเดล (ผู้ใช้ปรับได้ผ่าน slider) ----
  double _confidenceThreshold =
      0.5; // defult confidenceThreshold 0.5 and iouThreshold 0.45
  double _iouThreshold = 0.45;
  int _numItemsThreshold = 11;
  SliderType _activeSlider = SliderType.none; // slider ตัวไหนที่กำลังแสดงอยู่

  // ---- โมเดล ----
  final ModelType _selectedModel = ModelType.traffic; // โมเดลหลัก = ไฟจราจร
  bool _isModelLoading = false; // กำลังโหลดโมเดลอยู่ไหม
  String? _modelPath; // path ของโมเดลไฟจราจร
  String _loadingMessage = ''; // ข้อความสถานะการโหลด
  double _downloadProgress = 0.0; // ความคืบหน้าการโหลด (0-1)

  // ---- กล้อง ----
  double _currentZoomLevel = 1.0; // ระดับ zoom ปัจจุบัน
  LensFacing _lensFacing = LensFacing.back; // กล้องหลังเป็นค่าเริ่มต้น
  bool _isFrontCamera = false; // เปิดกล้องหน้ากล้องหรือไม่
  bool _isCameraEnabled = true; // กล้องเปิดอยู่หรือไม่
  bool _isCameraSuspended = false; // กล้องถูกพักตามแอป/route lifecycle หรือไม่

  final _yoloController = YOLOViewController(); // ควบคุม view กล้องของ YOLO
  late final TrafficVoiceService _voiceService; // เสียงประกาศ
  late final ModelManager _modelManager; // จัดการโมเดล

  // ---- ระบบเรียลไทม์ (เฟรมสตรีม) ----
  YOLO? _digitYolo; // ตัวโมเดลตัวเลข (สำหรับอ่านป้าย)
  String? _detectedNumber; // ตัวเลขนับถอยหลังที่ตรวจพบ
  late final RealtimeNumberInferenceEngine
  _numberInferenceEngine; // อ่านเลขจากเฟรม
  late final LatestFrameQueue<RealtimeFramePacket>
  _streamQueue; // คิวเฟรม (เก็บล่าสุด)
  late final DetectionStabilizer _detectionStabilizer;
  late final VoiceAlertController _voiceAlertController;
  static const DetectionAlertConfig _detectionConfig = DetectionAlertConfig();
  late final RealtimeFrameFreshnessGuard
  _frameFreshnessGuard; // กรองเฟรมเก่า/ไม่เรียง
  late final RealtimePipelineMonitor _pipelineMonitor; // ติดตามสถิติ pipeline
  late final DateTime Function() _clock; // ฟังก์ชันเวลาที่แทรกได้ (เพื่อเทสต์)
  late final Duration _maximumFrameAge; // อายุสูงสุดของเฟรม
  late final bool
  _enableFreshnessWatchdog; // เปิด watchdog เช็คเฟรมเก่าอัตโนมัติไหม
  Timer? _freshnessWatchdog; // Timer ที่คอยล้างผลลัพธ์ที่เก่าเกินไป
  RealtimePipelineSnapshot _pipelineSnapshot =
      const RealtimePipelineSnapshot.empty(); // สแนปช็อตล่าสุดของ pipeline
  DateTime? _lastFreshFrameCapturedAt; // เวลาจับภาพของเฟรมสดล่าสุด
  bool _isRealtimePipelineStale = true; // ข้อมูลเรียลไทม์ล้าสมัยหรือไม่
  int _nextStreamSequence = 0; // ตัวนับ sequence สำรองของเฟรม

  bool _isDisposed = false; // ถูก dispose แล้วหรือยัง
  Future<void>? _loadingFuture; // งานโหลดโมเดล (กันโหลดซ้ำซ้อน)
  Future<void>? _modelRecoveryFuture; // งานกู้คืนโมเดล (กันซ้ำซ้อน)

  // ---- ผลลัพธ์ที่แสดงกับผู้ใช้ (ภาษาไทย) ----
  List<String> _detectedFormalNames = []; // ชื่อไทยทางการของวัตถุที่พบ
  List<String> _detectedAlertMessages = []; // ข้อความเตือนภาษาไทย
  double? _lastDetectionConfidence; // confidence สูงสุดของการตรวจจับเฟรมล่าสุด

  /// ค่าว่างของแบนเนอร์คำสั่งคนขับ (ไม่มีสัญญาณ -> แผงซ่อนแบนเนอร์)
  static const DriverSignalResult _emptyDriverSignal = DriverSignalResult(
    message: '',
    action: SignalAction.none,
  );
  DriverSignalResult _driverSignalResult =
      _emptyDriverSignal; // คำสั่งคนขับจากผล stable ล่าสุด

  // ---------- Getters: ให้ UI อ่านค่าจากภายนอก (อ่านอย่างเดียว) ----------
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
  String? get confirmedTrafficLightClassName => _stableTrafficLights.isEmpty
      ? null
      : _stableTrafficLights.first.className;
  int? get activeTrafficLightTrackingId =>
      _stableTrafficLights.isEmpty ? null : _stableTrafficLights.first.trackId;
  RealtimePipelineSnapshot get pipelineSnapshot => _pipelineSnapshot;
  bool get isRealtimePipelineStale => _isRealtimePipelineStale;

  // Getter สำหรับ List ภาษาไทย
  List<String> get detectedFormalNames => _detectedFormalNames;
  List<String> get detectedAlertMessages => _detectedAlertMessages;
  double? get lastDetectionConfidence => _lastDetectionConfidence;

  /// แบนเนอร์คำสั่งคนขับ (เช่น "ไฟแดง - หยุดรอ") จาก [SignalInterpreter]
  DriverSignalResult get driverSignalResult => _driverSignalResult;

  bool get isVoiceEnabled => _voiceService.isEnabled; // เสียงเปิดอยู่หรือไม่

  /// สลับเปิด/ปิดเสียงประกาศ (signature ตรงกับฝั่ง video controller)
  void toggleVoice() {
    _voiceService.setEnabled(!_voiceService.isEnabled); // สลับสถานะ
    if (!_voiceService.isEnabled) {
      unawaited(
        _voiceService.stop(),
      ); // ถ้าปิดเสียง ให้หยุดการพูดที่กำลังค้างอยู่
    }
    notifyListeners(); // แจ้ง UI ให้ rebuild
  }

  /// สถานะการตรวจจับโดยรวม (ใช้แสดงใน UI แบบข้อความ)
  String get detectionStatus {
    if (!_isCameraEnabled) return 'กล้องปิดอยู่';
    if (_isModelLoading) {
      return _loadingMessage.isEmpty ? 'กำลังโหลดโมเดล' : _loadingMessage;
    }
    if (_modelPath == null) {
      return _loadingMessage.isEmpty ? 'ไม่พบโมเดล' : _loadingMessage;
    }
    if (_isRealtimePipelineStale) return 'กล้องไม่พร้อมหรือกำลังรอสัญญาณภาพ';
    if (_lastDetectionConfidence != null &&
        _lastDetectionConfidence! < _confidenceThreshold) {
      return 'ความมั่นใจต่ำ';
    }
    return 'กำลังตรวจจับ';
  }

  /// Constructor
  /// - พารามิเตอร์ @visibleForTesting: ให้ฝังปลอม (fake) แทนของจริงเพื่อเขียนเทสต์
  CameraInferenceController({
    @visibleForTesting SignNumberPipelineService? signNumberPipelineService,
    @visibleForTesting
    Duration numberDetectionInterval = const Duration(milliseconds: 400),
    @visibleForTesting CountdownReadingStabilizer? countdownStabilizer,
    @visibleForTesting DetectionStabilizer? detectionStabilizer,
    @visibleForTesting TrafficVoiceService? voiceService,
    @visibleForTesting VoiceAlertController? voiceAlertController,
    @visibleForTesting DateTime Function()? clock,
    @visibleForTesting
    Duration maximumFrameAge = defaultRealtimeMaximumFrameAge,
    @visibleForTesting bool enableFreshnessWatchdog = true,
    @visibleForTesting ModelManager? modelManager,
  }) {
    _clock = clock ?? DateTime.now;
    _maximumFrameAge = maximumFrameAge;
    _enableFreshnessWatchdog = enableFreshnessWatchdog;
    _voiceService = voiceService ?? TrafficVoiceService();
    // สร้างเอนจินอ่านเลข + คิวเฟรม + guard + monitor + stabilizer
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
    _detectionStabilizer =
        detectionStabilizer ?? DetectionStabilizer(config: _detectionConfig);
    _voiceAlertController =
        voiceAlertController ??
        VoiceAlertController(
          config: _detectionConfig,
          speakClassName: _speakStableClass,
        );
    _isFrontCamera = _lensFacing == LensFacing.front;

    // ModelManager พร้อม callback รับข้อความสถานะโหลดเส้น
    _modelManager =
        modelManager ??
        ModelManager(
          onStatusUpdate: (message) {
            if (_isDisposed) return;
            _loadingMessage = message;
            notifyListeners();
          },
        );
  }

  /// เริ่มต้นระบบ: เปิด watchdog + โหลดค่า threshold เก็บไว้ + โหลดโมเดลทั้ง 2 ตัว
  Future<void> initialize() async {
    _startFreshnessWatchdog(); // เริ่ม timer ล้างเฟรมเก่า

    try {
      // อ่านค่า threshold ที่ผู้ใช้เคยตั้งไว้ (ถ้ามี) จาก SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      _iouThreshold = prefs.getDouble('iouThreshold') ?? 0.45;
      _confidenceThreshold = prefs.getDouble('confidenceThreshold') ?? 0.5;
      _numItemsThreshold = prefs.getInt('numItemsThreshold') ?? 11;
    } catch (e) {
      log('Failed to load thresholds from SharedPreferences: $e');
    }

    await _loadModelForPlatform(); // โหลดโมเดลไฟจราจร
    await _loadDigitModel(); // โหลดโมเดลตัวเลข
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
      await oldDigitYolo?.dispose(); // ปล่อยโมเดลตัวเก่า

      // สร้าง pipeline อ่านตัวเลข และฝังลงในเอนจินเรียลไทม์
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
      return load(replacement); // ลองโหลด path ทดแทน
    }
  }

  /// จัดการ error จากโมเดลไฟจราจรที่รายงานมาจาก YOLOView
  Future<void> onModelLoadError(Object error, String failedPath) async {
    if (_isDisposed || failedPath != _modelPath) {
      return; // ไม่ใช่โมเดลปัจจุบัน -> ข้าม
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
      _modelPath = replacement; // มาโมเดลทดแทนแล้ว
      _loadingMessage = '';
    }
    notifyListeners();
  }

  // รับ output model: ฟังก์ชันที่ YOLOView เรียกเมื่อมีผลเฟรมสตรีมสดจากกล้อง
  Future<void> onStreamingData(Map<String, dynamic> data) {
    if (_isDisposed || !isCameraActive) {
      return Future.value(); // กล้องปิด -> ข้าม
    }

    // แปลงข้อมูล raw จากกล้องให้เป็น RealtimeFramePacket แล้วส่งเข้าคิว
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
    try {
      if (nextEnabled) {
        if (!_isCameraSuspended) {
          await _yoloController.resume(); // เปิดกล้อง
        }
      } else {
        await _yoloController.pause(); // ปิดกล้อง
      }
      _isCameraEnabled = nextEnabled;
      _resetDetectionSession();
      // ต้องรีเซ็ต guard/monitor ด้วย ไม่ใช่แค่ตั้ง flag:
      // กล้อง native เริ่มนับ frameNumber ใหม่หลัง resume ถ้าไม่ล้างเลขเฟรมล่าสุด
      // เฟรมชุดใหม่จะถูกตัดเป็น outOfOrder ทั้งหมดจนกว่าจะเลยเลขเดิม
      _resetRealtimePipeline();
      notifyListeners();
    } catch (error) {
      _loadingMessage =
          'ไม่สามารถ${nextEnabled ? 'เปิด' : 'ปิด'}กล้องได้: $error';
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
    // ขั้นตอนที่ 1: ตรวจความสด/ลำดับของเฟรมผ่าน FreshnessGuard
    final decision = _frameFreshnessGuard.evaluate(
      packet,
      now: processingStartedAt,
    );
    if (decision != RealtimeFrameDecision.accept) {
      _pipelineMonitor.recordRejected(decision); // บันทึกเฟรมที่ถูกปฏิเสธ
      if (decision == RealtimeFrameDecision.stale) {
        _isRealtimePipelineStale = true; // เฟรมเก่า -> pipeline ล้าสมัย
        _clearRealtimeResults();
      }
      _refreshPipelineSnapshot(processingStartedAt);
      notifyListeners();
      return;
    }

    // เฟรมผ่าน -> อัปเดตให้ pipeline "สด" ตามเวลาล่าสุด
    _lastFreshFrameCapturedAt = packet.estimatedCapturedAt;
    _isRealtimePipelineStale = false;

    final fps = packet.fps;
    if (fps != null) onPerformanceMetrics(fps); // อัปเดต FPS ถ้ากล้องรายงาน

    // ขั้นตอนที่ 2: ตรวจจับไฟจราจร + แปลความหมาย (เรียก pipeline หลัก)
    await onDetectionResults(
      packet.detections,
      timestamp: packet.estimatedCapturedAt,
    );
    if (_isDisposed) return;

    // อ่านเลขจาก raw frame ต่อได้ แต่แสดงเมื่อ sign_number ผ่าน temporal smoothing แล้ว
    final stabilizedReading = await _numberInferenceEngine.process(
      packet,
      enabled: !_detectionStabilizer.hasStableClass('green_light_circle'),
    );
    if (_isDisposed) return;

    final completedAt = _clock();
    _pipelineMonitor.recordProcessed(
      // บันทึกสถิติการประมวลผล
      packet,
      processingStartedAt: processingStartedAt,
      completedAt: completedAt,
    );
    _refreshPipelineSnapshot(completedAt);

    // ถ้าเฟรมเก่าเกินไปเมื่อประมวลผลเสร็จ -> ล้างผลลัพธ์ (แสดงว่า pipeline ล้าสมัย)
    if (packet.ageAt(completedAt) > _maximumFrameAge) {
      _isRealtimePipelineStale = true;
      _clearRealtimeResults();
    } else if (stabilizedReading != null) {
      _applyDetectedNumber(stabilizedReading); // มีตัวเลข stable -> แสดงใน UI
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

    final checkedAt = now ?? _clock();
    final lastCapturedAt = _lastFreshFrameCapturedAt;
    // ถ้ายังไม่มีเฟรมล่าสุด หรือยังไม่เกินอายุสูงสุด -> ยังใหม่พอ ไม่ต้องทำอะไร
    if (lastCapturedAt == null ||
        checkedAt.difference(lastCapturedAt) <= _maximumFrameAge) {
      return;
    }
    if (_isRealtimePipelineStale) return; // ล้าสมัยอยู่แล้ว -> ไม่ต้องทำซ้ำ

    // เฟรมเก่าเกิน -> ล้างผลและตั้งสถานะล้าสมัย
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

  // ==========================================
  // อัปเดต onDetectionResults เพื่อดึงทุก Class และแปลภาษาไทย
  // ==========================================
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
    final observationTime = timestamp ?? _clock();
    final qualifiedDetections = results.where((result) {
      final threshold = result.className == 'sign_number'
          ? realtimeSignConfidenceThreshold
          : _confidenceThreshold;
      return result.confidence >= threshold;
    });
    final stabilization = _detectionStabilizer.update(
      qualifiedDetections,
      timestamp: observationTime,
    );
    final stableDetections =
        List<StableDetection>.from(stabilization.stableDetections)
          ..sort((first, second) {
            final priorityOrder = _detectionConfig
                .ruleFor(first.className)
                .priority
                .compareTo(_detectionConfig.ruleFor(second.className).priority);
            return priorityOrder != 0
                ? priorityOrder
                : second.confidence.compareTo(first.confidence);
          });

    if (stabilization.events.any(
      (event) =>
          event.type != DetectionEventType.lost &&
          event.detection.className == 'green_light_circle',
    )) {
      _detectedNumber = null;
      _numberInferenceEngine.resetCycle();
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
    final stableConfidence = stableDetections.isEmpty
        ? null
        : stableDetections
              .map((detection) => detection.confidence)
              .reduce((first, second) => first > second ? first : second);

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

    // ----- คำนวณ FPS ต่อตามปกติ -----
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

  List<StableDetection> get _stableTrafficLights =>
      _detectionStabilizer.stableDetections
          .where(
            (detection) => DetectionAlertConfig.trafficLightClasses.contains(
              detection.className,
            ),
          )
          .toList()
        ..sort(
          (first, second) => _detectionConfig
              .ruleFor(first.className)
              .priority
              .compareTo(_detectionConfig.ruleFor(second.className).priority),
        );

  Future<void> _speakStableClass(String className) {
    final formalName = videoFormalThaiName(className);
    final alertMessage = _voiceService.getThaiMessage(className);
    final message = alertMessage.isEmpty
        ? formalName
        : '$formalName: $alertMessage';
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

    _activeSlider = _activeSlider == type ? SliderType.none : type;
    notifyListeners();
  }

  /// อัปเดตค่าจาก slider ที่กำลังแสดงอยู่ แล้วส่งต่อไปยัง YOLO
  /// - บางค่า (iou) ก็บันทึกลง SharedPreferences เพื่อใช้ครั้งถัดไป
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
          // บันทึกค่าลงเก็บถาวร (fire-and-forget พร้อม log กรณี error)
          SharedPreferences.getInstance()
              .then((prefs) {
                prefs.setDouble('iouThreshold', value);
              })
              .catchError((e) {
                log('Failed to save iouThreshold to SharedPreferences: $e');
              });
        }
        break;

      case SliderType.none: // ไม่มี slider เปิดอยู่ -> ไม่ทำอะไร
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
    _lensFacing = _isFrontCamera ? LensFacing.front : LensFacing.back;

    if (_isFrontCamera) {
      _currentZoomLevel = 1.0; // กล้องหน้ารีเซ็ต zoom
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
      await _loadingFuture; // มีงานโหลดอยู่แล้ว -> รวมงาน
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

      // บันทึก path ที่ได้ และรีเซ็ตสถานะโหลด
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

      // จัดการ error ให้อ่านง่าย (wrap ด้วย YOLOErrorHandler)
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
    _freshnessWatchdog?.cancel(); // หยุด watchdog
    _streamQueue.dispose(); // ปล่อยคิวเฟรม
    _resetDetectionSession();
    _numberInferenceEngine.dispose(); // ปล่อยเอนจินอ่านเลข

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
    _yoloController.dispose(); // ปล่อยตัวควบคุมกล้อง
    super.dispose();
  }
}
