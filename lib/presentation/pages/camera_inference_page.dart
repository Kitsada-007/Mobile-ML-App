// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/presentation/controllers/camera_inference_controller.dart';

import 'package:trffic_ilght_app/presentation/widgets/camera_widgets/camera_inference_content.dart';
import 'package:trffic_ilght_app/presentation/widgets/camera_widgets/camera_inference_overlay.dart';
import 'package:trffic_ilght_app/presentation/widgets/camera_widgets/camera_controls.dart';
import 'package:trffic_ilght_app/presentation/widgets/camera_widgets/threshold_slider.dart';

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

              CameraControls(
                currentZoomLevel: _controller.currentZoomLevel,
                isFrontCamera: _controller.isFrontCamera,
                activeSlider: _controller.activeSlider,
                onZoomChanged: _controller.setZoomLevel,
                onSliderToggled: _controller.toggleSlider,
                onCameraFlipped: _controller.flipCamera,
                isLandscape: isLandscape,
              ),
              ThresholdSlider(
                activeSlider: _controller.activeSlider,
                confidenceThreshold: _controller.confidenceThreshold,
                iouThreshold: _controller.iouThreshold,
                numItemsThreshold: _controller.numItemsThreshold,
                onValueChanged: _controller.updateSliderValue,
                isLandscape: isLandscape,
              ),

              // ==========================================
              // ส่วน UI ใหม่: มินิมอล เรียบง่าย โชว์ด้านบน
              // ==========================================
              Positioned(
                top: 100, // ขยับลงมาจากแถบด้านบน (AppBar) นิดหน่อย
                left: 20,
                right: 0,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final formalNames = _controller.detectedFormalNames;
                    final alertMessages = _controller.detectedAlertMessages;

                    // ถ้าไม่เจออะไรเลย ให้หน้าจอโล่งๆ ไปเลย (ซ่อนข้อความ)
                    if (formalNames.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    // ถ้าเจอวัตถุ แสดงเป็นข้อความเรียบๆ ตรงกลาง
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(formalNames.length, (index) {
                        final className = formalNames[index];
                        String displayAlert = alertMessages[index];

                        // จัดการแสดงผลตัวเลข
                        if (className == "ป้ายตัวเลข" &&
                            _controller.detectedNumber != null) {
                          displayAlert =
                              "ความเร็ว ${_controller.detectedNumber}";
                        }

                        // ถ้าไม่มีคำแจ้งเตือน ให้ใช้ชื่อทางการแทน
                        final textToShow = displayAlert.isNotEmpty
                            ? displayAlert
                            : className;

                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            key: ValueKey(
                              textToShow,
                            ), // ช่วยให้แอนิเมชันเวลาเปลี่ยนคำดูนุ่มนวล
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(
                                0.6,
                              ), // พื้นหลังดำโปร่งแสงนิดๆ ให้อ่านตัวหนังสือออก
                              borderRadius: BorderRadius.circular(
                                30,
                              ), // ทรงแคปซูลโค้งมน เรียบหรู
                            ),
                            child: Text(
                              textToShow,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _getAlertColor(
                                  className,
                                ), // ดึงสีมาใช้เหมือนเดิม (แดง, เหลือง, เขียว)
                                fontSize: 24, // ตัวอักษรใหญ่ชัดเจน
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        );
                      }),
                    );
                  },
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
