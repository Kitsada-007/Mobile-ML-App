import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:trffic_ilght_app/core/services/detection/detection_alert_config.dart';
import 'package:trffic_ilght_app/core/services/detection/detection_stabilizer.dart';
import 'package:trffic_ilght_app/core/services/detection/traffic_detection_label_formatter.dart';
import 'package:trffic_ilght_app/core/services/inference/countdown_reading_stabilizer.dart';
import 'package:trffic_ilght_app/core/services/inference/sign_number_pipeline_service.dart';
import 'package:trffic_ilght_app/core/services/inference/signal_interpreter.dart';
import 'package:trffic_ilght_app/core/services/model_management/model_manager.dart';
import 'package:trffic_ilght_app/features/video_detection/data/services/video_frame_analysis_service.dart';
import 'package:trffic_ilght_app/features/video_detection/data/services/video_input_validator.dart';
import 'package:trffic_ilght_app/features/video_detection/data/services/video_processing_service.dart';
import 'package:trffic_ilght_app/shared/models/model_types.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:video_player/video_player.dart';

import 'package:trffic_ilght_app/core/services/voice/traffic_voice_service.dart';
import 'package:trffic_ilght_app/core/services/voice/voice_alert_controller.dart';
import 'package:trffic_ilght_app/core/services/voice/countdown_alert_controller.dart';

/// ฟังก์ชัน factory สำหรับสร้างโมเดล YOLO ใช้กับวิดีโอ
/// - useMultiInstance: true = โหลดแบบหลาย instance (เพื่อรองรับการรันคู่ขนาน)
@visibleForTesting
YOLO createVideoYolo(String modelPath) {
  return YOLO(
    modelPath: modelPath,
    task: YOLOTask.detect,
    useMultiInstance: true,
  );
}

/// Controller สำหรับหน้าตรวจจับวิดีโอ
/// รับผิดชอบ: Business logic, การโหลดโมเดล, จัดการ state,
/// และซิงโครไนซ์ผลลัพธ์ตรวจจับกับเฟรมวิดีโอที่กำลังเล่น (overlay แบบ realtime)
class VideoInferenceController extends ChangeNotifier {
  // Constructor รองรับ Dependency Injection (ส่ง services เข้ามาเองได้ เพื่อใช้ทดแทนของจริงตอนเทสต์)
  VideoInferenceController({
    ImagePicker? picker,
    VideoInputValidator? videoValidator,
    ModelManager? modelManager,
    VideoProcessingService? videoProcessingService,
    TrafficVoiceService? voiceService,
    @visibleForTesting DetectionStabilizer? detectionStabilizer,
    @visibleForTesting VoiceAlertController? voiceAlertController,
    @visibleForTesting CountdownAlertController? countdownAlertController,
    // จำนวนตรวจเช็คต่อวินาที — default 6 เพราะ 6 อยู่ที่ขอบ Nyquist พอดี
    // สำหรับไฟกะพริบ ~1 Hz ทำให้การตรวจสถานะ flashing_* พลาดง่ายในบางไฟล์
    // (ถ้าวัดบนเครื่องจริงแล้วเวลาประมวลผลรวมเพิ่มเกิน ~40% ให้ถอยกลับเป็น 6
    // ดูผล timingSummary ใน log "[video-perf]" เทียบ before/after)
    this.targetChecksPerSecond = 4,
  }) : _picker = picker ?? ImagePicker(),
       _videoValidator = videoValidator ?? const VideoInputValidator(),
       _modelManager = modelManager ?? ModelManager(),
       _videoProcessingService =
           videoProcessingService ?? VideoProcessingService(),
       _voiceService = voiceService ?? TrafficVoiceService() {
    _detectionStabilizer =
        detectionStabilizer ?? DetectionStabilizer(config: _detectionConfig);
    _voiceAlertController =
        voiceAlertController ??
        VoiceAlertController(
          config: _detectionConfig,
          speakClassName: _speakStableClass,
        );
    _countdownAlertController =
        countdownAlertController ?? CountdownAlertController();
  }

  final ImagePicker _picker;
  final VideoInputValidator _videoValidator;
  final ModelManager _modelManager;
  final VideoProcessingService _videoProcessingService;
  final TrafficVoiceService _voiceService;
  final int targetChecksPerSecond;
  static const DetectionAlertConfig _detectionConfig = DetectionAlertConfig();
  late final DetectionStabilizer _detectionStabilizer;
  late final VoiceAlertController _voiceAlertController;
  late final CountdownAlertController _countdownAlertController;
  final CountdownReadingStabilizer _countdownStabilizer =
      CountdownReadingStabilizer();

  Map<int, FrameAnalysisResult> _frameResults = {};
  int _targetFps = 5;
  int _lastFrameIndex = -1;

  List<YOLOResult> _currentFrameDetections = [];
  String? _currentDetectedNumber;
  String? _currentCountdownUiMessage;
  // คลาสไฟจราจรเสถียรของเฟรมปัจจุบัน (รวมคลาสสังเคราะห์ไฟกะพริบ)
  // ใช้เลือกชุดสีของป้ายนับถอยหลังใน UI เท่านั้น ไม่เกี่ยวกับ logic เสียง
  String? _currentStableTrafficLightClassName;
  DriverSignalResult _currentDriverSignalResult = const DriverSignalResult(
    message: '',
    action: SignalAction.none,
  );
  List<String> _currentFormalNames = [];
  List<String> _currentAlertMessages = [];
  double? _lastDetectionConfidence;

  Uint8List? _imageBytes;

  YOLO? _trafficYolo;
  YOLO? _numberYolo;
  // ต้อง dispose เพราะมี worker isolate
  SignNumberPipelineService? _signNumberPipeline;
  VideoFrameAnalysisService? _videoFrameAnalysisService;
  String? _trafficModelPath;
  String? _numberModelPath;

  bool _areModelsReady = false;
  bool _processing = false;
  double _progressValue = 0.0;
  String _progressText = '';
  String? _snackBarMessage;

  VideoPlayerController? _videoController;
  VideoPlayerController? _selectedPreviewController;
  File? _videoFile;
  bool _isDisposed = false;

  bool get areModelsReady => _areModelsReady;
  bool get isProcessing => _processing;
  double get progressValue => _progressValue;
  String get progressText => _progressText;
  List<YOLOResult> get currentFrameDetections => _currentFrameDetections;
  String? get currentDetectedNumber => _currentDetectedNumber;
  String? get currentCountdownUiMessage => _currentCountdownUiMessage;

  /// คลาสไฟจราจรที่ยืนยันเสถียรแล้วของเฟรมปัจจุบัน (เช่น red_light_circle,
  /// flashing_yellow) สำหรับให้ UI เลือกสีป้ายนับถอยหลัง — null เมื่อยังไม่ยืนยัน
  String? get stableTrafficLightClassName =>
      _currentStableTrafficLightClassName;
  DriverSignalResult get currentDriverSignalResult =>
      _currentDriverSignalResult;
  List<String> get currentFormalNames => List.unmodifiable(_currentFormalNames);
  List<String> get currentAlertMessages =>
      List.unmodifiable(_currentAlertMessages);
  double? get lastDetectionConfidence => _lastDetectionConfidence;

  Uint8List? get imageBytes => _imageBytes;
  VideoPlayerController? get videoController => _videoController;
  VideoPlayerController? get selectedPreviewController =>
      _selectedPreviewController;
  File? get videoFile => _videoFile;
  String? get snackBarMessage => _snackBarMessage;

  bool get isVoiceEnabled => _voiceService.isEnabled;

  /// สลับเปิด/ปิดเสียงประกาศ
  void toggleVoice() {
    _voiceService.setEnabled(!_voiceService.isEnabled);
    if (!_voiceService.isEnabled) {
      unawaited(_voiceService.stop());
    }
    notifyListeners();
  }

  /// ล้างข้อความ SnackBar (เรียกเมื่อแสดงไปแล้ว)
  void clearSnackBarMessage() {
    _snackBarMessage = null;
  }

  /// โหลดโมเดล YOLO ทั้ง 2 ตัว (Traffic + Number) ให้พร้อมใช้งาน
  Future<void> initializeModels() async {
    YOLO? trafficYolo;
    YOLO? numberYolo;
    try {
      // ModelManager จะ download ให้อัตโนมัติถ้ายังไม่มีไฟล์
      _trafficModelPath = await _modelManager.getModelPath(ModelType.traffic);
      _numberModelPath = await _modelManager.getModelPath(ModelType.number);

      if (_trafficModelPath == null || _numberModelPath == null) {
        _notifyMessage('ไม่พบไฟล์โมเดล Traffic หรือ Number');
        return;
      }

      trafficYolo = await _loadYoloWithRollback(
        ModelType.traffic,
        _trafficModelPath!,
      );
      numberYolo = await _loadYoloWithRollback(
        ModelType.number,
        _numberModelPath!,
      );

      // ถ้ามีการ dispose ระหว่างรอโหลด -> ปล่อยโมเดลที่โหลดเสร็จแล้วออก แล้วหยุด
      if (_isDisposed) {
        await trafficYolo.dispose();
        await numberYolo.dispose();
        return;
      }

      // เก็บของเก่าไว้ก่อน แล้วค่อยปล่อยหลังสลับของใหม่เข้าที่
      // (initializeModels อาจถูกเรียกซ้ำตอน retry หลัง error -> ถ้าไม่ปล่อยจะ leak)
      final oldPipeline = _signNumberPipeline;
      final oldTrafficYolo = _trafficYolo;
      final oldNumberYolo = _numberYolo;

      _trafficYolo = trafficYolo;
      _numberYolo = numberYolo;
      _signNumberPipeline = SignNumberPipelineService(digitYolo: numberYolo);
      _videoFrameAnalysisService = VideoFrameAnalysisService(
        trafficYolo: trafficYolo,
        signNumberPipeline: _signNumberPipeline!,
      );
      _areModelsReady = true;
      notifyListeners();

      // ปล่อยของเก่า: pipeline ก่อน (มี isolate worker และใช้ numberYolo ตัวเก่าอยู่)
      // แล้วจึงปล่อยโมเดล ไม่งั้นงานที่ค้างใน worker จะอ้างโมเดลที่ถูกปล่อยไปแล้ว
      await oldPipeline?.dispose();
      await oldTrafficYolo?.dispose();
      await oldNumberYolo?.dispose();
    } catch (e) {
      await trafficYolo?.dispose();
      await numberYolo?.dispose();
      if (_isDisposed) return;

      final error = YOLOErrorHandler.handleError(
        e,
        'Failed to load video inference models',
      );
      _notifyMessage('Error loading models: ${error.message}');
    }
  }

  /// โหลดโมเดล YOLO พร้อม rollback: ถ้า path แรกโหลดไม่ได้
  /// จะขอ path สำรองจาก ModelManager เพื่อลองโหลดใหม่
  Future<YOLO> _loadYoloWithRollback(
    ModelType modelType,
    String initialPath,
  ) async {
    try {
      return await _loadYolo(initialPath);
    } catch (_) {
      final replacement = await _modelManager.reportModelLoadFailure(
        modelType,
        failedPath: initialPath,
      );
      // ไม่มี path ทดแทน หรือได้ path เดิม -> โยน error เดิมต่อ
      if (replacement == null || replacement == initialPath) rethrow;
      return _loadYolo(replacement);
    }
  }

  /// สร้าง YOLO จาก path และโหลดโมเดล
  /// ถ้าโหลดไม่สำเร็จจะ dispose instance นั้นก่อนโยน error (กัน resource รั่ว)
  Future<YOLO> _loadYolo(String modelPath) async {
    final yolo = createVideoYolo(modelPath);
    try {
      await yolo.loadModel();
      return yolo;
    } catch (_) {
      await yolo.dispose();
      rethrow;
    }
  }

  /// เลือกวิดีโอจากแกลเลอรี แล้ว (ถ้าโมเดลพร้อม) ประมวลผลทันที
  Future<void> pickVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;

    final File selectedFile = File(file.path);
    final validation = await _videoValidator.validate(selectedFile);
    if (!validation.isValid) {
      _notifyMessage(validation.errorMessage!);
      return;
    }

    final previewController = VideoPlayerController.file(selectedFile);
    var previewReady = false;
    try {
      await previewController.initialize();
      await previewController.seekTo(Duration.zero); // ขยับไปเฟรมแรก
      previewReady = true;
    } catch (_) {
      await previewController.dispose();
    }

    _clearVideoController();
    await _selectedPreviewController?.dispose();

    _videoFile = selectedFile;
    _selectedPreviewController = previewReady ? previewController : null;
    _frameResults.clear();
    _currentFrameDetections.clear();
    _resetDetectionSession(stopVoice: false);
    notifyListeners();

    if (_areModelsReady) {
      unawaited(predictVideo());
    }
  }

  /// ประมวลผลวิดีโอทั้งหมด (ตรวจจับทุกเฟรม) แล้วเล่นผลลัพธ์พร้อม overlay
  Future<void> predictVideo() async {
    if (!_areModelsReady ||
        _videoFrameAnalysisService == null ||
        _videoFile == null) {
      _notifyMessage('กรุณาเลือกวิดีโอและรอให้โมเดลโหลดเสร็จ');
      return;
    }

    _processing = true;
    _progressValue = 0.0;
    _progressText = 'กำลังเตรียมโฟลเดอร์ชั่วคราว...';
    _frameResults.clear();
    _currentFrameDetections.clear();
    _resetDetectionSession(stopVoice: false);
    _clearVideoController();
    notifyListeners();

    try {
      final result = await _videoProcessingService.processVideo(
        videoFile: _videoFile!,
        frameAnalysisService: _videoFrameAnalysisService!,
        countdownStabilizer: _countdownStabilizer,
        targetFps: targetChecksPerSecond, // ใช้ค่าที่ controller กำหนดจริง
        isCancelled: () => _isDisposed,
        onProgress: (progressValue, progressText) {
          if (!_isDisposed) {
            _progressValue = progressValue;
            _progressText = progressText;
            notifyListeners();
          }
        },
      );

      if (_isDisposed) return;

      _frameResults = result.frameResults;
      _targetFps = result.targetFps;

      _notifyMessage('Video processing completed successfully!');

      _videoController = VideoPlayerController.file(
        File(result.finalVideoPath),
      );
      await _videoController!.initialize();
      if (_isDisposed) return;
      await _videoController!.setLooping(true);

      await _selectedPreviewController?.dispose();
      _selectedPreviewController = null;

      _videoController!.addListener(_onVideoPositionChanged);
      await _videoController!.play();

      if (!_isDisposed) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error processing video: $e');
      _notifyMessage('Error: $e');
    } finally {
      if (!_isDisposed) {
        _processing = false;
        notifyListeners();
      }
    }
  }

  /// ตำแหน่งวิดีโอเปลี่ยน -> อัปเดตผลตรวจจับ/overlay ของเฟรมนั้น
  void _onVideoPositionChanged() {
    if (_isDisposed ||
        _videoController == null ||
        !_videoController!.value.isInitialized) {
      return;
    }

    final position = _videoController!.value.position;
    final frameIndex = (position.inMilliseconds * _targetFps / 1000).floor();

    if (frameIndex != _lastFrameIndex) {
      // เมื่อวิดีโอวนหรือ seek ย้อน ต้องเริ่ม tracking session ใหม่
      if (frameIndex < _lastFrameIndex) {
        _resetDetectionSession();
      }
      _lastFrameIndex = frameIndex;

      final frameResult = _frameResults[frameIndex];
      if (frameResult != null) {
        // กล่องใช้ผล raw ของเฟรมโดยตรง ส่วน summary และเสียงใช้ผล stable ด้านล่าง
        _currentFrameDetections = frameResult.detections;
        _updateCurrentFrameAnalysis(
          frameResult.detections,
          frameResult.detectedNumber,
          signPresent: frameResult.signPresent,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            position.inMilliseconds,
          ),
        );
      } else {
        _currentFrameDetections = [];
        _updateCurrentFrameAnalysis(
          [],
          null,
          signPresent: false,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            position.inMilliseconds,
          ),
        );
      }
      notifyListeners();
    }
  }

  /// แยก raw detections ไป tracking/smoothing ก่อนอัปเดต UI และเสียง
  void _updateCurrentFrameAnalysis(
    List<YOLOResult> detections,
    String? rawDetectedNumber, {
    required bool signPresent,
    required DateTime timestamp,
  }) {
    final stableInput = detections.where(
      (detection) =>
          _detectionConfig.participatesInStableDetection(detection.className),
    );
    final update = _detectionStabilizer.update(
      stableInput,
      timestamp: timestamp,
    );
    final stableDetections = List<StableDetection>.from(update.stableDetections)
      ..sort((first, second) {
        final priorityOrder = _detectionConfig
            .ruleFor(first.className)
            .priority
            .compareTo(_detectionConfig.ruleFor(second.className).priority);
        return priorityOrder != 0
            ? priorityOrder
            : second.confidence.compareTo(first.confidence);
      });
    final stableYoloDetections = stableDetections
        .map((detection) => detection.toYoloResult())
        .toList(growable: false);
    // ใช้ signPresent จาก FrameAnalysisResult ตรง ๆ (single source of truth)
    // ห้ามนับ raw detection ใหม่ที่นี่ — เฟรมช่วง hold ไม่มีกล่อง sign_number
    // แต่ต้องยังถือว่าป้ายอยู่ ไม่งั้นเลขที่ service hold ไว้ถูกทิ้งทันที
    _currentDetectedNumber = signPresent ? rawDetectedNumber : null;

    String? stableTrafficLightClassName;
    for (final detection in stableDetections) {
      if (CountdownAlertController.supportedTrafficLightClasses.contains(
        detection.className,
      )) {
        stableTrafficLightClassName = detection.className;
        break;
      }
    }
    final countdownUpdate = _countdownAlertController.update(
      isSignDetected: signPresent,
      detectedNumber: _currentDetectedNumber,
      stableTrafficLightClassName: stableTrafficLightClassName,
    );
    _currentCountdownUiMessage = countdownUpdate.uiMessage;

    // คลาสไฟสำหรับสีป้ายนับถอยหลัง: รวม off_light และไฟกะพริบสังเคราะห์
    // (คนละเงื่อนไขกับ countdown ด้านบนที่จำกัดเฉพาะไฟนิ่งซึ่งมีนับถอยหลังจริง)
    _currentStableTrafficLightClassName = null;
    for (final detection in stableDetections) {
      if (DetectionAlertConfig.trafficLightClasses.contains(
            detection.className,
          ) ||
          DetectionAlertConfig.flashingLightClasses.contains(
            detection.className,
          )) {
        _currentStableTrafficLightClassName = detection.className;
        break;
      }
    }

    _currentDriverSignalResult = SignalInterpreter.interpret(
      stableYoloDetections,
    );

    final formalNames = <String>[];
    final alertMessages = <String>[];
    for (final detection in stableDetections) {
      final formalName = videoFormalThaiName(detection.className);
      if (formalNames.contains(formalName)) continue;
      formalNames.add(formalName);
      alertMessages.add(_voiceService.getThaiMessage(detection.className));
    }
    _currentFormalNames = formalNames;
    _currentAlertMessages = alertMessages;
    _lastDetectionConfidence = stableDetections.isEmpty
        ? null
        : stableDetections
              .map((detection) => detection.confidence)
              .reduce((first, second) => first > second ? first : second);

    final shouldAnnounce =
        _videoController != null &&
        _videoController!.value.isPlaying &&
        _voiceService.isEnabled;
    if (shouldAnnounce) {
      unawaited(_voiceAlertController.handleEvents(update.events));
      final countdownEvent = countdownUpdate.event;
      if (countdownEvent != null) {
        unawaited(
          _voiceAlertController.speakMessageIfIdle(
            () => _voiceService.speak(countdownEvent.voiceMessage),
          ),
        );
      }
    }
  }

  Future<void> _speakStableClass(String className) {
    final formalName = videoFormalThaiName(className);
    final alertMessage = _voiceService.getThaiMessage(className);
    final message = alertMessage.isEmpty
        ? formalName
        : '$formalName: $alertMessage';
    return _voiceService.speak(message);
  }

  void _resetDetectionSession({bool stopVoice = true}) {
    _detectionStabilizer.reset();
    _voiceAlertController.reset();
    _countdownAlertController.reset();
    _countdownStabilizer.reset();
    _lastFrameIndex = -1;
    _currentDetectedNumber = null;
    _currentCountdownUiMessage = null;
    _currentStableTrafficLightClassName = null;
    _currentDriverSignalResult = const DriverSignalResult(
      message: '',
      action: SignalAction.none,
    );
    _currentFormalNames.clear();
    _currentAlertMessages.clear();
    _lastDetectionConfidence = null;
    if (stopVoice) unawaited(_voiceService.stop());
  }

  /// สลับเล่น/หยุดวิดีโอ (และหยุดเสียงเมื่อ pause)
  Future<void> togglePlayPause() async {
    if (_videoController == null) return;
    if (_videoController!.value.isPlaying) {
      // หยุดให้เสร็จก่อนรีเซ็ต state
      await _videoController!.pause();
      _resetDetectionSession();
    } else {
      _resetDetectionSession();
      await _videoController!.play();
    }
    if (_isDisposed) return;
    notifyListeners();
  }

  /// หยุดเล่นวิดีโอชั่วคราวและล้างสถานะการตรวจจับ/เสียง
  Future<void> pause() async {
    if (_videoController != null && _videoController!.value.isPlaying) {
      await _videoController!.pause();
      _resetDetectionSession();
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  /// ล้างตัวเล่นวิดีโอผลลัพธ์ปัจจุบัน (ถอด listener + dispose + หยุดเสียง)
  void _clearVideoController() {
    _resetDetectionSession();
    if (_videoController != null) {
      final controller = _videoController!;
      _videoController = null;
      controller.removeListener(_onVideoPositionChanged);
      unawaited(controller.pause().then((_) => controller.dispose()));
    }
  }

  /// ตั้งข้อความ SnackBar แล้วแจ้ง UI
  void _notifyMessage(String msg) {
    _snackBarMessage = msg;
    notifyListeners();
  }

  /// ปล่อยทรัพยากรทั้งหมดเมื่อ controller ถูก dispose (ปิดหน้าจอ)
  @override
  void dispose() {
    _isDisposed = true; // กัน async code ทำงานต่อหลัง dispose
    _resetDetectionSession();
    unawaited(
      _trafficYolo?.dispose(),
    ); // Traffic ไม่ผูกกับ pipeline ปล่อยได้เลย

    // pipeline ใช้ numberYolo อยู่ และมี isolate worker ที่อาจยังทำงานค้าง
    // จึงต้องรอ pipeline.dispose() ให้จบก่อนแล้วค่อยปล่อยโมเดลที่มันใช้
    // ใช้ then() ไม่ใช่ Future(...) เพราะ Future(...) สร้าง Timer ที่ค้างจน
    // widget test ฟ้อง "pending timers" ตอน teardown
    final pipeline = _signNumberPipeline;
    final numberYolo = _numberYolo;
    _signNumberPipeline = null;
    _numberYolo = null;
    unawaited(
      (pipeline?.dispose() ?? Future<void>.value()).then(
        (_) => numberYolo?.dispose() ?? Future<void>.value(),
      ),
    );
    if (_videoController != null) {
      final controller = _videoController!;
      _videoController = null;
      controller.removeListener(_onVideoPositionChanged);
      unawaited(controller.pause().then((_) => controller.dispose()));
    }
    _selectedPreviewController?.dispose();
    super.dispose();
  }
}
