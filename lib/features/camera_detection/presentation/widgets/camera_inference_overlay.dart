import 'package:flutter/material.dart';

/// ส่วนหัว (Header) ของหน้าตรวจจับไฟจราจรแบบเรียลไทม์
/// - ปุ่มนำทาง (เมนูหรือย้อนกลับ ตาม context)
/// - ชื่อแอป/แบรนด์ย่อ (กลาง)
/// - ไอคอนแจ้งเตือน (ทึบ วางตำแหน่งให้สมมาตร)
class CameraInferenceOverlay extends StatelessWidget {
  const CameraInferenceOverlay({
    super.key,
    required this.onLeadingPressed,
    this.showMenuButton = false,
  });

  final VoidCallback onLeadingPressed;

  /// true = แสดงปุ่มเมนู (อยู่ใน Drawer), false = ปุ่มย้อนกลับ
  final bool showMenuButton;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      key: const Key('cameraPageHeader'),
      children: [
        _HeaderButton(
          key: const Key('cameraNavigationButton'),
          tooltip: showMenuButton ? 'เปิดเมนู' : 'ย้อนกลับ',
          icon: showMenuButton ? Icons.menu_rounded : Icons.arrow_back_rounded,
          onPressed: onLeadingPressed,
        ),
        const SizedBox(width: 8),
        const Expanded(child: _BrandBadge()),
        const SizedBox(width: 8),
        // สำรองตำแหน่งขนาดเท่าปุ่มซ้าย เพื่อให้ป้ายแบรนด์อยู่กึ่งกลางจริง
        SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Icon(
              Icons.notifications_none_rounded,
              color: colorScheme.onSurface,
              semanticLabel: 'การแจ้งเตือน',
            ),
          ),
        ),
      ],
    );
  }
}

/// ป้ายแบรนด์ (ชื่อไทย + ภาษาอังกฤษ + ชื่อเล่น)
class _BrandBadge extends StatelessWidget {
  const _BrandBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Semantics(
      header: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'ระบบตรวจจับไฟจราจร',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Traffic Light Detection',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Text(
            'Berng Fai',
            style: TextStyle(
              color: Color(0xFF0B9A5A),
              fontSize: 9,
              height: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// ปุ่มนำทาง (IconButton) ขนาดมาตรฐานที่ใช้ใน header
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      color: Theme.of(context).colorScheme.onSurface,
      iconSize: 30,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
    );
  }
}
