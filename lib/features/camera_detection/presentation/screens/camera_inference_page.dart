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

class _CameraInferencePageState extends State<CameraInferencePage>
    with WidgetsBindingObserver {
  late final CameraInferenceController _controller; // controller หลัก
  int _rebuildKey = 0; // ตัว key ที่เพิ่มขึ้นเพื่อบังคับ rebuild YOLOView
  bool? _isRouteCurrent;
  bool _isAppResumed = true;

  /// ระยะขอบบน/ล่างของทั้งหน้า (ใช้คำนวณความสูงที่เหลือด้วย)
  static const double _screenPadding = 12;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (_isRouteCurrent == isCurrent) return;

    _isRouteCurrent = isCurrent;
    _syncCameraLifecycle();
    if (isCurrent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _rebuildKey++);
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppResumed = state == AppLifecycleState.resumed;
    _syncCameraLifecycle();
  }

  /// กล้องทำงานเฉพาะตอนแอปอยู่ foreground และ route นี้อยู่ด้านบนสุด
  void _syncCameraLifecycle() {
    if ((_isRouteCurrent ?? true) && _isAppResumed) {
      unawaited(_controller.resumeCamera());
    } else {
      unawaited(_controller.pauseCamera());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
            // LayoutBuilder: รู้ความสูงจริงของพื้นที่ที่เหลือ
            // จึงกระจายเนื้อหาให้เต็มจอได้ แทนการปล่อยช่องว่างค้างไว้ด้านล่าง
            return LayoutBuilder(
              builder: (context, constraints) {
                final horizontalPadding = isLandscape ? 24.0 : 16.0;
                final availableHeight = constraints.maxHeight.isFinite
                    ? (constraints.maxHeight - _screenPadding * 2).clamp(
                        0.0,
                        double.infinity,
                      )
                    : 0.0;

                final header = CameraInferenceOverlay(
                  showMenuButton: widget.onMenuPressed != null,
                  onLeadingPressed:
                      widget.onMenuPressed ?? () => Navigator.maybePop(context),
                );
                final panel = CameraDetectionPanel(
                  formalNames: _controller.detectedFormalNames,
                  alertMessages: _controller.detectedAlertMessages,
                  detectedNumber: _controller.detectedNumber,
                  isLandscape: isLandscape,
                  driverSignalResult: _controller.driverSignalResult,
                  isPipelineStale: _controller.isRealtimePipelineStale,
                  statusText: _controller.detectionStatus,
                  lastDetectionConfidence: _controller.lastDetectionConfidence,
                );

                // แนวนอน: จอเตี้ยแต่กว้าง จึงวางกล้องคู่กับแผงผล ไม่ใช่วางต่อกันลงมา
                if (isLandscape) {
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      _screenPadding,
                      horizontalPadding,
                      _screenPadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        header,
                        const SizedBox(height: 12),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 3,
                                child: _buildPreviewCard(cameraContent!),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 2,
                                // แผงผลสูงเกินจอได้เมื่อพบหลายคลาส จึงต้องเลื่อนได้เอง
                                child: SingleChildScrollView(
                                  key: const Key('cameraDetectionScrollView'),
                                  child: panel,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // แนวตั้ง: กล้องกินพื้นที่ราวครึ่งจอ ส่วนที่เหลือถูกเกลี่ยด้วย spaceBetween
                // เพดาน 55% กันไม่ให้แผงผลด้านล่างถูกเบียดจนต้องเลื่อนหาโดยไม่จำเป็น
                // จอเตี้ยต้องแบ่งให้กล้องน้อยลง ไม่งั้นแผงผลถูกดันตกขอบจนต้องเลื่อนหา
                final previewHeight =
                    (availableHeight * (availableHeight >= 720 ? 0.55 : 0.45))
                        .clamp(180.0, 560.0);

                return SingleChildScrollView(
                  key: const Key('cameraDetectionScrollView'),
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    _screenPadding,
                    horizontalPadding,
                    _screenPadding,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      // minHeight ดันเนื้อหาให้สูงเท่าจอเสมอ ส่วนที่เกินยังเลื่อนได้ตามเดิม
                      constraints: BoxConstraints(
                        maxWidth: 720,
                        minHeight: availableHeight,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          header,
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: SizedBox(
                              height: previewHeight,
                              child: _buildPreviewCard(cameraContent!),
                            ),
                          ),
                          panel,
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// การ์ด preview กล้อง: ตัวภาพ + ป้ายสถานะ + ปุ่มเปิดปิดกล้อง + สถิติ
  /// ความสูงถูกกำหนดจากภายนอก (ไม่ผูกกับ AspectRatio คงที่อีกต่อไป)
  Widget _buildPreviewCard(Widget cameraContent) {
    return DecoratedBox(
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            cameraContent, // ตัวกล้อง YOLOView / หน้าโหลด
            // ป้ายสถานะสดที่มุมบนซ้าย
            Positioned(
              top: 14,
              left: 14,
              child: _LiveStatusBadge(
                hasDetections: _controller.detectionCount > 0,
              ),
            ),
            // ปุ่มเปิด/ปิดกล้อง (มุมบนขวา) พร้อม Semantics
            Positioned(
              top: 10,
              right: 10,
              child: Semantics(
                button: true,
                label: _controller.isCameraEnabled ? 'ปิดกล้อง' : 'เปิดกล้อง',
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
                  onPressed: () => unawaited(_controller.toggleCamera()),
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
