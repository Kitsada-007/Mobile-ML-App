// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/shared/models/model_types.dart'; // ประเภท SliderType

/// วิดเจ็ตสำหรับกลุ่มปุ่มควบคุมกล้อง (zoom / สลับกล้อง / ปรับ threshold)
/// หมายเหตุ: ปุ่มส่วนใหญ่ถูกคอมเมนต์ทิ้งไว้ (ดีดออกชั่วคราว) — ใช้ไว้สำหรับ
/// ปรับแต่งภายหลัง ปัจจุบัน layout มีแค่ตำแหน่งปุ่มกล้องล่างขวาเท่านั้น
class CameraControls extends StatelessWidget {
  const CameraControls({
    super.key,
    required this.currentZoomLevel,
    required this.isFrontCamera,
    required this.activeSlider,
    required this.onZoomChanged,
    required this.onSliderToggled,
    required this.onCameraFlipped,
    required this.isLandscape,
  });

  final double currentZoomLevel; // ระดับ zoom ปัจจุบัน
  final bool isFrontCamera; // เปิดอยู่ที่กล้องหน้าหรือไม่
  final SliderType activeSlider; // slider ที่แสดงอยู่
  final ValueChanged<double> onZoomChanged; // callback เปลี่ยน zoom
  final ValueChanged<SliderType> onSliderToggled; // callback สลับ slider
  final VoidCallback onCameraFlipped; // callback สลับกล้องหน้า/หลัง
  final bool isLandscape; // ปรับตำแหน่งตามแนว/ขวางจอ

  @override
  Widget build(BuildContext context) {
    // ใช้ padding.bottom แทน top เพื่อให้ปุ่มสลับกล้องไม่ทับซ้อนกับขอบจอด้านล่าง
    final double safeBottomPadding = MediaQuery.of(context).padding.bottom;

    return Stack(
      children: [
        Positioned(
          bottom: safeBottomPadding + (isLandscape ? 16 : 32),
          right: isLandscape ? 8 : 16,
          child: Column(
            children: [
              // ปุ่ม Zoom (ปิดไว้ชั่วคราว)
              // if (!isFrontCamera)
              //   ControlButton(
              //     content: '${currentZoomLevel.toStringAsFixed(1)}x',
              //     onPressed: () => onZoomChanged(
              //       currentZoomLevel < 0.75
              //           ? 1.0
              //           : currentZoomLevel < 2.0
              //           ? 3.0
              //           : 0.5,
              //     ),
              //   ),
              // SizedBox(height: isLandscape ? 8 : 12),

              // ปุ่ม Layers (numItems) (ปิดไว้ชั่วคราว)
              // ControlButton(
              //   content: Icons.layers,
              //   onPressed: () {
              //     if (activeSlider == SliderType.numItems) {
              //       onSliderToggled(SliderType.none);
              //     } else {
              //       onSliderToggled(SliderType.numItems);
              //     }
              //   },
              // ),
              // SizedBox(height: isLandscape ? 8 : 12),

              // ปุ่ม Adjust (confidence) (ปิดไว้ชั่วคราว)
              // ControlButton(
              //   content: Icons.adjust,
              //   onPressed: () {
              //     if (activeSlider == SliderType.confidence) {
              //       onSliderToggled(SliderType.none);
              //     } else {
              //       onSliderToggled(SliderType.confidence);
              //     }
              //   },
              // ),
              // SizedBox(height: isLandscape ? 8 : 12),

              // // ปุ่ม IOU (ปิดไว้ชั่วคราว)
              // ControlButton(
              //   content: 'assets/iou.png',
              //   onPressed: () {
              //     if (activeSlider == SliderType.iou) {
              //       onSliderToggled(SliderType.none);
              //     } else {
              //       onSliderToggled(SliderType.iou);
              //     }
              //   },
              // ),
              // SizedBox(height: isLandscape ? 16 : 40),
            ],
          ),
        ),

        // ปุ่มสลับกล้องหน้า/หลัง (ปิดไว้ชั่วคราว)
        // Positioned(
        //   bottom: safeBottomPadding + (isLandscape ? 32 : 16),
        //   left: isLandscape ? 32 : 16,
        //   child: CircleAvatar(
        //     radius: isLandscape ? 20 : 24,
        //     backgroundColor: Colors.black.withValues(alpha: 0.5),
        //     child: IconButton(
        //       icon: const Icon(Icons.flip_camera_ios, color: Colors.white),
        //       onPressed: onCameraFlipped,
        //     ),
        //   ),
        // ),
      ],
    );
  }
}
