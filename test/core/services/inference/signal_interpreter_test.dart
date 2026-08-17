import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/core/services/inference/signal_interpreter.dart';
import 'package:ultralytics_yolo/yolo.dart';

YOLOResult _makeDetection(String className, double confidence) {
  return YOLOResult.fromMap({
    'className': className,
    'confidence': confidence,
    'boundingBox': {'left': 0.0, 'top': 0.0, 'right': 100.0, 'bottom': 100.0},
    'normalizedBox': {'left': 0.0, 'top': 0.0, 'right': 1.0, 'bottom': 1.0},
  });
}

void main() {
  group('SignalInterpreter', () {
    test('green light with turn left and turn right allowed', () {
      final detections = [
        _makeDetection(TrafficSignalClasses.greenLightCircle, 0.9),
        _makeDetection(TrafficSignalClasses.turnLeft, 0.8),
        _makeDetection(TrafficSignalClasses.turnRight, 0.7),
      ];

      final result = SignalInterpreter.interpret(detections);
      expect(result.message, 'ไฟเขียว - ไปได้ (เลี้ยวซ้ายได้, เลี้ยวขวาได้)');
      expect(result.action, SignalAction.go);
    });

    test('red light ignores direction signs for safety', () {
      final detections = [
        _makeDetection(TrafficSignalClasses.redLightCircle, 0.95),
        _makeDetection(TrafficSignalClasses.turnLeft, 0.6),
      ];

      final result = SignalInterpreter.interpret(detections);
      expect(result.message, 'ไฟแดง - หยุดรอ');
      expect(result.action, SignalAction.stop);
    });

    test('red light with countdown 1-5 seconds shows get ready message', () {
      final detections = [
        _makeDetection(TrafficSignalClasses.redLightCircle, 0.95),
      ];

      final result = SignalInterpreter.interpret(
        detections,
        countdownNumberText: '3',
      );
      expect(result.message, 'ไฟแดง - เตรียมออกตัว อีก 3 วินาที');
      expect(result.action, SignalAction.stop);
    });

    test('green light ignores dont turn sign in allowed list', () {
      final detections = [
        _makeDetection(TrafficSignalClasses.greenLightCircle, 0.9),
        _makeDetection(TrafficSignalClasses.dontTurnLeft, 0.7),
      ];

      final result = SignalInterpreter.interpret(detections);
      expect(result.message, 'ไฟเขียว - ไปได้');
      expect(result.action, SignalAction.go);
    });

    test('off light shows system error caution', () {
      final detections = [_makeDetection(TrafficSignalClasses.offLight, 0.85)];

      final result = SignalInterpreter.interpret(detections);
      expect(result.message, 'สัญญาณไฟขัดข้อง - ขับด้วยความระมัดระวัง');
      expect(result.action, SignalAction.caution);
    });

    test('yellow light shows prepare to stop caution', () {
      final detections = [
        _makeDetection(TrafficSignalClasses.yellowLight, 0.88),
      ];

      final result = SignalInterpreter.interpret(detections);
      expect(result.message, 'ไฟเหลือง - เตรียมหยุด');
      expect(result.action, SignalAction.caution);
    });

    test('mutually exclusive light color picks highest confidence light', () {
      final detections = [
        _makeDetection(TrafficSignalClasses.greenLightCircle, 0.6),
        _makeDetection(TrafficSignalClasses.redLightCircle, 0.92),
      ];

      final result = SignalInterpreter.interpret(detections);
      expect(result.message, 'ไฟแดง - หยุดรอ');
      expect(result.action, SignalAction.stop);
    });

    test('returns empty when no light passes threshold', () {
      final detections = [
        _makeDetection(TrafficSignalClasses.greenLightCircle, 0.2),
      ];

      final result = SignalInterpreter.interpret(detections);
      expect(result.message, '');
      expect(result.action, SignalAction.none);
    });

    test('flashing red shows stop-first caution and ignores countdown', () {
      // ไฟกะพริบไม่มีนับถอยหลัง — ส่ง countdownNumberText มาก็ต้องไม่ติดข้อความ
      final detections = [
        _makeDetection(TrafficSignalClasses.flashingRed, 0.9),
      ];

      final result = SignalInterpreter.interpret(
        detections,
        countdownNumberText: '3',
      );
      expect(result.message, 'ไฟแดงกะพริบ - หยุดก่อน แล้วไปเมื่อปลอดภัย');
      expect(result.message, contains('กะพริบ'));
      expect(result.action, SignalAction.caution);
    });

    test('flashing yellow shows slow-down caution', () {
      final detections = [
        _makeDetection(TrafficSignalClasses.flashingYellow, 0.9),
      ];

      final result = SignalInterpreter.interpret(detections);
      expect(result.message, 'ไฟเหลืองกะพริบ - ชะลอความเร็ว ระวังทางแยก');
      expect(result.message, contains('กะพริบ'));
      expect(result.action, SignalAction.caution);
    });

    test('interprets straight arrow and turn right when no traffic light is detected', () {
      final detections = [
        _makeDetection(TrafficSignalClasses.goStraightArrow, 0.85),
        _makeDetection(TrafficSignalClasses.turnRight, 0.8),
      ];

      final result = SignalInterpreter.interpret(detections);
      expect(result.message, 'ตรงไปได้, เลี้ยวขวาได้');
      expect(result.action, SignalAction.go);
    });
  });
}
