import 'package:ultralytics_yolo/yolo.dart';

enum SignalCategory { lightColor, direction, countdown, unknown }

class TrafficSignalClasses {
  static const dontGoStraightArrow = 'dont_go_straight_arrow';
  static const dontTurnLeft = 'dont_turn_left';
  static const dontTurnRight = 'dont_turn_right';
  static const goStraightArrow = 'go_straight_arrow';
  static const greenLightCircle = 'green_light_circle';
  static const greenLight = 'green_light';
  static const offLight = 'off_light';
  static const redLightCircle = 'red_light_circle';
  static const redLight = 'red_light';
  static const signNumber = 'sign_number';
  static const turnLeft = 'turn_left';
  static const turnRight = 'turn_right';
  static const yellowLight = 'yellow_light';
  static const yellowLightCircle = 'yellow_light_circle';

  static Map<String, String> get thaiLabel => {
    dontGoStraightArrow: 'ห้ามตรงไป',
    dontTurnLeft: 'ห้ามเลี้ยวซ้าย',
    dontTurnRight: 'ห้ามเลี้ยวขวา',
    goStraightArrow: 'ตรงไปได้',
    greenLightCircle: 'ไฟเขียว',
    greenLight: 'ไฟเขียว',
    offLight: 'ไฟขัดข้อง',
    redLightCircle: 'ไฟแดง',
    redLight: 'ไฟแดง',
    signNumber: 'ตัวเลขนับถอยหลัง',
    turnLeft: 'เลี้ยวซ้ายได้',
    turnRight: 'เลี้ยวขวาได้',
    yellowLight: 'ไฟเหลือง',
    yellowLightCircle: 'ไฟเหลือง',
  };

  /// แบ่งหมวด: สีไฟ (แข่งกัน เลือกได้อันเดียว) vs ทิศทาง (เกิดร่วมกันได้หลายอัน)
  static Map<String, SignalCategory> get categoryOf => {
    redLightCircle: SignalCategory.lightColor,
    redLight: SignalCategory.lightColor,
    yellowLight: SignalCategory.lightColor,
    yellowLightCircle: SignalCategory.lightColor,
    greenLightCircle: SignalCategory.lightColor,
    greenLight: SignalCategory.lightColor,
    offLight: SignalCategory.lightColor,
    turnLeft: SignalCategory.direction,
    turnRight: SignalCategory.direction,
    dontTurnLeft: SignalCategory.direction,
    dontTurnRight: SignalCategory.direction,
    goStraightArrow: SignalCategory.direction,
    dontGoStraightArrow: SignalCategory.direction,
    signNumber: SignalCategory.countdown,
  };
}

/// ผลลัพธ์สุดท้ายที่พร้อมแสดงให้ user ดู - ไม่มี class name โผล่มาเลย
class DriverSignalResult {
  final String message; // เช่น "ไฟเขียว - ไปได้ (เลี้ยวซ้ายได้, เลี้ยวขวาได้)"
  final SignalAction action;
  const DriverSignalResult({required this.message, required this.action});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DriverSignalResult &&
          runtimeType == other.runtimeType &&
          message == other.message &&
          action == other.action;

  @override
  int get hashCode => message.hashCode ^ action.hashCode;

  @override
  String toString() => 'DriverSignalResult(message: $message, action: $action)';
}

enum SignalAction { go, stop, caution, none }

class SignalInterpreter {
  static const double defaultConfidenceThreshold = 0.25;

  static DriverSignalResult interpret(
    List<YOLOResult> detections, {
    String? countdownNumberText,
    double confidenceThreshold = defaultConfidenceThreshold,
  }) {
    // 1. แยกตามหมวด
    YOLOResult? bestLight;
    final List<YOLOResult> directions = [];

    for (final d in detections) {
      if (d.confidence < confidenceThreshold) continue;

      final category = TrafficSignalClasses.categoryOf[d.className];
      if (category == SignalCategory.lightColor) {
        if (bestLight == null || d.confidence > bestLight.confidence) {
          bestLight = d;
        }
      } else if (category == SignalCategory.direction) {
        directions.add(d);
      }
      // signNumber ไม่เข้ามาที่นี่ ถูกจัดการแยกใน pipeline number model
    }

    // 2. ไม่เจอไฟเลย -> ตรวจสอบว่ามีป้ายทิศทางหรือสัญญาณทิศทางหรือไม่
    if (bestLight == null) {
      if (directions.isEmpty) {
        return const DriverSignalResult(message: '', action: SignalAction.none);
      }

      final allowed = directions
          .where((d) => !d.className.startsWith('dont_'))
          .map((d) => TrafficSignalClasses.thaiLabel[d.className])
          .whereType<String>()
          .toSet()
          .toList();

      final disallowed = directions
          .where((d) => d.className.startsWith('dont_'))
          .map((d) => TrafficSignalClasses.thaiLabel[d.className])
          .whereType<String>()
          .toSet()
          .toList();

      if (allowed.isNotEmpty) {
        final buffer = StringBuffer(allowed.join(', '));
        if (disallowed.isNotEmpty) {
          buffer.write(' (${disallowed.join(', ')})');
        }
        return DriverSignalResult(
          message: buffer.toString(),
          action: SignalAction.go,
        );
      } else if (disallowed.isNotEmpty) {
        return DriverSignalResult(
          message: disallowed.join(', '),
          action: SignalAction.caution,
        );
      }

      return const DriverSignalResult(message: '', action: SignalAction.none);
    }

    // 3. สังเคราะห์เป็นข้อความเดียว ให้คนขับอ่านแล้วเข้าใจทันที
    return _buildMessage(bestLight, directions, countdownNumberText);
  }

  static DriverSignalResult _buildMessage(
    YOLOResult light,
    List<YOLOResult> directions,
    String? countdownNumberText,
  ) {
    final lightKey = light.className;

    // ไฟแดง = หยุดเสมอ ไม่ต้องสนใจป้ายทิศทางเลย (ความปลอดภัยมาก่อน)
    if (lightKey == TrafficSignalClasses.redLightCircle || lightKey == TrafficSignalClasses.redLight) {
      final String countdownText;
      if (countdownNumberText == null) {
        countdownText = '';
      } else {
        countdownText = countdownNumberText;
      }
      final number = int.tryParse(countdownText);
      if (number != null && number >= 1 && number <= 5) {
        return DriverSignalResult(
          message: 'ไฟแดง - เตรียมออกตัว อีก $number วินาที',
          action: SignalAction.stop,
        );
      }
      return const DriverSignalResult(
        message: 'ไฟแดง - หยุดรอ',
        action: SignalAction.stop,
      );
    }

    // ไฟเหลือง = เตือนให้ระวัง
    if (lightKey == TrafficSignalClasses.yellowLight || lightKey == TrafficSignalClasses.yellowLightCircle) {
      return const DriverSignalResult(
        message: 'ไฟเหลือง - เตรียมหยุด',
        action: SignalAction.caution,
      );
    }

    // ไฟขัดข้อง = เตือนพิเศษ
    if (lightKey == TrafficSignalClasses.offLight) {
      return const DriverSignalResult(
        message: 'สัญญาณไฟขัดข้อง - ขับด้วยความระมัดระวัง',
        action: SignalAction.caution,
      );
    }

    // ไฟเขียว = รวมทิศทางที่อนุญาตเข้าไปในข้อความเดียว
    if (lightKey == TrafficSignalClasses.greenLightCircle || lightKey == TrafficSignalClasses.greenLight) {
      final allowed = directions
          .where((d) => !d.className.startsWith('dont_'))
          .map((d) => TrafficSignalClasses.thaiLabel[d.className])
          .whereType<String>()
          .toSet()
          .toList();

      final buffer = StringBuffer('ไฟเขียว - ไปได้');
      if (allowed.isNotEmpty) {
        buffer.write(' (${allowed.join(', ')})');
      }
      return DriverSignalResult(
        message: buffer.toString(),
        action: SignalAction.go,
      );
    }

    return const DriverSignalResult(message: '', action: SignalAction.none);
  }
}
