import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/core/services/detection/detection_alert_config.dart';
import 'package:trffic_ilght_app/core/services/detection/detection_stabilizer.dart';
import 'package:trffic_ilght_app/core/services/voice/voice_alert_controller.dart';
import 'package:ultralytics_yolo/yolo.dart';

YOLOResult detection(
  String className, {
  double confidence = 0.9,
  double left = 0.35,
  double top = 0.1,
  double right = 0.65,
  double bottom = 0.4,
}) {
  return YOLOResult(
    classIndex: 0,
    className: className,
    confidence: confidence,
    boundingBox: Rect.fromLTRB(left, top, right, bottom),
    normalizedBox: Rect.fromLTRB(left, top, right, bottom),
  );
}

void main() {
  group('DetectionStabilizer', () {
    test('keeps red stable and never speaks three yellow flickers', () async {
      final stabilizer = DetectionStabilizer();
      final start = DateTime(2026);
      final spoken = <String>[];
      final voice = VoiceAlertController(
        speakClassName: (className) async => spoken.add(className),
      );

      for (var frame = 0; frame < 4; frame++) {
        final update = stabilizer.update([
          detection('red_light_circle'),
        ], timestamp: start.add(Duration(milliseconds: frame * 100)));
        await voice.handleEvents(update.events);
      }

      final events = <DetectionEvent>[];
      for (var frame = 0; frame < 3; frame++) {
        final update = stabilizer.update([
          detection('yellow_light'),
        ], timestamp: start.add(Duration(milliseconds: 400 + frame * 100)));
        events.addAll(update.events);
        await voice.handleEvents(update.events);
      }
      final reverted = stabilizer.update([
        detection('red_light_circle'),
      ], timestamp: start.add(const Duration(milliseconds: 700)));
      await voice.handleEvents(reverted.events);

      expect(reverted.stableDetections.single.className, 'red_light_circle');
      expect(
        events.where(
          (event) =>
              event.type == DetectionEventType.changed &&
              event.detection.className == 'yellow_light',
        ),
        isEmpty,
      );
      expect(spoken, ['red_light_circle']);
    });

    test('changes and speaks yellow once when it wins four of five', () async {
      final stabilizer = DetectionStabilizer();
      final start = DateTime(2026);
      final spoken = <String>[];
      final voice = VoiceAlertController(
        speakClassName: (className) async => spoken.add(className),
      );

      for (var frame = 0; frame < 4; frame++) {
        final update = stabilizer.update([
          detection('red_light_circle'),
        ], timestamp: start.add(Duration(milliseconds: frame * 100)));
        await voice.handleEvents(update.events);
      }

      final events = <DetectionEvent>[];
      for (var frame = 0; frame < 5; frame++) {
        final update = stabilizer.update([
          detection('yellow_light'),
        ], timestamp: start.add(Duration(milliseconds: 400 + frame * 100)));
        events.addAll(update.events);
        await voice.handleEvents(update.events);
      }

      expect(stabilizer.stableDetections.single.className, 'yellow_light');
      expect(
        events.where(
          (event) =>
              event.type == DetectionEventType.changed &&
              event.detection.className == 'yellow_light',
        ),
        hasLength(1),
      );
      expect(spoken, ['red_light_circle', 'yellow_light']);
    });

    test('repeated sign produces and speaks one event until lost', () async {
      final stabilizer = DetectionStabilizer();
      final start = DateTime(2026);
      final events = <DetectionEvent>[];
      final spoken = <String>[];
      final voice = VoiceAlertController(
        speakClassName: (className) async => spoken.add(className),
      );

      for (var frame = 0; frame < 8; frame++) {
        final update = stabilizer.update([
          detection('dont_turn_left'),
        ], timestamp: start.add(Duration(milliseconds: frame * 100)));
        events.addAll(update.events);
        await voice.handleEvents(update.events);
      }

      expect(
        events.where((event) => event.type == DetectionEventType.detected),
        hasLength(1),
      );

      final lost = stabilizer.update(
        const [],
        timestamp: start.add(const Duration(milliseconds: 2301)),
      );
      expect(lost.events.single.type, DetectionEventType.lost);
      expect(lost.stableDetections, isEmpty);
      expect(spoken, ['dont_turn_left']);
    });

    test('turn signal survives a brief flash gap without a repeated event', () {
      final stabilizer = DetectionStabilizer();
      final start = DateTime(2026);
      final events = <DetectionEvent>[];

      for (var frame = 0; frame < 3; frame++) {
        events.addAll(
          stabilizer.update([
            detection('turn_left'),
          ], timestamp: start.add(Duration(milliseconds: frame * 100))).events,
        );
      }
      final missing = stabilizer.update(
        const [],
        timestamp: start.add(const Duration(milliseconds: 700)),
      );
      final returned = stabilizer.update([
        detection('turn_left', left: 0.36, right: 0.66),
      ], timestamp: start.add(const Duration(milliseconds: 900)));
      events.addAll(missing.events);
      events.addAll(returned.events);

      expect(returned.stableDetections.single.className, 'turn_left');
      expect(
        events.where((event) => event.type == DetectionEventType.detected),
        hasLength(1),
      );
      expect(
        events.where((event) => event.type == DetectionEventType.lost),
        isEmpty,
      );
    });

    test('tracks simultaneous objects without mixing their histories', () {
      final stabilizer = DetectionStabilizer();
      final start = DateTime(2026);

      for (var frame = 0; frame < 4; frame++) {
        stabilizer.update([
          detection('red_light_circle', left: 0.1, right: 0.3),
          detection('green_light_circle', left: 0.7, right: 0.9),
        ], timestamp: start.add(Duration(milliseconds: frame * 100)));
      }

      expect(
        stabilizer.stableDetections.map((item) => item.className).toSet(),
        {'red_light_circle', 'green_light_circle'},
      );
      expect(
        stabilizer.stableDetections.map((item) => item.trackId).toSet(),
        hasLength(2),
      );
    });

    test('requires six continuous frames before confirming off light', () {
      final stabilizer = DetectionStabilizer(
        config: const DetectionAlertConfig(
          offLightMinimumFrames: 6,
          offLightMinimumDuration: Duration(milliseconds: 500),
        ),
      );
      final start = DateTime(2026);

      for (var frame = 0; frame < 5; frame++) {
        stabilizer.update([
          detection('off_light'),
        ], timestamp: start.add(Duration(milliseconds: frame * 100)));
      }
      expect(stabilizer.stableDetections, isEmpty);

      final confirmed = stabilizer.update([
        detection('off_light'),
      ], timestamp: start.add(const Duration(milliseconds: 500)));
      expect(confirmed.stableDetections.single.className, 'off_light');
      expect(confirmed.events.single.type, DetectionEventType.detected);
    });

    test(
      'flicker with sparse frames never confirms off light via duration rule',
      () {
        // จำลอง flicker ที่เฟรมมาห่างๆ (เฟรมละ 1 วิ): เห็นไฟเขียว 1 เฟรม
        // แล้วตามด้วย off 8 เฟรม (กิน 7 วิ) — เกณฑ์ระยะเวลา 6 วิ เคยผ่าน
        // ทั้งที่เพิ่งเห็นไฟติดที่ตำแหน่งเดิม lookback ต้องกันไว้
        final stabilizer = DetectionStabilizer();
        final start = DateTime(2026);
        final events = <DetectionEvent>[];

        events.addAll(
          stabilizer.update([
            detection('green_light_circle'),
          ], timestamp: start).events,
        );
        for (var frame = 1; frame <= 8; frame++) {
          events.addAll(
            stabilizer.update([
              detection('off_light'),
            ], timestamp: start.add(Duration(seconds: frame))).events,
          );
          expect(
            stabilizer.stableDetections.where(
              (item) => item.className == 'off_light',
            ),
            isEmpty,
            reason:
                'เฟรมที่ $frame: เพิ่งเห็นไฟเขียวใน lookback = flicker '
                'ต้องไม่รายงานไฟขัดข้อง',
          );
        }
        expect(
          events.where((event) => event.detection.className == 'off_light'),
          isEmpty,
        );
      },
    );

    test(
      'off light burst is suppressed until the lit frame leaves the lookback',
      () {
        // lookback (8) ยาวกว่า minimumFrames (6): ช่วง off รัวๆ หลังเห็นไฟเขียว
        // ต้องถูกกดไว้จนเฟรมไฟเขียวหลุดหน้าต่าง แล้วไฟดับจริงจึงยืนยันได้
        final stabilizer = DetectionStabilizer(
          config: const DetectionAlertConfig(
            offLightMinimumFrames: 6,
            offLightMinimumDuration: Duration(milliseconds: 500),
            flickerLookbackFrames: 8,
          ),
        );
        final start = DateTime(2026);

        stabilizer.update([detection('green_light_circle')], timestamp: start);
        for (var frame = 1; frame <= 7; frame++) {
          stabilizer.update([
            detection('off_light'),
          ], timestamp: start.add(Duration(milliseconds: frame * 100)));
          expect(
            stabilizer.stableDetections.where(
              (item) => item.className == 'off_light',
            ),
            isEmpty,
            reason:
                'เฟรมที่ $frame: ไฟเขียวยังอยู่ใน lookback ต้องยังไม่ยืนยัน',
          );
        }

        // เฟรมที่ 8: ประวัติเต็มหน้าต่าง ไฟเขียวถูก evict ออก -> ไฟดับจริง ยืนยันได้
        final confirmed = stabilizer.update([
          detection('off_light'),
        ], timestamp: start.add(const Duration(milliseconds: 800)));
        expect(confirmed.stableDetections.single.className, 'off_light');
      },
    );

    test(
      'alternating off and green at one location never triggers off light',
      () {
        // flicker ตรงตามโจทย์: off, green, off, green, ... ที่ IoU เดิม
        final stabilizer = DetectionStabilizer();
        final start = DateTime(2026);
        final events = <DetectionEvent>[];

        for (var frame = 0; frame < 30; frame++) {
          final className = frame.isEven ? 'off_light' : 'green_light_circle';
          events.addAll(
            stabilizer.update(
              [detection(className)],
              timestamp: start.add(Duration(milliseconds: frame * 100)),
            ).events,
          );
          expect(
            stabilizer.stableDetections.where(
              (item) => item.className == 'off_light',
            ),
            isEmpty,
          );
        }
        expect(
          events.where((event) => event.detection.className == 'off_light'),
          isEmpty,
        );
      },
    );

    test('genuinely dark light with sparse frames still confirms off light', () {
      // ไฟดับจริง (ไม่เคยเห็นไฟติดเลย) เฟรมห่างๆ -> เกณฑ์ระยะเวลายังทำงานเหมือนเดิม
      final stabilizer = DetectionStabilizer();
      final start = DateTime(2026);

      DetectionStabilizerUpdate? update;
      for (var frame = 0; frame < 8; frame++) {
        update = stabilizer.update([
          detection('off_light'),
        ], timestamp: start.add(Duration(seconds: frame)));
      }

      expect(update!.stableDetections.single.className, 'off_light');
    });

    test('light that turns off for good still raises the off light alert', () {
      // ไฟเขียวติดจริง แล้วดับถาวร: ต้องแจ้งหลังดับสนิทจนพ้นหน้าต่างเวลา 6 วิ
      // นับจากเฟรมไฟติดสุดท้าย (ไม่ใช่ 12 เฟรมเฉยๆ ซึ่งสั้นแค่ 1.2 วิที่ 10fps)
      final stabilizer = DetectionStabilizer();
      final start = DateTime(2026);
      final events = <DetectionEvent>[];

      for (var frame = 0; frame < 4; frame++) {
        stabilizer.update([
          detection('green_light_circle'),
        ], timestamp: start.add(Duration(milliseconds: frame * 100)));
      }
      for (var frame = 4; frame <= 64; frame++) {
        events.addAll(
          stabilizer.update([
            detection('off_light'),
          ], timestamp: start.add(Duration(milliseconds: frame * 100))).events,
        );
        if (frame == 30) {
          // 3 วิหลังไฟเขียวดับ: ยังอยู่ในหน้าต่างกัน flicker ต้องยังไม่ฟันธง
          expect(
            stabilizer.stableDetections.where(
              (item) => item.className == 'off_light',
            ),
            isEmpty,
          );
        }
      }

      expect(stabilizer.stableDetections.single.className, 'off_light');
      expect(
        events.where(
          (event) =>
              event.type == DetectionEventType.changed &&
              event.detection.className == 'off_light',
        ),
        hasLength(1),
      );
    });

    test(
      'video-rate dark stretch after a lit frame does not confirm off light',
      () {
        // อัตราเดียวกับท่อวิดีโอจริง (targetChecksPerSecond = 4 -> 250ms/เฟรม):
        // เห็นไฟเขียว แล้วไฟ "ดูดับ" ยาว 3 วิ (12 เฟรมเต็มหน้าต่างแบบนับเฟรม)
        // ต้องยังไม่แจ้งไฟขัดข้อง เพราะเพิ่งเห็นไฟติดเมื่อ 3 วิก่อน
        final stabilizer = DetectionStabilizer();
        final start = DateTime(2026);

        stabilizer.update([detection('green_light_circle')], timestamp: start);
        for (var frame = 1; frame <= 12; frame++) {
          stabilizer.update([
            detection('off_light'),
          ], timestamp: start.add(Duration(milliseconds: frame * 250)));
          expect(
            stabilizer.stableDetections.where(
              (item) => item.className == 'off_light',
            ),
            isEmpty,
            reason:
                'เฟรมที่ $frame (${frame * 250}ms): ไฟเขียวเพิ่งติดเมื่อ '
                'ไม่ถึง 6 วิ ต้องไม่แจ้งไฟขัดข้อง',
          );
        }

        // ดับต่อเนื่องจนพ้น 6 วิจากเฟรมไฟเขียว -> คราวนี้ดับจริง ต้องยืนยัน
        DetectionStabilizerUpdate? update;
        for (var frame = 13; frame <= 26; frame++) {
          update = stabilizer.update([
            detection('off_light'),
          ], timestamp: start.add(Duration(milliseconds: frame * 250)));
        }
        expect(update!.stableDetections.single.className, 'off_light');
      },
    );

    test(
      'camera-rate dark burst after a lit frame does not confirm off light',
      () {
        // อัตรากล้องเรียลไทม์ (~30fps): 12 เฟรมมืด = แค่ 0.4 วิ
        // สั้นกว่าจังหวะ flicker มาก ต้องไม่พอฟันธงว่าไฟขัดข้อง
        final stabilizer = DetectionStabilizer();
        final start = DateTime(2026);

        for (var frame = 0; frame < 3; frame++) {
          stabilizer.update([
            detection('green_light_circle'),
          ], timestamp: start.add(Duration(milliseconds: frame * 33)));
        }
        for (var frame = 3; frame < 15; frame++) {
          stabilizer.update([
            detection('off_light'),
          ], timestamp: start.add(Duration(milliseconds: frame * 33)));
          expect(
            stabilizer.stableDetections.where(
              (item) => item.className == 'off_light',
            ),
            isEmpty,
            reason:
                'เฟรมที่ $frame: มืดมาแค่ ${(frame - 2) * 33}ms '
                'หลังเห็นไฟเขียว ต้องไม่แจ้งไฟขัดข้อง',
          );
        }
      },
    );

    test(
      'split-track flicker (lens box inside housing box) never confirms off light',
      () {
        // จำลอง track split จากสนามจริง: กล่องไฟเขียว = เลนส์เล็ก, กล่อง off =
        // โคมทั้งแผง IoU ต่ำกว่าเกณฑ์ 0.2 จึงแตกคนละ track — track ของ off
        // จะมีแต่ off ล้วน หลักฐานไฟติดอยู่คนละ track ต้องพึ่ง registry กลาง
        final stabilizer = DetectionStabilizer();
        final start = DateTime(2026);

        for (var frame = 0; frame < 40; frame++) {
          final isLitFrame = frame % 4 == 0; // ไฟติดโผล่ทุก 1 วิ (4fps)
          final input = isLitFrame
              ? detection(
                  'green_light_circle', // เลนส์เล็กกลางโคม
                  left: 0.45,
                  top: 0.05,
                  right: 0.55,
                  bottom: 0.15,
                )
              : detection(
                  'off_light', // โคมทั้งแผง (ทับซ้อนเลนส์แต่ IoU ~0.03)
                  left: 0.2,
                  top: 0.0,
                  right: 0.8,
                  bottom: 0.6,
                );
          stabilizer.update([
            input,
          ], timestamp: start.add(Duration(milliseconds: frame * 250)));
          expect(
            stabilizer.stableDetections.where(
              (item) => item.className == 'off_light',
            ),
            isEmpty,
            reason:
                'เฟรมที่ $frame: เพิ่งเห็นไฟเขียวที่ตำแหน่งทับซ้อนกัน '
                'ภายใน 6 วิ ต้องไม่แจ้งไฟขัดข้อง',
          );
        }
      },
    );

    test('lit sighting survives track expiry and still blocks off light', () {
      // ไฟเขียวโผล่ครั้งเดียวแล้ว track โดน expire (หายเกิน grace 1 วิ)
      // หลักฐานใน registry ต้องยังกัน off_light ได้จนพ้นหน้าต่าง 6 วิ
      final stabilizer = DetectionStabilizer();
      final start = DateTime(2026);

      stabilizer.update([
        detection(
          'green_light_circle',
          left: 0.45,
          top: 0.05,
          right: 0.55,
          bottom: 0.15,
        ),
      ], timestamp: start);

      // เว้นว่าง 1.5 วิ (track ไฟเขียวตาย) แล้วโคมมืดโผล่ที่เดิมยาวๆ
      DetectionStabilizerUpdate? update;
      for (var frame = 0; frame < 30; frame++) {
        final timestamp = start.add(Duration(milliseconds: 1500 + frame * 250));
        update = stabilizer.update([
          detection('off_light', left: 0.2, top: 0.0, right: 0.8, bottom: 0.6),
        ], timestamp: timestamp);
        if (timestamp.difference(start) <= const Duration(seconds: 6)) {
          expect(
            stabilizer.stableDetections.where(
              (item) => item.className == 'off_light',
            ),
            isEmpty,
            reason:
                'ที่ ${timestamp.difference(start).inMilliseconds}ms: '
                'ไฟเขียวยังอยู่ในหน้าต่าง 6 วิ แม้ track จะตายไปแล้ว',
          );
        }
      }

      // พ้นหน้าต่างแล้ว (เฟรมสุดท้าย = 8.75 วิ) -> ไฟดับจริง ต้องยืนยัน
      expect(update!.stableDetections.single.className, 'off_light');
    });

    test('distant lit light does not suppress a separate dark light', () {
      // ไฟติดอยู่คนละมุมจอ ไม่ทับซ้อนเชิงพื้นที่ -> ห้าม suppress ข้ามดวง
      final stabilizer = DetectionStabilizer();
      final start = DateTime(2026);

      stabilizer.update([
        detection(
          'green_light_circle',
          left: 0.0,
          top: 0.0,
          right: 0.1,
          bottom: 0.1,
        ),
      ], timestamp: start);

      DetectionStabilizerUpdate? update;
      for (var frame = 1; frame <= 12; frame++) {
        update = stabilizer.update([
          detection('off_light', left: 0.6, top: 0.6, right: 0.9, bottom: 0.9),
        ], timestamp: start.add(Duration(milliseconds: frame * 100)));
      }

      expect(update!.stableDetections.single.className, 'off_light');
    });

    test('pure continuous off still confirms off light', () {
      // ห้าม regress: off ล้วนๆ ไม่มีการสลับ ต้องยังยืนยัน off_light ตามเดิม
      final stabilizer = DetectionStabilizer();
      final start = DateTime(2026);

      DetectionStabilizerUpdate? update;
      for (var frame = 0; frame < 30; frame++) {
        update = stabilizer.update([
          detection('off_light'),
        ], timestamp: start.add(Duration(milliseconds: frame * 250)));
      }

      expect(update!.stableDetections.single.className, 'off_light');
    });

    test('camera flicker (alternating lit and off) never confirms off light', () {
      // ไฟจราจรปกติแต่กล้องเห็นกะพริบจาก rolling shutter/PWM: สลับ red/off ยาวๆ
      // แม้ off จะสะสมเฟรมมากพอ ห้ามฟันธง off_light เด็ดขาด
      // (ไฟที่เสียจริงต้องดับสนิทต่อเนื่อง ไม่มีเฟรมไฟติดแทรกเลย)
      final stabilizer = DetectionStabilizer();
      final start = DateTime(2026);

      for (var frame = 0; frame < 40; frame++) {
        final className = frame.isEven ? 'red_light_circle' : 'off_light';
        stabilizer.update([
          detection(className),
        ], timestamp: start.add(Duration(milliseconds: frame * 250)));
        expect(
          stabilizer.stableDetections.where(
            (item) => item.className == 'off_light',
          ),
          isEmpty,
          reason:
              'เฟรมที่ $frame: ไฟกะพริบจากกล้องต้องไม่ถูกรายงานเป็นไฟขัดข้อง',
        );
      }
    });

    test('ไฟกะพริบจริงไม่ได้ stable class ใดเลย (ตั้งใจให้เงียบ)', () {
      // พฤติกรรมที่ตั้งใจหลังถอดสถานะสังเคราะห์ flashing_* ออก:
      // pattern สลับ lit<->off ได้โหวตสูงสุด 3/5 ซึ่งต่ำกว่า requiredVotes (4)
      // และ off_light ก็ถูก flicker gate บล็อก -> ไม่มี stable class เลย
      // แอปจึงไม่แสดงป้าย ไม่พูด ตอนเจอทางแยกไฟเหลืองกะพริบ
      // ถ้าเทสต์นี้พัง แปลว่ามีคนเพิ่มตรรกะไฟกะพริบกลับเข้ามา - ตั้งใจหรือไม่?
      final stabilizer = DetectionStabilizer();
      final start = DateTime(2026);
      final events = <DetectionEvent>[];

      DetectionStabilizerUpdate? update;
      for (var frame = 0; frame < 12; frame++) {
        final className = frame.isEven ? 'yellow_light' : 'off_light';
        update = stabilizer.update([
          detection(className),
        ], timestamp: start.add(Duration(milliseconds: frame * 250)));
        events.addAll(update.events);
      }

      expect(update!.stableDetections, isEmpty);
      expect(events, isEmpty);
    });

    test('countdown ROI class never enters stable detections or events', () {
      final stabilizer = DetectionStabilizer();
      final start = DateTime(2026);
      final events = <DetectionEvent>[];

      for (var frame = 0; frame < 8; frame++) {
        events.addAll(
          stabilizer.update([
            detection('sign_number'),
          ], timestamp: start.add(Duration(milliseconds: frame * 100))).events,
        );
      }

      expect(events, isEmpty);
      expect(stabilizer.stableDetections, isEmpty);
    });
  });
}
