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
  });

  final Color background;
  final Color border;
  final Color number;
  final Color unit;
}

/// ป้ายตัวเลขนับถอยหลังที่ใช้ร่วมกันระหว่างหน้ากล้องและหน้าวิดีโอ
/// สีทั้งชุดผูกกับ "คลาสไฟจราจรที่ยืนยันเสถียรแล้ว" จาก controller
/// ห้ามเดาสีจากข้อความภาษาไทย — ต้องรับชื่อคลาสโมเดลตรง ๆ
class CountdownBadge extends StatelessWidget {
  const CountdownBadge({
    super.key,
    required this.countdown,
    this.trafficLightClassName,
  });

  /// ตัวเลขนับถอยหลัง (null = ไม่พบตัวเลข แสดง "X")
  final int? countdown;

  /// คลาสไฟจราจรที่เสถียรแล้ว เช่น red_light_circle
  /// (null = ยังไม่ยืนยันไฟ ใช้ชุดสีกลาง)
  final String? trafficLightClassName;

  /// เลือกชุดสีตามคลาสไฟ — switch expression มี default ชัดเจน
  /// เพื่อให้เพิ่มคลาสใหม่ในอนาคตแล้วคอมไพเลอร์/ผู้อ่านเห็นจุดต่อได้ทันที
  static CountdownBadgePalette paletteFor(String? trafficLightClassName) {
    // เลขเป็นตัวอักษรใหญ่ (36px หนา) เกณฑ์ AA ของ large text คือ 3:1
    // ทุกคู่สีด้านล่างเลือกเฉดเข้มบนพื้นพาสเทลให้เกิน 4.5:1 เผื่อแสงจ้าในรถ
    return switch (trafficLightClassName) {
      TrafficSignalClasses.redLightCircle ||
      TrafficSignalClasses.redLight => const CountdownBadgePalette(
        background: Color(0xFFFFECEC),
        border: Color(0xFFF3B6B6),
        number: Color(0xFFB42323),
        unit: Color(0xFF8F3131),
      ),
      TrafficSignalClasses.yellowLight ||
      TrafficSignalClasses.yellowLightCircle => const CountdownBadgePalette(
        background: Color(0xFFFFF6DF),
        border: Color(0xFFF1D48F),
        number: Color(0xFF935F00),
        unit: Color(0xFF7A5200),
      ),
      // แก้ไข: เพิ่มกลุ่มไฟลูกศรสีเขียว (ไปตรง, เลี้ยวซ้าย, เลี้ยวขวา) เข้ามาใช้ Palette สีเขียวด้วย
      TrafficSignalClasses.greenLightCircle ||
      TrafficSignalClasses.greenLight ||
      TrafficSignalClasses.goStraightArrow ||
      TrafficSignalClasses.turnLeft ||
      TrafficSignalClasses.turnRight => const CountdownBadgePalette(
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
  Widget build(BuildContext context) {
    final palette = paletteFor(trafficLightClassName);
    final animationsDisabled = MediaQuery.disableAnimationsOf(context);

    // เปลี่ยนสีแบบ transition สั้น ๆ กันภาพกระตุกเมื่อสถานะไฟสลับ
    Duration transition;
    if (animationsDisabled) {
      transition = Duration.zero;
    } else {
      transition = const Duration(milliseconds: 200);
    }

    // เก็บลงตัวแปรก่อน เพื่อให้ทั้งข้อความบนป้ายและ semantics ใช้ค่าเดียวกัน
    final countdownValue = countdown;
    String numberText;
    String unitText;
    String countdownSemanticsText;
    if (countdownValue == null) {
      numberText = 'X';
      unitText = 'ไม่พบตัวเลข';
      countdownSemanticsText = 'ไม่พบตัวเลขนับถอยหลัง';
    } else {
      numberText = countdownValue.toString();
      unitText = 'วินาที';
      countdownSemanticsText = 'ตัวเลขนับถอยหลัง $countdownValue วินาที';
    }

    final lightLabel = TrafficSignalClasses.thaiLabel[trafficLightClassName];
    // ต้องมีข้อความบอกสีไฟเสมอ (คนตาบอดสีต้องใช้ได้ ไม่พึ่งสีทางเดียว)
    final semanticsLabel = [?lightLabel, countdownSemanticsText].join(' ');

    return Semantics(
      // ตัด semantics ของ Text ลูกออก เพราะ label ครอบคลุมทั้งสีไฟและตัวเลขแล้ว
      // (กัน screen reader อ่านค่าซ้ำสองรอบ) — ไม่ตั้ง container เพื่อให้ยังรวม
      // อยู่ใต้ liveRegion ของแผงผลเหมือนโครงสร้างเดิม
      excludeSemantics: true,
      label: semanticsLabel,
      child: AnimatedContainer(
        duration: transition,
        width: 86,
        height: 86,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.border),
        ),
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
                child: Text(numberText, maxLines: 1),
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
                child: Text(unitText, maxLines: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
