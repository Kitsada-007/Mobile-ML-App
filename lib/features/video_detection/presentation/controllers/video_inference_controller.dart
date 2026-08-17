import 'dart:async'; // สำหรับ unawaited (สั่ง async แบบไม่รอผล)
import 'dart:io'; // สำหรับใช้งาน File (ไฟล์วิดีโอ)

import 'package:flutter/foundation.dart'; // มี ChangeNotifier + @visibleForTesting
import 'package:image_picker/image_picker.dart'; // เลือกวิดีโอจากแกลเลอรี
import 'package:trffic_ilght_app/core/services/detection/detection_alert_config.dart';
import 'package:trffic_ilght_app/core/services/detection/detection_stabilizer.dart';
import 'package:trffic_ilght_app/core/services/detection/traffic_detection_label_formatter.dart';
import 'package:trffic_ilght_app/core/services/inference/countdown_reading_stabilizer.dart'; // ลดความสั่นไหวของตัวเลขนับถอยหลัง
import 'package:trffic_ilght_app/core/services/inference/sign_number_pipeline_service.dart'; // Pipeline อ่านเลขป้าย/นับถอยหลัง
import 'package:trffic_ilght_app/core/services/inference/signal_interpreter.dart'; // แปลผลสัญญาณไฟ -> คำสั่งคนขับ
import 'package:trffic_ilght_app/core/services/model_management/model_manager.dart'; // จัดการ download/หา path ของโมเดล
import 'package:trffic_ilght_app/features/video_detection/data/services/video_frame_analysis_service.dart'; // วิเคราะห์ภาพแต่ละเฟรม
import 'package:trffic_ilght_app/features/video_detection/data/services/video_input_validator.dart'; // ตรวจสอบไฟล์วิดีโอที่เลือก
import 'package:trffic_ilght_app/features/video_detection/data/services/video_processing_service.dart'; // ประมวลผลวิดีโอทั้งไฟล์
import 'package:trffic_ilght_app/shared/models/model_types.dart'; // ประเภทของโมเดล (traffic / number)
import 'package:ultralytics_yolo/ultralytics_yolo.dart'; // ไลบรารี YOLO สำหรับตรวจจับ
import 'package:video_player/video_player.dart'; // เล่นวิดีโอใน Flutter

import 'package:trffic_ilght_app/core/services/voice/traffic_voice_service.dart'; // บริการเสียงประกาศภาษาไทย
import 'package:trffic_ilght_app/core/services/voice/voice_alert_controller.dart';
import 'package:trffic_ilght_app/core/services/voice/countdown_alert_controller.dart';

/// ฟังก์ชัน factory สำหรับสร้างโมเดล YOLO ใช้กับวิดีโอ
/// - ทำเครื่องหมาย @visibleForTesting เพื่อให้ทดสอบได้จากภายนอก package
/// - task: YOLOTask.detect = งานตรวจจับวัตถุ
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
    ImagePicker? picker, // ตัวเลือกวิดีโอ (default: ImagePicker จริง)
    VideoInputValidator? videoValidator, // ตัวตรวจสอบวิดีโอ
    ModelManager? modelManager, // ตัวจัดการโมเดล
    VideoProcessingService? videoProcessingService, // ตัวประมวลผลวิดีโอ
    TrafficVoiceService? voiceService, // บริการเสียง
    @visibleForTesting DetectionStabilizer? detectionStabilizer,
    @visibleForTesting VoiceAlertController? voiceAlertController,
    @visibleForTesting CountdownAlertController? countdownAlertController,
    this.targetChecksPerSecond = 4, // จำนวนตรวจเช็คต่อวินาที (default 4)
  }) : _picker = picker ?? ImagePicker(), // ถ้าไม่ส่งค่าใช้ default (สร้างใหม่)
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

  // ---- Dependencies (services ที่ใช้งาน) ----
  final ImagePicker _picker; // เลือกวิดีโอจากแกลเลอรี
  final VideoInputValidator _videoValidator; // ตรวจสอบความถูกต้องของไฟล์วิดีโอ
  final ModelManager _modelManager; // หา path + จัดการโมเดล
  final VideoProcessingService
  _videoProcessingService; // ประมวลผลวิดีโอทั้งไฟล์
  final TrafficVoiceService _voiceService; // พูดเสียงประกาศไทย
  final int targetChecksPerSecond; // ความถี่ที่ต้องการตรวจต่อวินาที
  static const DetectionAlertConfig _detectionConfig = DetectionAlertConfig();
  late final DetectionStabilizer _detectionStabilizer;
  late final VoiceAlertController _voiceAlertController;
  late final CountdownAlertController _countdownAlertController;
  // ตัวกันความสั่นไหวของตัวเลขนับถอยหลัง (ไม่ให้เลขเด้งขึ้น/ลงบ่อย)
  final CountdownReadingStabilizer _countdownStabilizer =
      CountdownReadingStabilizer();

  // ---- State สำหรับผลการตรวจจับ ----
  Map<int, FrameAnalysisResult> _frameResults =
      {}; // ผลลัพธ์รายเฟรม (key = index เฟรม)
  int _targetFps = 5; // FPS ที่ใช้ประมวลผลวิดีโอ (ค่าเริ่มต้น 5)
  int _lastFrameIndex =
      -1; // index เฟรมสุดท้ายที่แสดง (ใช้ตรวจจับว่าเฟรมเปลี่ยน)

  List<YOLOResult> _currentFrameDetections = []; // ผลตรวจจับของเฟรมที่แสดงอยู่
  String?
  _currentDetectedNumber; // ตัวเลขที่ตรวจพบในเฟรมปัจจุบัน (เช่น 5, 4, 3)
  String? _currentCountdownUiMessage;
  // ผลการแปลความหมายสัญญาณไฟ -> คำสั่งคนขับของเฟรมปัจจุบัน (เริ่มต้น: ไม่มี action)
  DriverSignalResult _currentDriverSignalResult = const DriverSignalResult(
    message: '',
    action: SignalAction.none,
  );
  List<String> _currentFormalNames = []; // ชื่อไทยทางการของวัตถุที่ตรวจพบ
  List<String> _currentAlertMessages = []; // ข้อความแจ้งเตือนภาษาไทย
  double? _lastDetectionConfidence; // ค่า confidence สูงสุดของเฟรมล่าสุด

  Uint8List? _imageBytes; // ข้อมูลภาพต้นฉบับ (bytes)

  // ---- โมเดล YOLO และบริการวิเคราะห์ ----
  YOLO? _trafficYolo; // โมเดลตรวจจับไฟจราจร
  YOLO? _numberYolo; // โมเดลอ่านตัวเลข/ป้ายนับถอยหลัง
  SignNumberPipelineService?
  _signNumberPipeline; // pipeline อ่านเลขป้าย (ต้อง dispose เพราะมี worker isolate)
  VideoFrameAnalysisService? _videoFrameAnalysisService; // บริการวิเคราะห์เฟรม
  String? _trafficModelPath; // path ไฟล์โมเดล Traffic
  String? _numberModelPath; // path ไฟล์โมเดล Number

  // ---- สถานะการทำงาน/ความคืบหน้า ----
  bool _areModelsReady = false; // โมเดลโหลดพร้อมแล้วหรือยัง
  bool _processing = false; // กำลังประมวลผลวิดีโอหรือไม่
  double _progressValue = 0.0; // ค่าความคืบหน้า 0.0 - 1.0
  String _progressText = ''; // ข้อความอธิบายขั้นตอนที่กำลังทำ
  String? _snackBarMessage; // ข้อความที่จะแสดงเป็น SnackBar

  // ---- วิดีโอ ----
  VideoPlayerController?
  _videoController; // ตัวเล่นวิดีโอผลลัพธ์ (หลังประมวลผล)
  VideoPlayerController?
  _selectedPreviewController; // ตัวเล่นตัวอย่างวิดีโอที่เลือก
  File? _videoFile; // ไฟล์วิดีโอที่ผู้ใช้เลือก
  bool _isDisposed =
      false; // flag บอกว่า dispose ไปแล้วหรือยัง (กันทำงานหลังปิด)

  // ---------- Getters (ให้ UI อ่านค่าจากภายนอกได้ แต่แก้ไขไม่ได้) ----------
  bool get areModelsReady => _areModelsReady;
  bool get isProcessing => _processing;
  double get progressValue => _progressValue;
  String get progressText => _progressText;
  List<YOLOResult> get currentFrameDetections => _currentFrameDetections;
  String? get currentDetectedNumber => _currentDetectedNumber;
  String? get currentCountdownUiMessage => _currentCountdownUiMessage;
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

  bool get isVoiceEnabled => _voiceService.isEnabled; // เสียงเปิดอยู่หรือไม่

  /// สลับเปิด/ปิดเสียงประกาศ
  void toggleVoice() {
    _voiceService.setEnabled(!_voiceService.isEnabled); // สลับสถานะ
    if (!_voiceService.isEnabled) {
      unawaited(
        _voiceService.stop(),
      ); // ถ้าปิดเสียง ให้หยุดการพูดที่กำลังค้างอยู่
    }
    notifyListeners(); // แจ้ง UI ให้ rebuild
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
      // ขอ path ของไฟล์โมเดลจาก ModelManager (download อัตโนมัติถ้ายังไม่มี)
      _trafficModelPath = await _modelManager.getModelPath(ModelType.traffic);
      _numberModelPath = await _modelManager.getModelPath(ModelType.number);

      // ถ้าเจอโมเดลไม่ครบทั้ง 2 ตัว -> แจ้งเตือนแล้วหยุด
      if (_trafficModelPath == null || _numberModelPath == null) {
        _notifyMessage('ไม่พบไฟล์โมเดล Traffic หรือ Number');
        return;
      }

      // โหลดโมเดลทั้งสองตัว (มี rollback ถ้า path แรกใช้ไม่ได้)
      trafficYolo = await _loadYoloWithRollback(
        ModelType.traffic,
        _trafficModelPath!,
      );
      numberYolo = await _loadYoloWithRollback(
        ModelType.number,
        _numberModelPath!,
      );

      // ถ้ามีการ dispose ระหว่างโหลด -> ปล่อยโมเดลที่โหลดเสร็จแล้วออก แล้วหยุด
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

      // เก็บโมเดลเข้าที่และสร้างบริการวิเคราะห์เฟรม
      _trafficYolo = trafficYolo;
      _numberYolo = numberYolo;
      _signNumberPipeline = SignNumberPipelineService(digitYolo: numberYolo);
      _videoFrameAnalysisService = VideoFrameAnalysisService(
        trafficYolo: trafficYolo,
        signNumberPipeline: _signNumberPipeline!,
      );
      _areModelsReady = true; // ตั้งสถานะว่าพร้อมแล้ว
      notifyListeners();

      // ปล่อยของเก่า: pipeline ก่อน (มี isolate worker และใช้ numberYolo ตัวเก่าอยู่)
      // แล้วจึงปล่อยโมเดล ไม่งั้นงานที่ค้างใน worker จะอ้างโมเดลที่ถูกปล่อยไปแล้ว
      await oldPipeline?.dispose();
      await oldTrafficYolo?.dispose();
      await oldNumberYolo?.dispose();
    } catch (e) {
      // กรณี error: ปล่อยโมเดลที่โหลดมา (บางส่วน) แล้วแสดงข้อความผิดพลาด
      await trafficYolo?.dispose();
      await numberYolo?.dispose();
      if (_isDisposed) return; // ถ้า dispose แล้วไม่ต้องแจ้งเตือน

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
      return await _loadYolo(initialPath); // ลองโหลด path แรกก่อน
    } catch (_) {
      // path แรกล้มเหลว -> รายงานความล้มเหลวเพื่อขอ path ทดแทน
      final replacement = await _modelManager.reportModelLoadFailure(
        modelType,
        failedPath: initialPath,
      );
      // ไม่มี path ทดแทน หรือได้ path เดิม -> โยน error เดิมต่อ
      if (replacement == null || replacement == initialPath) rethrow;
      return _loadYolo(replacement); // ลองโหลด path ทดแทน
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
    // เปิดแกลเลอรีให้เลือกวิดีโอ
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return; // ผู้ใช้ยกเลิก -> ไม่ต้องทำอะไร

    final File selectedFile = File(file.path);
    // ตรวจสอบความถูกต้องของไฟล์วิดีโอ (ขนาด/รูปแบบ ฯลฯ)
    final validation = await _videoValidator.validate(selectedFile);
    if (!validation.isValid) {
      _notifyMessage(validation.errorMessage!); // แจ้งเหตุผลที่ไม่ผ่าน
      return;
    }

    // สร้างตัวเล่นตัวอย่าง (preview) สำหรับวิดีโอที่เลือก
    final previewController = VideoPlayerController.file(selectedFile);
    var previewReady = false;
    try {
      await previewController.initialize();
      await previewController.seekTo(Duration.zero); // ขยับไปเฟรมแรก
      previewReady = true;
    } catch (_) {
      await previewController
          .dispose(); // เตรียมตัวเล่นไม่สำเร็จ -> ปล่อยทรัพยากร
    }

    _clearVideoController(); // ล้างวิดีโอผลลัพธ์เก่าออก
    await _selectedPreviewController?.dispose(); // ปล่อย preview ตัวเก่า

    // ---- ตั้งค่า state ใหม่ด้วยวิดีโอที่เลือก ----
    _videoFile = selectedFile;
    _selectedPreviewController = previewReady ? previewController : null;
    // รีเซ็ตผลลัพธ์การตรวจจับทั้งหมด
    _frameResults.clear();
    _currentFrameDetections.clear();
    _resetDetectionSession(stopVoice: false);
    notifyListeners();

    // ถ้าโมเดลโหลดพร้อมแล้ว -> เริ่มประมวลผลวิดีโอทันที (ไม่ต้องรอ)
    if (_areModelsReady) {
      unawaited(predictVideo());
    }
  }

  /// ประมวลผลวิดีโอทั้งหมด (ตรวจจับทุกเฟรม) แล้วเล่นผลลัพธ์พร้อม overlay
  Future<void> predictVideo() async {
    // ตรวจสอบเงื่อนไขเบื้องต้น: โมเดลพร้อม + มีบริการวิเคราะห์ + มีไฟล์วิดีโอ
    if (!_areModelsReady ||
        _videoFrameAnalysisService == null ||
        _videoFile == null) {
      _notifyMessage('กรุณาเลือกวิดีโอและรอให้โมเดลโหลดเสร็จ');
      return;
    }

    // ---- รีเซ็ตสถานะก่อนเริ่มประมวลผล ----
    _processing = true;
    _progressValue = 0.0;
    _progressText = 'กำลังเตรียมโฟลเดอร์ชั่วคราว...';
    _frameResults.clear();
    _currentFrameDetections.clear();
    _resetDetectionSession(stopVoice: false);
    _clearVideoController(); // ล้างวิดีโอเก่าที่เล่นอยู่
    notifyListeners();

    try {
      // ส่งประมวลผลวิดีโอทั้งไฟล์ โดยส่ง callback อัปเดตความคืบหน้า
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
            notifyListeners(); // ใช้ guard เพื่อไม่เรียกหลัง dispose
          }
        },
      );

      if (_isDisposed) return;

      // ---- บันทึกผลการประมวลผล ----
      _frameResults = result.frameResults; // ผลรายเฟรม (key = frame index)
      _targetFps = result.targetFps; // FPS จริงที่ใช้

      _notifyMessage('Video processing completed successfully!');

      // สร้างตัวเล่นวิดีโอผลลัพธ์ (ไฟล์ที่ annotate แล้ว) และตั้ง Loop
      _videoController = VideoPlayerController.file(
        File(result.finalVideoPath),
      );
      await _videoController!.initialize();
      if (_isDisposed) return;
      await _videoController!.setLooping(true);

      // ปล่อย preview เก่าออก (ไม่ต้องใช้แล้ว)
      await _selectedPreviewController?.dispose();
      _selectedPreviewController = null;

      // ฟังตำแหน่งการเล่น เพื่อซิงก์ overlay กับเฟรม แล้วเริ่มเล่น
      _videoController!.addListener(_onVideoPositionChanged);
      await _videoController!.play();

      if (!_isDisposed) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error processing video: $e');
      _notifyMessage('Error: $e');
    } finally {
      // ปิดสถานะการประมวลผลเสมอ (ทั้งสำเร็จและล้มเหลว)
      if (!_isDisposed) {
        _processing = false;
        notifyListeners();
      }
    }
  }

  /// ตำแหน่งวิดีโอเปลี่ยน -> อัปเดตผลตรวจจับ/overlay ของเฟรมนั้น
  void _onVideoPositionChanged() {
    // เช็คความพร้อม: ยังไม่ dispose / มีวิดีโอ / วิดีโอ initialize แล้ว
    if (_isDisposed ||
        _videoController == null ||
        !_videoController!.value.isInitialized) {
      return;
    }

    final position = _videoController!.value.position; // ตำแหน่งปัจจุบัน (ms)
    // คำนวณ index เฟรมจากตำแหน่ง: index = ตำแหน่ง(ms) * FPS / 1000
    final frameIndex = (position.inMilliseconds * _targetFps / 1000).floor();

    // ทำงานเฉพาะเมื่อเฟรมเปลี่ยนจากครั้งก่อน (กันงานซ้ำ)
    if (frameIndex != _lastFrameIndex) {
      // เมื่อวิดีโอวนหรือ seek ย้อน ต้องเริ่ม tracking session ใหม่
      if (frameIndex < _lastFrameIndex) {
        _resetDetectionSession();
      }
      _lastFrameIndex = frameIndex;

      // ดึงผลของเฟรมนี้จากตารางผลลัพธ์ (ถ้ามี)
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
        // ไม่มีผลสำหรับเฟรมนี้ -> ล้างการตรวจจับ
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
    if (_videoController == null) return; // ยังไม่มีวิดีโอ -> ไม่ทำอะไร
    if (_videoController!.value.isPlaying) {
      await _videoController!
          .pause(); // เล่นอยู่ -> หยุดให้เสร็จก่อนรีเซ็ต state
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
    _isDisposed = true; // ปิด flag กัน async code ทำงานต่อหลัง dispose
    _resetDetectionSession();
    unawaited(_trafficYolo?.dispose()); // Traffic ไม่ผูกกับ pipeline ปล่อยได้เลย

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
    _selectedPreviewController?.dispose(); // ล้างวิดีโอตัวอย่าง
    super.dispose();
  }
}
