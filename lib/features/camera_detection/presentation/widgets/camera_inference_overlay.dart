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
    String navigationTooltip;
    IconData navigationIcon;
    if (showMenuButton) {
      navigationTooltip = 'เปิดเมนู';
      navigationIcon = Icons.menu_rounded;
    } else {
      navigationTooltip = 'ย้อนกลับ';
      navigationIcon = Icons.arrow_back_rounded;
    }

    return Row(
      key: const Key('cameraPageHeader'),
      children: [
        _HeaderButton(
          key: const Key('cameraNavigationButton'),
          tooltip: navigationTooltip,
          icon: navigationIcon,
          onPressed: onLeadingPressed,
        ),
        const SizedBox(width: 8),
        const Expanded(child: _BrandBadge()),
        const SizedBox(width: 8),
        const SizedBox(width: 48, height: 48),
      ],
    );
  }
}

/// ป้ายแบรนด์ (โลโก้ + ชื่อแอป + คำอธิบายสั้น)
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/images/app.png', width: 28, height: 28),
              const SizedBox(width: 8),
              // จอแคบ (เช่น 320dp) ทำให้โลโก้+ชื่อรวมกันกว้างเกินช่องกลาง header
              // จึงต้องให้ชื่อยืดหยุ่นและตัดด้วย ellipsis แทนที่จะล้นออกนอกแถว
              Flexible(
                child: Text(
                  'Berng Fai',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Live Traffic Detection',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w500,
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
