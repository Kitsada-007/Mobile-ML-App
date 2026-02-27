// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'dart:io';
import 'dart:typed_data';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart'; // ยังต้องเก็บไว้เพื่อใช้เช็คความยาววิดีโอใน _validateVideo
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:trffic_ilght_app/core/models/models.dart';
import 'package:ultralytics_yolo/yolo.dart';

import 'package:ultralytics_yolo/utils/error_handler.dart';
import 'package:video_player/video_player.dart';
import '../../services/model_manager.dart';

/// A screen that demonstrates YOLO inference on a single video/image.
class VideoInferenceScreen extends StatefulWidget {
  const VideoInferenceScreen({super.key});

  @override
  State<VideoInferenceScreen> createState() => _VideoInferenceScreen();
}

class _VideoInferenceScreen extends State<VideoInferenceScreen> {
  final _picker = ImagePicker();
  List<Map<String, dynamic>> _detections = [];
  Uint8List? _imageBytes;
  Uint8List? _annotatedImage;
  late YOLO _yolo;
  String? _modelPath;
  bool _isModelReady = false;
  late final ModelManager _modelManager;

  VideoPlayerController? _videoController;
  File? _videoFile;

  // ตัวแปรควบคุมสถานะ
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

  // ฟังก์ชันเรียกหน้า Full Screen
  void _openFullScreen() {
    if (_videoController == null) return;

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) =>
                FullScreenVideoPage(controller: _videoController!),
          ),
        )
        .then((_) {
          // เมื่อกลับมาจากหน้าเต็มจอ ให้รีเฟรช UI เผื่อสถานะปุ่ม Play/Pause เปลี่ยนแปลง
          if (mounted) setState(() {});
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          Colors.grey[50], // เปลี่ยนพื้นหลังให้เป็นสีเทาอ่อนๆ ดูสบายตา
      appBar: AppBar(
        title: const Text(
          'Video & Image Inference',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),

            // 🌟 1. ส่วนของปุ่มกด (Modern Buttons)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _processing ? null : _pickVideo,
                  icon: const Icon(Icons.video_library_rounded),
                  label: const Text('Pick Video'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                ),
                const SizedBox(width: 15),
                ElevatedButton.icon(
                  onPressed: (_processing || _videoFile == null)
                      ? null
                      : _predictVideo,
                  icon: _processing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(_processing ? 'Processing...' : 'Run Inference'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: _processing ? 0 : 4,
                  ),
                ),
              ],
            ),

            // 🌟 2. แสดงชื่อไฟล์ที่เลือก (Pill Shape)
            if (_videoFile != null && !_processing)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.movie_creation_outlined,
                        size: 16,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _videoFile!.path.split('/').last,
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ส่วนแสดงสถานะโมเดล
            if (!_isModelReady)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: LinearProgressIndicator(minHeight: 2),
              ),

            // 🌟 3. แถบแสดงสถานะโหลด Progress Bar (Modern Card)
            if (_processing)
              Container(
                margin: const EdgeInsets.all(20.0),
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      _progressText,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 15),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: _progressValue > 0 ? _progressValue : null,
                        minHeight: 12,
                        backgroundColor: Colors.grey[200],
                        color: Colors.blueAccent,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_progressValue > 0)
                      Text(
                        "${(_progressValue * 100).toStringAsFixed(1)} %",
                        style: const TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),

            const SizedBox(height: 10),

            // 🌟 4. ส่วนแสดงผลรูปภาพ/วิดีโอ (Soft Shadows & Rounded Corners)
            Expanded(
              child: SingleChildScrollView(
                physics:
                    const BouncingScrollPhysics(), // ทำให้การเลื่อนดูสมูทขึ้น
                child: Column(
                  children: [
                    // กรณีมีวิดีโอพร้อมเล่น
                    if (_videoController != null &&
                        _videoController!.value.isInitialized)
                      Column(
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10.0),
                            child: Text(
                              'Result Video',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blueAccent.withOpacity(0.2),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            // ใช้ ClipRRect เพื่อตัดขอบวิดีโอให้โค้งตาม Container
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: AspectRatio(
                                aspectRatio:
                                    _videoController!.value.aspectRatio,
                                // แก้ไข Stack วิดีโอเดิม ให้มีปุ่มขยายจอที่มุมขวาบน
                                child: Stack(
                                  alignment: Alignment.bottomCenter,
                                  children: [
                                    VideoPlayer(_videoController!),
                                    VideoProgressIndicator(
                                      _videoController!,
                                      allowScrubbing: true,
                                      colors: const VideoProgressColors(
                                        playedColor: Colors.blueAccent,
                                        bufferedColor: Colors.white38,
                                        backgroundColor: Colors.transparent,
                                      ),
                                    ),
                                    // 🌟 เพิ่มปุ่ม Full Screen ตรงนี้ 🌟
                                    Positioned(
                                      top: 5,
                                      right: 5,
                                      child: IconButton(
                                        icon: const Icon(
                                          Icons.fullscreen_rounded,
                                          color: Colors.white,
                                          size: 30,
                                        ),
                                        onPressed:
                                            _openFullScreen, // กดแล้วเรียกหน้าแนวนอน
                                        style: IconButton.styleFrom(
                                          backgroundColor: Colors.black45,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // ปุ่ม Play/Pause สไตล์แอปเล่นเพลง
                          Container(
                            margin: const EdgeInsets.only(top: 10, bottom: 30),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: Icon(
                                _videoController!.value.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 40,
                                color: Colors.blueAccent,
                              ),
                              padding: const EdgeInsets.all(15),
                              onPressed: () {
                                setState(() {
                                  _videoController!.value.isPlaying
                                      ? _videoController!.pause()
                                      : _videoController!.play();
                                });
                              },
                            ),
                          ),
                        ],
                      )
                    // กรณีแสดงภาพนิ่ง
                    else if (_annotatedImage != null || _imageBytes != null)
                      Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.memory(
                            _annotatedImage ?? _imageBytes!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      )
                    // 🌟 5. Empty State (ตอนยังไม่เลือกอะไรเลย)
                    else if (!_processing)
                      Container(
                        height: 250,
                        margin: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.grey.shade300,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.video_call_rounded,
                                size: 60,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                "No video selected",
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Initializes the YOLO model for inference
  Future<void> _initializeYOLO() async {
    _modelPath = await _modelManager.getModelPath(ModelType.bestFloat16traffic);
    if (_modelPath == null) return;
    _yolo = YOLO(modelPath: _modelPath!, task: YOLOTask.detect, useGpu: false);
    try {
      await _yolo.loadModel();
      if (mounted) setState(() => _isModelReady = true);
    } catch (e) {
      if (mounted) {
        final error = YOLOErrorHandler.handleError(
          e,
          'Failed to load model $_modelPath for task ${YOLOTask.detect.name}',
        );
        _showSnackBar('Error loading model: ${error.message}');
      }
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
      if (durationInSeconds > 60.0) {
        _showSnackBar(
          "วิดีโอยาวเกินไป (${durationInSeconds.toStringAsFixed(1)} วิ) กรุณาเลือกวิดีโอไม่เกิน 15 วินาที",
        );
        return false;
      }
    }
    return true;
  }

  /// Picks an video from the gallery and runs inference
  Future<void> _pickVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;

    final File selectedFile = File(file.path);
    bool isValid = await _validateVideo(selectedFile);

    if (isValid) {
      _videoController?.dispose();
      setState(() {
        _videoFile = selectedFile;
        _videoController = null;
        _annotatedImage = null;
      });
    }
  }

  Future<void> _predictVideo() async {
    if (!_isModelReady || _videoFile == null) {
      return _showSnackBar("Please select a video and wait for model to load.");
    }

    setState(() {
      _processing = true;
      _progressValue = 0.0;
      _progressText = "กำลังเตรียมไฟล์วิดีโอ...";
      _detections = [];
      _annotatedImage = null;
      _videoController?.dispose();
      _videoController = null;
    });

    try {
      final directory = await getTemporaryDirectory();
      final String inputFolder = '${directory.path}/yolo_frames_in';
      final String outputFolder = '${directory.path}/yolo_frames_out';
      final String finalVideoPath = '${directory.path}/result_video.mp4';

      for (String path in [inputFolder, outputFolder]) {
        final dir = Directory(path);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
        dir.createSync(recursive: true);
      }

      // 🌟 ตั้งเป้าหมาย FPS เป็น 15 เพื่อความสมดุลระหว่างความลื่นไหลและความเร็ว 🌟
      final int targetFps = 15;

      // 🚀 สกัดเฟรม: ดึงทุกคอร์ที่มี (-threads 0) + ย่อแบบเร็ว (fast_bilinear)
      setState(() => _progressText = "กำลังสกัดเฟรมจากวิดีโอ (15 FPS)...");
      final String extractCmd =
          "-threads 0 -i ${_videoFile!.path} -t 15 -vf \"fps=$targetFps,scale=640:-1:flags=fast_bilinear\" -q:v 15 -y $inputFolder/frame_%05d.jpg";
      await FFmpegKit.execute(extractCmd);

      final dirIn = Directory(inputFolder);
      final List<FileSystemEntity> frameFiles = dirIn.listSync()
        ..sort((a, b) => a.path.compareTo(b.path));

      int totalFrames = frameFiles.length;
      int currentFrame = 0;

      // 2. ประมวลผลภาพด้วย YOLO
      for (var fileEntity in frameFiles) {
        if (fileEntity is File) {
          currentFrame++;

          if (mounted) {
            setState(() {
              _progressValue = currentFrame / totalFrames;
              _progressText = "กำลังตรวจจับ $currentFrame / $totalFrames เฟรม";
            });
          }

          final bytes = await fileEntity.readAsBytes();
          final result = await _yolo.predict(bytes);
          final annotatedBytes = result['annotatedImage'] as Uint8List?;

          if (annotatedBytes != null) {
            final String fileName = fileEntity.uri.pathSegments.last;
            final File outFile = File('$outputFolder/$fileName');
            await outFile.writeAsBytes(annotatedBytes);
          }
          await fileEntity.delete();
        }
      }

      // 3. รวมภาพกลับเป็นวิดีโอ MP4
      if (mounted) {
        setState(() {
          _progressValue = 0.0;
          _progressText = "กำลังรวมวิดีโอกลับคืน...";
        });
      }

      // ใช้ targetFps ในการเย็บไฟล์ และกำหนดความยาวสูงสุด 15 วินาที
      // 🚀 รวมวิดีโอ: ดึงทุกคอร์ที่มี (-threads 0) + เข้ารหัสขั้นสุดยอดความไว (-preset ultrafast)
      final String stitchCmd =
          "-threads 0 -framerate $targetFps -i $outputFolder/frame_%05d.jpg -i ${_videoFile!.path} -t 15 -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a copy -map 0:v:0 -map 1:a:0? -y $finalVideoPath";

      final stitchSession = await FFmpegKit.execute(stitchCmd);
      final returnCode = await stitchSession.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        _showSnackBar('Video processing completed successfully!');

        _videoController = VideoPlayerController.file(File(finalVideoPath));
        await _videoController!.initialize();
        _videoController!.setLooping(true);
        _videoController!.play();

        if (mounted) setState(() {});
      } else {
        _showSnackBar('Failed to create final video.');
      }
    } catch (e) {
      debugPrint("Error: $e");
      _showSnackBar('Error: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _showSnackBar(String msg) => mounted
      ? ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)))
      : null;
}

// ==========================================================
// 🌟 หน้าจอสำหรับเล่นวิดีโอแบบเต็มจอ (Full Screen) 🌟
// ==========================================================
class FullScreenVideoPage extends StatefulWidget {
  final VideoPlayerController controller;
  const FullScreenVideoPage({Key? key, required this.controller})
    : super(key: key);

  @override
  State<FullScreenVideoPage> createState() => _FullScreenVideoPageState();
}

class _FullScreenVideoPageState extends State<FullScreenVideoPage> {
  @override
  void initState() {
    super.initState();
    // เมื่อเปิดหน้านี้ บังคับให้หน้าจอเป็นแนวนอน (Landscape)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
  }

  @override
  void dispose() {
    // เมื่อปิดหน้านี้ บังคับให้หน้าจอกลับมาเป็นแนวตั้ง (Portrait) เหมือนเดิม
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // พื้นหลังโรงหนัง
      body: SafeArea(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. ตัววิดีโอเต็มจอ
            AspectRatio(
              aspectRatio: widget.controller.value.aspectRatio,
              child: VideoPlayer(widget.controller),
            ),

            // 2. แถบเลื่อนเวลา (Scrubber)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: VideoProgressIndicator(
                widget.controller,
                allowScrubbing: true,
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 20,
                ),
                colors: const VideoProgressColors(
                  playedColor: Colors.blueAccent,
                  bufferedColor: Colors.white38,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),

            // 3. ปุ่มกด Play/Pause กลางจอ
            GestureDetector(
              onTap: () {
                setState(() {
                  widget.controller.value.isPlaying
                      ? widget.controller.pause()
                      : widget.controller.play();
                });
              },
              child: Container(
                color: Colors.transparent, // รับการทัชทั้งหน้าจอ
                child: Center(
                  child: AnimatedOpacity(
                    opacity: widget.controller.value.isPlaying
                        ? 0.0
                        : 1.0, // ถ้าเล่นอยู่ให้ซ่อนปุ่ม
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 60,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 4. ปุ่มปิด (ออกจากการเต็มจอ)
            Positioned(
              top: 10,
              left: 10,
              child: IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 30,
                ),
                onPressed: () => Navigator.of(context).pop(), // กดแล้วปิด
              ),
            ),
          ],
        ),
      ),
    );
  }
}
