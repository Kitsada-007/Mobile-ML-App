import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/core/services/inference/signal_interpreter.dart';

/// ชุดสีของป้ายนับถอยหลัง 1 สถานะ (กรอบ / พื้นหลัง / ตัวเลข / หน่วย)
/// แยกเป็นคลาสเพื่อให้เทสต์ตรวจ mapping ได้ตรง ๆ โดยไม่ต้องไล่หา widget ภายใน
@immutable
class CountdownBadgePalette {
  const CountdownBadgePalette({
    required this.background,
    required this.border,
    required this.number,
    required this.unit,
    this.pulse = false,
  });

  final Color background;
  final Color border;
  final Color number;
  final Color unit;

  /// ไฟกะพริบ (flashing_*) ให้กรอบเต้นเป็นจังหวะ เพื่อสื่อว่าไฟไม่นิ่ง
  final bool pulse;
}

/// ป้ายตัวเลขนับถอยหลังที่ใช้ร่วมกันระหว่างหน้ากล้องและหน้าวิดีโอ
/// สีทั้งชุดผูกกับ "คลาสไฟจราจรที่ยืนยันเสถียรแล้ว" จาก controller
/// ห้ามเดาสีจากข้อความภาษาไทย — ต้องรับชื่อคลาสโมเดล/คลาสสังเคราะห์ตรง ๆ
class CountdownBadge extends StatefulWidget {
  const CountdownBadge({
    super.key,
    required this.countdown,
    this.trafficLightClassName,
  });

  /// ตัวเลขนับถอยหลัง (null = ไม่พบตัวเลข แสดง "X")
  final int? countdown;

  /// คลาสไฟจราจรที่เสถียรแล้ว เช่น red_light_circle / flashing_yellow
  /// (null = ยังไม่ยืนยันไฟ ใช้ชุดสีกลาง)
  final String? trafficLightClassName;

  /// เลือกชุดสีตามคลาสไฟ — switch expression มี default ชัดเจน
  /// เพื่อให้เพิ่มคลาสใหม่ในอนาคตแล้วคอมไพเลอร์/ผู้อ่านเห็นจุดต่อได้ทันที
  static CountdownBadgePalette paletteFor(String? trafficLightClassName) {
    // เลขเป็นตัวอักษรใหญ่ (36px หนา) เกณฑ์ AA ของ large text คือ 3:1
    // ทุกคู่สีด้านล่างเลือกเฉดเข้มบนพื้นพาสเทลให้เกิน 4.5:1 เผื่อแสงจ้าในรถ
    const red = CountdownBadgePalette(
      background: Color(0xFFFFECEC),
      border: Color(0xFFF3B6B6),
      number: Color(0xFFB42323),
      unit: Color(0xFF8F3131),
    );
    const yellow = CountdownBadgePalette(
      background: Color(0xFFFFF6DF),
      border: Color(0xFFF1D48F),
      number: Color(0xFF935F00),
      unit: Color(0xFF7A5200),
    );
    return switch (trafficLightClassName) {
      TrafficSignalClasses.redLightCircle => red,
      TrafficSignalClasses.yellowLight => yellow,
      TrafficSignalClasses.flashingRed => CountdownBadgePalette(
        background: red.background,
        border: red.border,
        number: red.number,
        unit: red.unit,
        pulse: true,
      ),
      TrafficSignalClasses.flashingYellow => CountdownBadgePalette(
        background: yellow.background,
        border: yellow.border,
        number: yellow.number,
        unit: yellow.unit,
        pulse: true,
      ),
      TrafficSignalClasses.greenLightCircle => const CountdownBadgePalette(
        background: Color(0xFFE8F8EE),
        border: Color(0xFFABDFC0),
        number: Color(0xFF14713A),
        unit: Color(0xFF1F5C36),
      ),
      TrafficSignalClasses.offLight => const CountdownBadgePalette(
        background: Color(0xFFF0F2F4),
        border: Color(0xFFCDD3D9),
        number: Color(0xFF3F464D),
        unit: Color(0xFF5A6068),
      ),
      // ยังไม่ยืนยันไฟ / คลาสที่ไม่รู้จัก -> สีกลาง ไม่ชี้นำผู้ขับ
      _ => const CountdownBadgePalette(
        background: Color(0xFFF7F8FA),
        border: Color(0xFFE3E6EA),
        number: Color(0xFF51575E),
        unit: Color(0xFF6B7178),
      ),
    };
  }

  @override
  State<CountdownBadge> createState() => _CountdownBadgeState();
}

class _CountdownBadgeState extends State<CountdownBadge>
    with SingleTickerProviderStateMixin {
  // จังหวะกะพริบ ~1 Hz (ไป-กลับ 450ms) ใกล้จังหวะไฟกะพริบจริง
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// เปิด/ปิดการเต้นของกรอบตามชุดสีและค่า disableAnimations ของระบบ
  void _syncPulse(bool shouldPulse, bool animationsDisabled) {
    if (shouldPulse && !animationsDisabled) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else if (_pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = CountdownBadge.paletteFor(widget.trafficLightClassName);
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);
    _syncPulse(palette.pulse, animationsDisabled);

    // เปลี่ยนสีแบบ transition สั้น ๆ กันภาพกระตุกเมื่อสถานะไฟสลับ
    final transition = animationsDisabled
        ? Duration.zero
        : const Duration(milliseconds: 200);

    final countdown = widget.countdown;
    final lightLabel =
        TrafficSignalClasses.thaiLabel[widget.trafficLightClassName];
    // ต้องมีข้อความบอกสีไฟเสมอ (คนตาบอดสีต้องใช้ได้ ไม่พึ่งสีทางเดียว)
    final semanticsLabel = [
      ?lightLabel,
      countdown == null
          ? 'ไม่พบตัวเลขนับถอยหลัง'
          : 'ตัวเลขนับถอยหลัง $countdown วินาที',
    ].join(' ');

    return Semantics(
      // ตัด semantics ของ Text ลูกออก เพราะ label ครอบคลุมทั้งสีไฟและตัวเลขแล้ว
      // (กัน screen reader อ่านค่าซ้ำสองรอบ) — ไม่ตั้ง container เพื่อให้ยังรวม
      // อยู่ใต้ liveRegion ของแผงผลเหมือนโครงสร้างเดิม
      excludeSemantics: true,
      label: semanticsLabel,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          // ไฟกะพริบ: หรี่กรอบเข้าหาสีพื้นสลับกับสีเต็ม (เฉพาะกรอบ ไม่แตะตัวเลข)
          final borderColor = palette.pulse
              ? Color.lerp(
                  palette.border,
                  palette.background,
                  _pulseController.value,
                )!
              : palette.border;
          return AnimatedContainer(
            duration: transition,
            width: 86,
            height: 86,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: palette.background,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor),
            ),
            child: child,
          );
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: AnimatedDefaultTextStyle(
                duration: transition,
                style: TextStyle(
                  color: palette.number,
                  fontSize: 36,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.5,
                ),
                child: Text(countdown?.toString() ?? 'X', maxLines: 1),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: AnimatedDefaultTextStyle(
                duration: transition,
                style: TextStyle(
                  color: palette.unit,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
                child: Text(
                  countdown == null ? 'ไม่พบตัวเลข' : 'วินาที',
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
