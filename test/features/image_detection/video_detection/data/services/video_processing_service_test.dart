import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/features/video_detection/data/services/video_processing_service.dart';

void main() {
  group('CountdownHoldTracker', () {
    test('holds the last number and keeps signPresent through the window', () {
      // เกณฑ์ผ่านของงาน: หลุด sign_number ไป 1–3 เฟรมติดกันต้องยังแสดงเลขเดิม
      // เฟรมที่ 4 ขึ้นไปจึงล้างเป็น null
      final tracker = CountdownHoldTracker(maxHoldFrames: 3);

      final accepted = tracker.process(
        stabilizedNumber: '12',
        hasSignDetection: true,
      );
      expect(accepted.finalNumber, '12');
      expect(accepted.signPresent, isTrue);

      // ป้ายกะพริบหาย 3 เฟรมติด — ทุกเฟรมต้อง hold เลขเดิมและถือว่าป้ายยังอยู่
      for (var frame = 0; frame < 3; frame++) {
        final held = tracker.process(
          stabilizedNumber: null,
          hasSignDetection: false,
        );
        expect(held.finalNumber, '12', reason: 'hold frame ${frame + 1}');
        expect(held.signPresent, isTrue, reason: 'hold frame ${frame + 1}');
      }

      // เฟรมที่ 4 หมดโควตา hold → ล้างเป็น null และป้ายถือว่าหายจริง
      final expired = tracker.process(
        stabilizedNumber: null,
        hasSignDetection: false,
      );
      expect(expired.finalNumber, isNull);
      expect(expired.signPresent, isFalse);
    });

    test('a fresh accepted number refills the hold window', () {
      final tracker = CountdownHoldTracker(maxHoldFrames: 3);

      tracker.process(stabilizedNumber: '10', hasSignDetection: true);
      tracker.process(stabilizedNumber: null, hasSignDetection: false);
      tracker.process(stabilizedNumber: null, hasSignDetection: false);
      // เจอเลขใหม่ก่อนหมดโควตา → เติม hold ให้เต็มอีกครั้ง
      tracker.process(stabilizedNumber: '9', hasSignDetection: true);

      for (var frame = 0; frame < 3; frame++) {
        final held = tracker.process(
          stabilizedNumber: null,
          hasSignDetection: false,
        );
        expect(held.finalNumber, '9');
        expect(held.signPresent, isTrue);
      }
      final expired = tracker.process(
        stabilizedNumber: null,
        hasSignDetection: false,
      );
      expect(expired.finalNumber, isNull);
      expect(expired.signPresent, isFalse);
    });

    test('sign box without a readable number still reports signPresent', () {
      final tracker = CountdownHoldTracker(maxHoldFrames: 3);

      // ตรวจเจอกล่อง sign_number แต่ stabilizer ยังไม่ยอมรับเลข —
      // ป้ายถือว่าอยู่ (กล่องจริง) แม้ยังไม่มีเลขให้แสดง
      final result = tracker.process(
        stabilizedNumber: null,
        hasSignDetection: true,
      );
      expect(result.finalNumber, isNull);
      expect(result.signPresent, isTrue);
    });
  });

  group('FrameAnalysisResult', () {
    test('signPresent defaults to false', () {
      const result = FrameAnalysisResult(detections: []);
      expect(result.signPresent, isFalse);
    });
  });
}
