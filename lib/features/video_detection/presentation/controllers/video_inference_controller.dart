import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:trffic_ilght_app/core/services/inference/countdown_reading_stabilizer.dart';
import 'package:trffic_ilght_app/core/services/inference/sign_number_pipeline_service.dart';
import 'package:trffic_ilght_app/core/services/model_management/model_manager.dart';
import 'package:trffic_ilght_app/features/video_detection/data/services/video_frame_analysis_service.dart';
import 'package:trffic_ilght_app/features/video_detection/data/services/video_input_validator.dart';
import 'package:trffic_ilght_app/features/video_detection/data/services/video_processing_service.dart';
import 'package:trffic_ilght_app/shared/models/model_types.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:video_player/video_player.dart';

import 'package:trffic_ilght_app/core/services/voice/traffic_voice_service.dart';

@visibleForTesting
YOLO createVideoYolo(String modelPath) {
  return YOLO(
    modelPath: modelPath,
    task: YOLOTask.detect,
    useMultiInstance: true,
  );
}

/// Controller responsible for business logic, model initialization, state management,
/// and realtime video frame overlay synchronization.
class VideoInferenceController extends ChangeNotifier {
  VideoInferenceController({
    ImagePicker? picker,
    VideoInputValidator? videoValidator,
    ModelManager? modelManager,
    VideoProcessingService? videoProcessingService,
    TrafficVoiceService? voiceService,
  }) : _picker = picker ?? ImagePicker(),
       _videoValidator = videoValidator ?? const VideoInputValidator(),
       _modelManager = modelManager ?? ModelManager(),
       _videoProcessingService =
           videoProcessingService ?? VideoProcessingService(),
       _voiceService = voiceService ?? TrafficVoiceService();

  final ImagePicker _picker;
  final VideoInputValidator _videoValidator;
  final ModelManager _modelManager;
  final VideoProcessingService _videoProcessingService;
  final TrafficVoiceService _voiceService;
  final CountdownReadingStabilizer _countdownStabilizer =
      CountdownReadingStabilizer();

  final Set<String> _detectedClasses = {};
  final Set<String> _detectedNumbers = {};
  Map<int, FrameAnalysisResult> _frameResults = {};
  int _targetFps = 5;
  int _lastFrameIndex = -1;

  List<YOLOResult> _currentFrameDetections = [];
  String? _currentDetectedNumber;
  List<String> _currentFormalNames = [];
  List<String> _currentAlertMessages = [];
  double? _lastDetectionConfidence;

  Uint8List? _imageBytes;
  Uint8List? _annotatedImage;

  YOLO? _trafficYolo;
  YOLO? _numberYolo;
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

  // Getters
  bool get areModelsReady => _areModelsReady;
  bool get isProcessing => _processing;
  double get progressValue => _progressValue;
  String get progressText => _progressText;
  Set<String> get detectedClasses => Set.unmodifiable(_detectedClasses);
  Set<String> get detectedNumbers => Set.unmodifiable(_detectedNumbers);
  List<YOLOResult> get currentFrameDetections => _currentFrameDetections;
  String? get currentDetectedNumber => _currentDetectedNumber;
  List<String> get currentFormalNames => List.unmodifiable(_currentFormalNames);
  List<String> get currentAlertMessages =>
      List.unmodifiable(_currentAlertMessages);
  double? get lastDetectionConfidence => _lastDetectionConfidence;

  Uint8List? get imageBytes => _imageBytes;
  Uint8List? get annotatedImage => _annotatedImage;
  VideoPlayerController? get videoController => _videoController;
  VideoPlayerController? get selectedPreviewController =>
      _selectedPreviewController;
  File? get videoFile => _videoFile;
  String? get snackBarMessage => _snackBarMessage;

  void clearSnackBarMessage() {
    _snackBarMessage = null;
  }

  Future<void> initializeModels() async {
    YOLO? trafficYolo;
    YOLO? numberYolo;
    try {
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

      if (_isDisposed) {
        await trafficYolo.dispose();
        await numberYolo.dispose();
        return;
      }

      _trafficYolo = trafficYolo;
      _numberYolo = numberYolo;
      _videoFrameAnalysisService = VideoFrameAnalysisService(
        trafficYolo: trafficYolo,
        signNumberPipeline: SignNumberPipelineService(digitYolo: numberYolo),
      );
      _areModelsReady = true;
      notifyListeners();
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
      if (replacement == null || replacement == initialPath) rethrow;
      return _loadYolo(replacement);
    }
  }

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
      await previewController.seekTo(Duration.zero);
      previewReady = true;
    } catch (_) {
      await previewController.dispose();
    }
    _clearVideoController();
    await _selectedPreviewController?.dispose();

    _videoFile = selectedFile;
    _selectedPreviewController = previewReady ? previewController : null;
    _annotatedImage = null;
    _detectedClasses.clear();
    _detectedNumbers.clear();
    _frameResults.clear();
    _currentFrameDetections.clear();
    _currentDetectedNumber = null;
    _currentFormalNames.clear();
    _currentAlertMessages.clear();
    _lastDetectionConfidence = null;
    _countdownStabilizer.reset();
    notifyListeners();

    if (_areModelsReady) {
      unawaited(predictVideo());
    }
  }

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
    _detectedClasses.clear();
    _detectedNumbers.clear();
    _frameResults.clear();
    _currentFrameDetections.clear();
    _currentDetectedNumber = null;
    _currentFormalNames.clear();
    _currentAlertMessages.clear();
    _lastDetectionConfidence = null;
    _countdownStabilizer.reset();
    _annotatedImage = null;
    _clearVideoController();
    notifyListeners();

    try {
      final result = await _videoProcessingService.processVideo(
        videoFile: _videoFile!,
        frameAnalysisService: _videoFrameAnalysisService!,
        countdownStabilizer: _countdownStabilizer,
        onProgress: (progressValue, progressText) {
          if (!_isDisposed) {
            _progressValue = progressValue;
            _progressText = progressText;
            notifyListeners();
          }
        },
      );

      _detectedClasses.addAll(result.detectedClasses);
      _detectedNumbers.addAll(result.detectedNumbers);
      _frameResults = result.frameResults;
      _targetFps = result.targetFps;

      _notifyMessage('Video processing completed successfully!');

      _videoController = VideoPlayerController.file(
        File(result.finalVideoPath),
      );
      await _videoController!.initialize();
      await _videoController!.setLooping(true);

      _videoController!.addListener(_onVideoPositionChanged);
      await _videoController!.play();

      notifyListeners();
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

  void _onVideoPositionChanged() {
    if (_isDisposed ||
        _videoController == null ||
        !_videoController!.value.isInitialized) {
      return;
    }

    final position = _videoController!.value.position;
    final frameIndex = (position.inMilliseconds * _targetFps / 1000).floor();

    if (frameIndex != _lastFrameIndex) {
      _lastFrameIndex = frameIndex;
      final frameResult = _frameResults[frameIndex];
      if (frameResult != null) {
        _currentFrameDetections = frameResult.detections;
        _currentDetectedNumber = frameResult.detectedNumber;
        _updateCurrentFrameAnalysis(
          frameResult.detections,
          frameResult.detectedNumber,
        );
        notifyListeners();
      }
    }
  }

  void _updateCurrentFrameAnalysis(
    List<YOLOResult> detections,
    String? detectedNumber,
  ) {
    if (detections.isEmpty &&
        (detectedNumber == null || detectedNumber.isEmpty)) {
      _currentFormalNames = [];
      _currentAlertMessages = [];
      _lastDetectionConfidence = null;
      return;
    }

    double maxConf = 0.0;
    final tempFormalNames = <String>[];
    final tempAlertMessages = <String>[];

    final sorted = List<YOLOResult>.from(detections)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    for (final det in sorted) {
      if (det.confidence > maxConf) maxConf = det.confidence;
      final formal = _voiceService.getFormalThaiName(det.className);
      final alert = _voiceService.getThaiMessage(det.className);
      if (!tempFormalNames.contains(formal)) {
        tempFormalNames.add(formal);
        tempAlertMessages.add(alert);
      }
    }

    if (detectedNumber != null &&
        detectedNumber.isNotEmpty &&
        !tempFormalNames.contains('สัญญาณไฟนับถอยหลัง')) {
      tempFormalNames.add(_voiceService.getFormalThaiName('sign_number'));
      tempAlertMessages.add(_voiceService.getThaiMessage('sign_number'));
    }

    _currentFormalNames = tempFormalNames;
    _currentAlertMessages = tempAlertMessages;
    _lastDetectionConfidence = maxConf > 0 ? maxConf : null;
  }

  void togglePlayPause() {
    if (_videoController == null) return;
    if (_videoController!.value.isPlaying) {
      _videoController!.pause();
    } else {
      _videoController!.play();
    }
    notifyListeners();
  }

  void _clearVideoController() {
    if (_videoController != null) {
      _videoController!.removeListener(_onVideoPositionChanged);
      _videoController!.dispose();
      _videoController = null;
    }
  }

  void _notifyMessage(String msg) {
    _snackBarMessage = msg;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    unawaited(_trafficYolo?.dispose());
    unawaited(_numberYolo?.dispose());
    _clearVideoController();
    _selectedPreviewController?.dispose();
    super.dispose();
  }
}
