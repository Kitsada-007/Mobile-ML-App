import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:trffic_ilght_app/shared/models/model_types.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/widgets/empty_state_section.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/widgets/full_screen_video.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/widgets/result_image.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/widgets/video_inference_action.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/widgets/video_processing.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/widgets/video_result_section.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/widgets/video_selected_video.dart';
import 'package:trffic_ilght_app/core/services/inference/countdown_reading_stabilizer.dart';
import 'package:trffic_ilght_app/core/services/model_management/model_manager.dart';
import 'package:trffic_ilght_app/core/services/inference/sign_number_pipeline_service.dart';
import 'package:trffic_ilght_app/features/video_detection/data/services/video_frame_analysis_service.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'package:video_player/video_player.dart';

@visibleForTesting
YOLO createVideoYolo(String modelPath) {
  return YOLO(
    modelPath: modelPath,
    task: YOLOTask.detect,
    useMultiInstance: true,
  );
}

class VideoInferenceScreen extends StatefulWidget {
  const VideoInferenceScreen({super.key});

  @override
  State<VideoInferenceScreen> createState() => _VideoInferenceScreenState();
}

class _VideoInferenceScreenState extends State<VideoInferenceScreen> {
  final ImagePicker _picker = ImagePicker();

  // เพิ่ม Set สำหรับเก็บชื่อ Class ที่ตรวจพบแบบไม่ซ้ำกัน
  final Set<String> _detectedClasses = {};
  final Set<String> _detectedNumbers = {};
  final CountdownReadingStabilizer _countdownStabilizer =
      CountdownReadingStabilizer();
  Uint8List? _imageBytes;
  Uint8List? _annotatedImage;

  YOLO? _trafficYolo;
  YOLO? _numberYolo;
  VideoFrameAnalysisService? _videoFrameAnalysisService;
  String? _trafficModelPath;
  String? _numberModelPath;
  bool _areModelsReady = false;
  late final ModelManager _modelManager;

  VideoPlayerController? _videoController;
  File? _videoFile;

  bool _processing = false;
  double _progressValue = 0.0;
  String _progressText = "";

  @override
  void initState() {
    super.initState();
    _modelManager = ModelManager();
    _initializeModels();
  }

  @override
  void dispose() {
    unawaited(_trafficYolo?.dispose());
    unawaited(_numberYolo?.dispose());
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool hasVideoResult =
        _videoController != null && _videoController!.value.isInitialized;
    final bool hasImageResult = _annotatedImage != null || _imageBytes != null;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Video Inference',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        foregroundColor:
            theme.appBarTheme.foregroundColor ?? colorScheme.onSurface,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  if (!_areModelsReady)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        color: colorScheme.primary,
                        backgroundColor: colorScheme.onSurface.withValues(
                          alpha: 0.08,
                        ),
                      ),
                    ),

                  if (hasVideoResult) ...[
                    ResultVideoSection(
                      controller: _videoController!,
                      onOpenFullScreen: _openFullScreen,
                      onTogglePlayPause: _togglePlayPause,
                    ),

                    // แสดงผล Class และตัวเลขที่พบหลังประมวลผลเสร็จ
                    if (_detectedClasses.isNotEmpty ||
                        _detectedNumbers.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colorScheme.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.analytics_outlined,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "วัตถุที่ตรวจพบในวิดีโอ:",
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _detectedClasses.map((className) {
                                return Chip(
                                  label: Text(className),
                                  backgroundColor: colorScheme.primaryContainer,
                                  labelStyle: TextStyle(
                                    color: colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  side: BorderSide.none,
                                );
                              }).toList(),
                            ),
                            if (_detectedNumbers.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(
                                'ตัวเลขที่ตรวจพบ:',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _detectedNumbers.map((number) {
                                  return Chip(
                                    avatar: const Icon(
                                      Icons.numbers_rounded,
                                      size: 18,
                                    ),
                                    label: Text(number),
                                    backgroundColor:
                                        colorScheme.secondaryContainer,
                                    labelStyle: TextStyle(
                                      color: colorScheme.onSecondaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    side: BorderSide.none,
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ] else if (hasImageResult)
                    ResultImageSection(
                      imageBytes: _annotatedImage ?? _imageBytes!,
                    )
                  else if (!_processing)
                    const EmptyStateSection(),

                  const SizedBox(height: 12),

                  if (_videoFile != null && !_processing)
                    SelectedVideoCard(
                      fileName: _videoFile!.path.split('/').last,
                    ),

                  if (_processing) ...[
                    const SizedBox(height: 12),
                    ProcessingCard(
                      progressValue: _progressValue,
                      progressText: _progressText,
                    ),
                  ],

                  const SizedBox(height: 16),
                  Text(
                    "อัปโหลดวิดีโอได้ไม่เกิน 50 MB\nและความยาวไม่เกิน 15 วินาที",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: theme.shadowColor.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: InferenceActionBar(
                  processing: _processing,
                  videoFile: _videoFile,
                  onPickVideo: _pickVideo,
                  onRunInference: _predictVideo,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ฟังก์ชันสำหรับแปลชื่อ Class จาก Model เป็นภาษาไทยทางการ
  String _getFormalThaiName(String className) {
    switch (className) {
      case 'dont_go_straight_arrow':
        return "ป้ายห้ามตรงไป";
      case 'dont_turn_left':
        return "ป้ายห้ามเลี้ยวซ้าย";
      case 'dont_turn_right':
        return "ป้ายห้ามเลี้ยวขวา";
      case 'go_straight_arrow':
        return "ป้ายบังคับให้ตรงไป";
      case 'green_light_circle':
        return "สัญญาณไฟจราจรสีเขียว";
      case 'off_light':
        return "สัญญาณไฟจราจรขัดข้อง";
      case 'red_light_circle':
        return "สัญญาณไฟจราจรสีแดง";
      case 'sign_number':
        return "สัญญาณไฟนับถอยหลัง";
      case 'turn_left':
        return "สัญญาณไฟเลี้ยวซ้าย";
      case 'turn_right':
        return "สัญญาณไฟเลี้ยวขวา";
      case 'yellow_light':
        return "สัญญาณไฟจราจรสีเหลือง";
      default:
        return className; // ถ้าไม่มีในลิสต์ ให้แสดงชื่อดั้งเดิมไปก่อน
    }
  }

  void _openFullScreen() {
    if (_videoController == null) return;

    Get.to(() => FullScreenVideoPage(controller: _videoController!))?.then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _initializeModels() async {
    YOLO? trafficYolo;
    YOLO? numberYolo;
    try {
      _trafficModelPath = await _modelManager.getModelPath(ModelType.traffic);
      _numberModelPath = await _modelManager.getModelPath(ModelType.number);

      if (_trafficModelPath == null || _numberModelPath == null) {
        _showSnackBar('ไม่พบไฟล์โมเดล Traffic หรือ Number');
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

      if (!mounted) {
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
      setState(() => _areModelsReady = true);
    } catch (e) {
      await trafficYolo?.dispose();
      await numberYolo?.dispose();
      if (!mounted) return;

      final error = YOLOErrorHandler.handleError(
        e,
        'Failed to load video inference models',
      );
      _showSnackBar('Error loading models: ${error.message}');
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

  Future<bool> _validateVideo(File videoFile) async {
    final int sizeInBytes = await videoFile.length();
    final double sizeInMb = sizeInBytes / (1024 * 1024);

    if (sizeInMb > 50.0) {
      _showSnackBar(
        "ไฟล์วิดีโอใหญ่เกินไป (${sizeInMb.toStringAsFixed(1)} MB) กรุณาเลือกไฟล์ไม่เกิน 50 MB",
      );
      return false;
    }

    final infoSession = await FFprobeKit.getMediaInformation(videoFile.path);
    final info = infoSession.getMediaInformation();

    if (info != null && info.getDuration() != null) {
      final double durationInSeconds =
          double.tryParse(info.getDuration()!) ?? 0.0;
      if (durationInSeconds > 15.0) {
        _showSnackBar(
          "วิดีโอยาวเกินไป (${durationInSeconds.toStringAsFixed(1)} วิ) กรุณาเลือกวิดีโอไม่เกิน 15 วินาที",
        );
        return false;
      }
    }

    return true;
  }

  Future<void> _pickVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    final File selectedFile = File(file.path);
    final bool isValid = await _validateVideo(selectedFile);
    if (!isValid) return;
    _videoController?.dispose();
    setState(() {
      _videoFile = selectedFile;
      _videoController = null;
      _annotatedImage = null;
      _detectedClasses.clear(); // เคลียร์ผลลัพธ์เดิมเมื่อเลือกวิดีโอใหม่
      _detectedNumbers.clear();
      _countdownStabilizer.reset();
    });
  }

  Future<void> _predictVideo() async {
    if (!_areModelsReady ||
        _videoFrameAnalysisService == null ||
        _videoFile == null) {
      _showSnackBar('กรุณาเลือกวิดีโอและรอให้โมเดลโหลดเสร็จ');
      return;
    }

    setState(() {
      _processing = true;
      _progressValue = 0.0;
      _progressText = "กำลังเตรียมโฟลเดอร์ชั่วคราว...";
      _detectedClasses.clear(); // เคลียร์ผลลัพธ์เดิมก่อนเริ่มประมวลผล
      _detectedNumbers.clear();
      _countdownStabilizer.reset();
      _annotatedImage = null;
      _videoController?.dispose();
      _videoController = null;
    });

    final directory = await getTemporaryDirectory();
    final String inputFolder = '${directory.path}/yolo_frames_in';
    final String outputFolder = '${directory.path}/yolo_frames_out';
    final String finalVideoPath = '${directory.path}/result_video.mp4';

    try {
      await _extractAndProcessFrames(
        inputFolder: inputFolder,
        outputFolder: outputFolder,
      );

      await _stitchFramesToVideo(
        outputFolder: outputFolder,
        finalVideoPath: finalVideoPath,
      );

      _showSnackBar('Video processing completed successfully!');

      _videoController = VideoPlayerController.file(File(finalVideoPath));
      await _videoController!.initialize();
      await _videoController!.setLooping(true);
      await _videoController!.play();

      if (mounted) {
        setState(() {}); // อัปเดต UI ให้แสดงวิดีโอและรายชื่อ Class ที่พบ
      }
    } catch (e) {
      debugPrint("Error: $e");
      _showSnackBar('Error: $e');
    } finally {
      try {
        final outDir = Directory(outputFolder);
        if (await outDir.exists()) {
          await outDir.delete(recursive: true);
        }
      } catch (cleanupError) {
        debugPrint('Failed to clean up output folder: $cleanupError');
      }

      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<void> _extractAndProcessFrames({
    required String inputFolder,
    required String outputFolder,
  }) async {
    final frameAnalysisService = _videoFrameAnalysisService;
    if (frameAnalysisService == null) {
      throw StateError('Video inference models are not ready');
    }

    for (final path in [inputFolder, outputFolder]) {
      final dir = Directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      await dir.create(recursive: true);
    }
    const int targetFps = 15;
    if (mounted) {
      setState(() {
        _progressText = "กำลังสกัดเฟรมจากวิดีโอ (15 FPS)...";
      });
    }
    final String extractCmd =
        '-threads 0 '
        '-i "${_videoFile!.path}" '
        '-t 15 '
        '-vf "fps=$targetFps,scale=640:-1:flags=fast_bilinear" '
        '-q:v 15 '
        '-y "$inputFolder/frame_%05d.jpg"';
    await FFmpegKit.execute(extractCmd);
    final dirIn = Directory(inputFolder);
    final List<FileSystemEntity> frameFiles = dirIn.listSync()
      ..sort((a, b) => a.path.compareTo(b.path));

    final int totalFrames = frameFiles.length;
    int currentFrame = 0;
    for (final fileEntity in frameFiles) {
      if (fileEntity is! File) {
        continue;
      }
      currentFrame++;
      if (mounted) {
        setState(() {
          _progressValue = currentFrame / totalFrames;
          _progressText = "กำลังตรวจจับ $currentFrame / $totalFrames เฟรม";
        });
      }

      final String fileName = fileEntity.uri.pathSegments.last;
      final File outFile = File('$outputFolder/$fileName');

      try {
        final bytes = await fileEntity.readAsBytes();
        final result = await frameAnalysisService.analyze(bytes);

        for (final detection in result.detections) {
          _detectedClasses.add(_getFormalThaiName(detection.className));
        }
        final detectedNumber = _countdownStabilizer.add(result.detectedNumber);
        if (detectedNumber != null && detectedNumber.isNotEmpty) {
          _detectedNumbers.add(detectedNumber);
        }

        await outFile.writeAsBytes(result.outputImageBytes);
      } catch (frameError) {
        debugPrint('Error predicting frame $fileName: $frameError');
        await fileEntity.copy(outFile.path);
      } finally {
        if (await fileEntity.exists()) {
          await fileEntity.delete();
        }
      }
    }
  }

  Future<void> _stitchFramesToVideo({
    required String outputFolder,
    required String finalVideoPath,
  }) async {
    const int targetFps = 15;

    if (mounted) {
      setState(() {
        _progressValue = 0.0;
        _progressText = "กำลังรวมวิดีโอกลับคืน...";
      });
    }

    final String stitchCmd =
        '-threads 0 '
        '-framerate $targetFps '
        '-i "$outputFolder/frame_%05d.jpg" '
        '-i "${_videoFile!.path}" '
        '-t 15 '
        '-c:v libx264 '
        '-preset ultrafast '
        '-pix_fmt yuv420p '
        '-c:a copy '
        '-map 0:v:0 '
        '-map 1:a:0? '
        '-y "$finalVideoPath"';

    final stitchSession = await FFmpegKit.execute(stitchCmd);
    final returnCode = await stitchSession.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      throw Exception('Failed to create final video.');
    }
  }

  void _togglePlayPause() {
    if (_videoController == null) return;

    setState(() {
      if (_videoController!.value.isPlaying) {
        _videoController!.pause();
      } else {
        _videoController!.play();
      }
    });
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}
