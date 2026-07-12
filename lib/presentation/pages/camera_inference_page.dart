// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:trffic_ilght_app/presentation/controllers/camera_inference_controller.dart';

import 'package:trffic_ilght_app/presentation/widgets/camera_widgets/camera_inference_content.dart';
import 'package:trffic_ilght_app/presentation/widgets/camera_widgets/camera_inference_overlay.dart';

/// A screen that demonstrates real-time YOLO inference using the device camera.
///
/// This screen provides:
/// - Live camera feed with YOLO object detection
/// - Model selection (detect, segment, classify, pose, obb)
/// - Adjustable thresholds (confidence, IoU, max detections)
/// - Camera controls (flip, zoom)
/// - Performance metrics (FPS)
class CameraInferencePage extends StatefulWidget {
  const CameraInferencePage({super.key});

  @override
  State<CameraInferencePage> createState() => _CameraInferencePageState();
}

class _CameraInferencePageState extends State<CameraInferencePage> {
  late final CameraInferenceController _controller;
  int _rebuildKey = 0;

  @override
  void initState() {
    super.initState();
    _controller = CameraInferenceController();
    _controller.initialize().catchError((error) {
      if (mounted) {
        _showError('Model Loading Error', error.toString());
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check if route is current (we've navigated back to this screen)
    final route = ModalRoute.of(context);
    if (route?.isCurrent == true) {
      // Force rebuild when navigating back to ensure camera restarts
      // The rebuild will create a new YOLOView which will automatically start the camera
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _rebuildKey++;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent, // ให้สีกลืนไปกับพื้นหลัง
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Camera',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
      ),

      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, child) {
          return Stack(
            children: [
              CameraInferenceContent(
                key: ValueKey('camera_content_$_rebuildKey'),
                controller: _controller,
                rebuildKey: _rebuildKey,
              ),
              CameraInferenceOverlay(
                controller: _controller,
                isLandscape: isLandscape,
              ),

              // ==========================================
              // UI หน้ากล้องแบบ Green & Clean (Glassmorphism + Emerald Green Accent)
              // ==========================================
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.3), // Emerald Green
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ส่วนหัว: หัวข้อและสถานะ
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.sensors_rounded,
                                    color: Color(0xFF10B981),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'AI TRAFFIC SCANNER',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF10B981),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'ACTIVE',
                                    style: TextStyle(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.85),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Divider(
                            color: Colors.white24,
                            height: 20,
                            thickness: 1,
                          ),
                          
                          // แสดงข้อมูลการตรวจจับ
                          AnimatedBuilder(
                            animation: _controller,
                            builder: (context, _) {
                              final formalNames = _controller.detectedFormalNames;
                              final alertMessages = _controller.detectedAlertMessages;
                              final detectedNum = _controller.detectedNumber;

                              if (formalNames.isEmpty) {
                                return Row(
                                  children: [
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'กำลังสแกนหาป้ายจราจรและสัญญาณไฟ...',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.6),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ],
                                );
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(formalNames.length, (index) {
                                  final className = formalNames[index];
                                  String displayAlert = alertMessages[index];

                                  bool isSpeedLimit = false;
                                  if (className == "ป้ายตัวเลข" && detectedNum != null) {
                                    isSpeedLimit = true;
                                    final int? val = int.tryParse(detectedNum);
                                    if (val != null && val >= 1 && val <= 3) {
                                      displayAlert = "เตรียมตัวไป";
                                    } else {
                                      displayAlert = "ป้ายจำกัดความเร็ว $detectedNum กม./ชม.";
                                    }
                                  }

                                  final textToShow = displayAlert.isNotEmpty ? displayAlert : className;
                                  final alertColor = _getAlertColor(className);

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                                    child: Row(
                                      children: [
                                        // แถบสีแสดงสถานะการเตือน
                                        Container(
                                          width: 5,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: alertColor,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            textToShow,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              decoration: TextDecoration.none,
                                            ),
                                          ),
                                        ),
                                        // วงกลมสัญลักษณ์ป้ายจำกัดความเร็ว (แสดงเมื่อพบตัวเลข)
                                        if (isSpeedLimit && detectedNum != null && int.tryParse(detectedNum) != null && int.parse(detectedNum) > 3)
                                          Container(
                                            width: 34,
                                            height: 34,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Colors.white,
                                              border: Border.all(
                                                color: Colors.red,
                                                width: 3,
                                              ),
                                            ),
                                            child: Center(
                                              child: Text(
                                                detectedNum,
                                                style: const TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w900,
                                                  decoration: TextDecoration.none,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                }),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showError(String title, String message) => showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  // ฟังก์ชันช่วยกำหนดสีของกล่องแจ้งเตือน
  Color _getAlertColor(String className) {
    if (className.contains('แดง') || className.contains('ห้าม')) {
      return Colors.redAccent; // สีแดงสำหรับไฟแดงหรือป้ายห้าม
    } else if (className.contains('เหลือง') || className.contains('กะพริบ')) {
      return Colors.orangeAccent; // สีส้ม/เหลือง สำหรับเตือน
    } else if (className.contains('เขียว') ||
        className.contains('เลี้ยว') ||
        className.contains('ตรง')) {
      return Colors.greenAccent; // สีเขียวสำหรับไปได้
    } else if (className == "กำลังสแกน...") {
      return Colors.white54; // สีเทา
    }
    return Colors.blueAccent; // สีฟ้าสำหรับป้ายตัวเลขทั่วไป
  }
}
