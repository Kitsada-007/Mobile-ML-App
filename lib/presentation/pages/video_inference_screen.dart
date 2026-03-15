import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/src/extension_navigation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:trffic_ilght_app/core/models/models.dart';
import 'package:trffic_ilght_app/presentation/widgets/video_widgets/empty_state_section.dart';
import 'package:trffic_ilght_app/presentation/widgets/video_widgets/full_screen_video.dart';
import 'package:trffic_ilght_app/presentation/widgets/video_widgets/result_image.dart';
import 'package:trffic_ilght_app/presentation/widgets/video_widgets/video_Inference_action.dart';
import 'package:trffic_ilght_app/presentation/widgets/video_widgets/video_processing.dart';
import 'package:trffic_ilght_app/presentation/widgets/video_widgets/video_result_section.dart';
import 'package:trffic_ilght_app/presentation/widgets/video_widgets/video_selected_video.dart';
import 'package:trffic_ilght_app/services/model_manager.dart';
import 'package:ultralytics_yolo/utils/error_handler.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:video_player/video_player.dart';

class VideoInferenceScreen extends StatefulWidget {
  const VideoInferenceScreen({super.key});

  @override
  State<VideoInferenceScreen> createState() => _VideoInferenceScreenState();
}

class _VideoInferenceScreenState extends State<VideoInferenceScreen> {
  final ImagePicker _picker = ImagePicker();

  List<Map<String, dynamic>> _detections = [];
  Uint8List? _imageBytes;
  Uint8List? _annotatedImage;

  late YOLO _yolo;
  String? _modelPath;
  bool _isModelReady = false;
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
    _initializeYOLO();
  }

  @override
  void dispose() {
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
            theme.appBarTheme.foregroundColor ?? colorScheme.onBackground,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  if (!_isModelReady)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        color: colorScheme.primary,
                        backgroundColor: colorScheme.onBackground.withOpacity(
                          0.08,
                        ),
                      ),
                    ),

                  if (hasVideoResult)
                    ResultVideoSection(
                      controller: _videoController!,
                      onOpenFullScreen: _openFullScreen,
                      onTogglePlayPause: _togglePlayPause,
                    )
                  else if (hasImageResult)
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
                  Text(
                    "อัปโหลดวิดีโอได้ไม่เกิน 50 MB\nและความยาวไม่เกิน 15 วินาที",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.7),
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
                    color: theme.shadowColor.withOpacity(0.12),
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

  void _openFullScreen() {
    if (_videoController == null) return;

    Get.to(() => FullScreenVideoPage(controller: _videoController!))?.then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _initializeYOLO() async {
    _modelPath = await _modelManager.getModelPath(ModelType.bestFloat16traffic);
    if (_modelPath == null) return;

    _yolo = YOLO(modelPath: _modelPath!, task: YOLOTask.detect, useGpu: false);

    try {
      await _yolo.loadModel();
      if (mounted) {
        setState(() => _isModelReady = true);
      }
    } catch (e) {
      if (!mounted) return;

      final error = YOLOErrorHandler.handleError(
        e,
        'Failed to load model $_modelPath for task ${YOLOTask.detect.name}',
      );
      _showSnackBar('Error loading model: ${error.message}');
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
    });
  }

  Future<void> _predictVideo() async {
    if (!_isModelReady || _videoFile == null) {
      _showSnackBar("Please select a video and wait for model to load.");
      return;
    }

    setState(() {
      _processing = true;
      _progressValue = 0.0;
      _progressText = "กำลังเตรียมโฟลเดอร์ชั่วคราว...";
      _detections = [];
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
        setState(() {});
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
        final result = await _yolo.predict(bytes);
        final annotatedBytes = result['annotatedImage'] as Uint8List?;

        if (annotatedBytes != null) {
          await outFile.writeAsBytes(annotatedBytes);
        } else {
          await fileEntity.copy(outFile.path);
        }
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
