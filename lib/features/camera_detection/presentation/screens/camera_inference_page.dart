// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trffic_ilght_app/features/settings/settings.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/controllers/camera_inference_controller.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/widgets/camera_detection_panel.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/widgets/camera_inference_content.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/widgets/camera_inference_overlay.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/widgets/detection_stats_display.dart';
import 'package:trffic_ilght_app/features/settings/settings.dart';
import 'package:trffic_ilght_app/shared/utils/optional_provider.dart';

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
  late final CameraInferenceController _controller;
  SettingsProvider? _settings; // null เมื่อหน้านี้ถูก pump เดี่ยว ๆ ในเทสต์
  int _rebuildKey = 0; // ตัว key ที่เพิ่มขึ้นเพื่อบังคับ rebuild YOLOView
  bool? _isRouteCurrent;
  bool _isAppResumed = true;

  /// ระยะขอบบน/ล่างของทั้งหน้า (ใช้คำนวณความสูงที่เหลือด้วย)
  static const double _screenPadding = 12.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = CameraInferenceController(
      voiceService: readOptionalProvider<TrafficVoiceService>(context),
      onRequestStreamRestart: _restartCameraStream,
    );
    _bindSettings();
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
    // ยังหา route ไม่เจอ (เช่นถูกวางนอก Navigator) ให้ถือว่าอยู่บนสุดไว้ก่อน
    final route = ModalRoute.of(context);
    bool isCurrent;
    if (route == null) {
      isCurrent = true;
    } else {
      isCurrent = route.isCurrent;
    }
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
    // ยังไม่เคยรู้สถานะ route (null) ให้ถือว่าอยู่บนสุด เหมือนพฤติกรรมเดิม
    final routeCurrent = _isRouteCurrent;
    bool isRouteCurrent;
    if (routeCurrent == null) {
      isRouteCurrent = true;
    } else {
      isRouteCurrent = routeCurrent;
    }

    if (isRouteCurrent && _isAppResumed) {
      unawaited(_controller.resumeCamera());
    } else {
      unawaited(_controller.pauseCamera());
    }
  }

  /// สร้าง YOLOView ใหม่เมื่อ controller แจ้งว่าสตรีมเงียบไปนานเกินไป
  ///
  /// ใช้กลไก _rebuildKey เดิมที่หน้านี้ใช้ตอนกลับเข้ามาอยู่บนสุดอยู่แล้ว
  /// (controller เว้นระยะและจำกัดจำนวนครั้งให้แล้ว จึงไม่วนสร้างใหม่รัว ๆ)
  void _restartCameraStream() {
    if (!mounted) return;
    setState(() {
      _rebuildKey++;
    });
  }

  /// ผูกหน้ากล้องเข้ากับ SettingsProvider เพื่อให้ค่า threshold ที่ผู้ใช้เปลี่ยนในหน้า
  /// Settings มีผลทันที (หน้า Settings ถูก push ทับหน้านี้ หน้านี้จึงไม่ได้ถูกสร้างใหม่)
  void _bindSettings() {
    final settings = readOptionalProvider<SettingsProvider>(context);
    _settings = settings;
    if (settings == null) {
      return;
    }
    _applyDetectionSettings();
    settings.addListener(_applyDetectionSettings);
  }

  void _applyDetectionSettings() {
    final settings = _settings;
    if (settings == null) {
      return;
    }
    _controller.applyDetectionSettings(
      confidenceThreshold: settings.confidenceThreshold,
      iouThreshold: settings.iouThreshold,
      numItemsThreshold: settings.numItemsThreshold,
      showDetectionOverlay: settings.showDetectionOverlay,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _settings?.removeListener(_applyDetectionSettings);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ดึงค่า Threshold จาก SettingsProvider แบบเรียลไทม์ และอัปเดตให้ Controller
    final settings = context.watch<SettingsProvider>();
    _controller.updateThresholds(
      confidenceThreshold: settings.confidenceThreshold,
      iouThreshold: settings.iouThreshold,
      numItemsThreshold: settings.numItemsThreshold,
    );

    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          // ส่วนลูกรียูส (ไม่ rebuild) — แค่กล้อง YOLOView
          child: CameraInferenceContent(
            key: ValueKey('camera_content_$_rebuildKey'),
            controller: _controller,
            rebuildKey: _rebuildKey,
          ),
          builder: (context, cameraContent) {
            // รู้ความสูงจริงของพื้นที่ที่เหลือ
            // จึงกระจายเนื้อหาให้เต็มจอได้ แทนการปล่อยช่องว่างค้างไว้ด้านล่าง
            return LayoutBuilder(
              builder: (context, constraints) {
                double horizontalPadding;
                if (isLandscape) {
                  horizontalPadding = 24.0;
                } else {
                  horizontalPadding = 16.0;
                }

                double availableHeight;
                if (constraints.maxHeight.isFinite) {
                  availableHeight = (constraints.maxHeight - _screenPadding * 2)
                      .clamp(0.0, double.infinity);
                } else {
                  availableHeight = 0.0;
                }

                // ไม่มี callback เมนู (ไม่ได้เปิดจาก Drawer) ปุ่มนำจึงทำหน้าที่ย้อนกลับแทน
                final menuCallback = widget.onMenuPressed;
                VoidCallback onLeadingPressed;
                if (menuCallback == null) {
                  onLeadingPressed = () => Navigator.maybePop(context);
                } else {
                  onLeadingPressed = menuCallback;
                }

                final header = CameraInferenceOverlay(
                  showMenuButton: menuCallback != null,
                  onLeadingPressed: onLeadingPressed,
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
                  trafficLightClassName:
                      _controller.stableTrafficLightClassName,
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
                double previewHeightRatio;
                if (availableHeight >= 720) {
                  previewHeightRatio = 0.55;
                } else {
                  previewHeightRatio = 0.45;
                }
                final previewHeight = (availableHeight * previewHeightRatio)
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
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          header,
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
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
    // ป้ายกำกับกับไอคอนของปุ่มกล้องผูกกับสถานะเดียวกัน จึงกำหนดพร้อมกันทีเดียว
    String cameraToggleLabel;
    IconData cameraToggleIcon;
    if (_controller.isCameraEnabled) {
      cameraToggleLabel = 'ปิดกล้อง';
      cameraToggleIcon = Icons.videocam_rounded;
    } else {
      cameraToggleLabel = 'เปิดกล้อง';
      cameraToggleIcon = Icons.videocam_off_rounded;
    }

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
            cameraContent,
            Positioned(
              top: 14,
              left: 14,
              child: _LiveStatusBadge(
                hasDetections: _controller.detectionCount > 0,
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    button: true,
                    label: cameraToggleLabel,
                    child: IconButton.filled(
                      key: const Key('cameraPowerButton'),
                      tooltip: cameraToggleLabel,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                      ),
                      icon: Icon(cameraToggleIcon),
                      onPressed: () => unawaited(_controller.toggleCamera()),
                    ),
                  ),
                  if (_controller.isCameraEnabled) ...[
                    const SizedBox(height: 12),
                    _ZoomControls(
                      currentZoom: _controller.currentZoomLevel,
                      onZoomChanged: _controller.setZoomLevel,
                    ),
                  ],
                ],
              ),
            ),
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

  final bool hasDetections;

  @override
  Widget build(BuildContext context) {
    // ข้อความสำหรับ screen reader ยาวกว่าข้อความบนป้าย จึงแยกเป็นคนละตัวแปร
    String semanticsLabel;
    String badgeText;
    if (hasDetections) {
      semanticsLabel = 'ตรวจจับสัญญาณแล้ว';
      badgeText = 'ตรวจจับแล้ว';
    } else {
      semanticsLabel = 'กำลังตรวจจับ';
      badgeText = 'กำลังตรวจจับ';
    }

    return Semantics(
      liveRegion: true,
      label: semanticsLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                badgeText,
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

/// ชุดปุ่มควบคุมระดับ Zoom ของกล้อง (สามารถกดซ่อน/ขยายได้)
class _ZoomControls extends StatefulWidget {
  const _ZoomControls({required this.currentZoom, required this.onZoomChanged});

  final double currentZoom;
  final ValueChanged<double> onZoomChanged;

  @override
  State<_ZoomControls> createState() => _ZoomControlsState();
}

class _ZoomControlsState extends State<_ZoomControls> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final zoomLevels = [1.0, 1.5, 2.0];

    // สถานะพับเก็บ: แสดงเฉพาะระดับซูมปัจจุบัน
    if (!_isExpanded) {
      return GestureDetector(
        onTap: () => setState(() => _isExpanded = true),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.black54,
            shape: BoxShape.circle,
          ),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Text(
                '${widget.currentZoom == 1.0 || widget.currentZoom == 2.0 ? widget.currentZoom.toInt() : widget.currentZoom}x',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // สถานะกางออก: แสดงปุ่มเลือกระดับซูม และปุ่มปิด
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...zoomLevels.map((zoom) {
              final isSelected = (widget.currentZoom - zoom).abs() < 0.1;
              return GestureDetector(
                onTap: () {
                  widget.onZoomChanged(zoom);
                  setState(() => _isExpanded = false); // เลือกแล้วพับเก็บเลย
                },
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                  ),
                  child: Text(
                    '${zoom == 1.0 || zoom == 2.0 ? zoom.toInt() : zoom}x',
                    style: TextStyle(
                      color: isSelected
                          ? Theme.of(context).colorScheme.onPrimary
                          : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }),
            // ปุ่มลูกศรสำหรับกดพับเก็บโดยไม่เปลี่ยนค่า
            GestureDetector(
              onTap: () => setState(() => _isExpanded = false),
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                margin: const EdgeInsets.only(top: 2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.transparent,
                ),
                child: const Icon(
                  Icons.keyboard_arrow_up_rounded,
                  color: Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
