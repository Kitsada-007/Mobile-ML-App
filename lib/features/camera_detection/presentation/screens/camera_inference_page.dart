// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'dart:async'; // ใช้ unawaited

import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/controllers/camera_inference_controller.dart'; // Controller หลัก
import 'package:trffic_ilght_app/features/camera_detection/presentation/widgets/camera_detection_panel.dart'; // แผงผลลัพธ์การตรวจจับ
import 'package:trffic_ilght_app/features/camera_detection/presentation/widgets/camera_inference_content.dart'; // เนื้อหาหลัก (กล้อง/โหลด)
import 'package:trffic_ilght_app/features/camera_detection/presentation/widgets/camera_inference_overlay.dart'; // หัวหน้า (header)
import 'package:trffic_ilght_app/features/camera_detection/presentation/widgets/detection_stats_display.dart'; // แสดงสถิติ (DETECTIONS/FPS)

/// หน้าเซนต์สำหรับการตรวจจับ YOLO จากกล้องแบบเรียลไทม์
/// มีผลลัพธ์แสดงใต้ preview กล้อง
class CameraInferencePage extends StatefulWidget {
  const CameraInferencePage({
    super.key,
    this.onMenuPressed, // callback กดเมนู (มีค่าถ้าเปิดจาก Drawer)
    this.initializeOnStart =
        true, // เริ่มโหลดโมเดลทันทีเมื่อเปิดหน้า (ปิดได้ตอนเทสต์)
  });

  final VoidCallback? onMenuPressed;
  final bool initializeOnStart;

  @override
  State<CameraInferencePage> createState() => _CameraInferencePageState();
}

class _CameraInferencePageState extends State<CameraInferencePage> {
  late final CameraInferenceController _controller; // controller หลัก
  int _rebuildKey = 0; // ตัว key ที่เพิ่มขึ้นเพื่อบังคับ rebuild YOLOView

  @override
  void initState() {
    super.initState();
    _controller = CameraInferenceController();
    // เริ่มต้นระบบทั้งหมด (โหลดโมเดล ฯลฯ) — จับ error แสดง dialog แทน
    if (widget.initializeOnStart) {
      _controller.initialize().catchError((error) {
        if (mounted) {
          _showError('Model Loading Error', error.toString());
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ถ้าหน้านี้เป็นหน้าปัจจุบันของ route -> rebuild YOLOView (ผ่านการเพิ่ม rebuildKey)
    final route = ModalRoute.of(context);
    if (route?.isCurrent == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _rebuildKey++);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose(); // ปล่อย controller (โมเดล/กล้อง/เสียง)
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // เช็คแนวนอน/แนวตั้งเพื่อปรับ layout
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        // ListenableBuilder: rebuild เฉพาะส่วนเมื่อ controller มีการเปลี่ยนแปลง
        child: ListenableBuilder(
          listenable: _controller,
          // ส่วนลูกรียูส (ไม่ rebuild) — แค่กล้อง YOLOView
          child: CameraInferenceContent(
            key: ValueKey('camera_content_$_rebuildKey'),
            controller: _controller,
            rebuildKey: _rebuildKey,
          ),
          builder: (context, cameraContent) {
            return SingleChildScrollView(
              key: const Key('cameraDetectionScrollView'),
              padding: EdgeInsets.fromLTRB(
                isLandscape ? 24 : 16,
                8,
                isLandscape ? 24 : 16,
                24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ---------- Header: เมนู/ย้อนกลับ + ชื่อแอป + ไอคอนแจ้งเตือน ----------
                      CameraInferenceOverlay(
                        showMenuButton: widget.onMenuPressed != null,
                        onLeadingPressed:
                            widget.onMenuPressed ??
                            () => Navigator.maybePop(context),
                      ),
                      const SizedBox(height: 16),
                      // ---------- การ์ดแสดงกล้อง (preview) ----------
                      DecoratedBox(
                        key: const Key('cameraPreviewCard'),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: AspectRatio(
                            aspectRatio: isLandscape ? 16 / 9 : 4 / 3,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                cameraContent!, // ตัวกล้อง YOLOView / หน้าโหลด
                                // ป้ายสถานะสดที่มุมบนซ้าย
                                Positioned(
                                  top: 14,
                                  left: 14,
                                  child: _LiveStatusBadge(
                                    hasDetections:
                                        _controller.detectionCount > 0,
                                  ),
                                ),
                                // ปุ่มเปิด/ปิดกล้อง (มุมบนขวา) พร้อม Semantics
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  child: Semantics(
                                    button: true,
                                    label: _controller.isCameraEnabled
                                        ? 'ปิดกล้อง'
                                        : 'เปิดกล้อง',
                                    child: IconButton.filled(
                                      key: const Key('cameraPowerButton'),
                                      tooltip: _controller.isCameraEnabled
                                          ? 'ปิดกล้อง'
                                          : 'เปิดกล้อง',
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.black54,
                                        foregroundColor: Colors.white,
                                      ),
                                      icon: Icon(
                                        _controller.isCameraEnabled
                                            ? Icons.videocam_rounded
                                            : Icons.videocam_off_rounded,
                                      ),
                                      onPressed: () =>
                                          unawaited(_controller.toggleCamera()),
                                    ),
                                  ),
                                ),
                                // สถิติการตรวจจับด้านล่าง (DETECTIONS / FPS)
                                Positioned(
                                  left: 14,
                                  right: 14,
                                  bottom: 14,
                                  child: DetectionStatsDisplay(
                                    detectionCount: _controller.detectionCount,
                                    currentFps: _controller.currentFps,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // ---------- แผงผลลัพธ์การตรวจจับ (ด้านล่าง) ----------
                      CameraDetectionPanel(
                        formalNames: _controller.detectedFormalNames,
                        alertMessages: _controller.detectedAlertMessages,
                        detectedNumber: _controller.detectedNumber,
                        isLandscape: isLandscape,
                        isPipelineStale: _controller.isRealtimePipelineStale,
                        statusText: _controller.detectionStatus,
                        lastDetectionConfidence:
                            _controller.lastDetectionConfidence,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// แสดง error เป็น AlertDialog
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
}

/// ป้ายสถานะสดของกล้อง (จุดเขียว + ข้อความ) ใช้ Semantics live region เพื่อ screen reader
class _LiveStatusBadge extends StatelessWidget {
  const _LiveStatusBadge({required this.hasDetections});

  final bool hasDetections; // มีการตรวจจับในเฟรมล่าสุดหรือไม่

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true, // ประกาศให้ screen reader อ่านแบบสด
      label: hasDetections ? 'ตรวจจับสัญญาณแล้ว' : 'กำลังตรวจจับ',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62), // พื้นดำโปร่งแสง
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // จุดสีเขียวแสดงสถานะพร้อม
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                  color: Color(0xFF34C759),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                hasDetections ? 'ตรวจจับแล้ว' : 'กำลังตรวจจับ',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
