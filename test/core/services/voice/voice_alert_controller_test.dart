import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/core/services/detection/detection_stabilizer.dart';
import 'package:trffic_ilght_app/core/services/voice/voice_alert_controller.dart';

StableDetection stableDetection(String className, {int trackId = 1}) {
  return StableDetection(
    trackId: trackId,
    className: className,
    confidence: 0.9,
    boundingBox: const Rect.fromLTRB(0, 0, 10, 10),
    normalizedBox: const Rect.fromLTRB(0, 0, 1, 1),
  );
}

DetectionEvent event(
  String className,
  DateTime timestamp, {
  DetectionEventType type = DetectionEventType.detected,
}) {
  return DetectionEvent(
    type: type,
    detection: stableDetection(className),
    timestamp: timestamp,
  );
}

void main() {
  test('announces only the highest-priority event in one frame', () async {
    final spoken = <String>[];
    final controller = VoiceAlertController(
      speakClassName: (classNames) async => spoken.add(classNames.join(' + ')),
    );
    final now = DateTime(2026);

    final selected = await controller.handleEvents([
      event('sign_number', now),
      event('green_light_circle', now),
      event('off_light', now),
      event('red_light_circle', now),
    ]);

    expect(selected?.detection.className, 'off_light');
    expect(spoken, ['off_light']);
  });

  test('รวมไฟเขียวกับลูกศรที่เห็นพร้อมกันเป็นประโยคเดียว', () async {
    final spoken = <String>[];
    final controller = VoiceAlertController(
      speakClassName: (classNames) async => spoken.add(classNames.join(' + ')),
    );
    final now = DateTime(2026);

    await controller.handleEvents([
      event('green_light_circle', now),
      event('go_straight_arrow', now),
    ]);

    // ไฟเขียวกับลูกศรไปในทางเดียวกัน รวมได้
    expect(spoken, ['green_light_circle + go_straight_arrow']);
  });

  test('ไฟแดงพูดเดี่ยว และไม่พูดลูกศรตามหลัง', () async {
    final spoken = <String>[];
    final controller = VoiceAlertController(
      speakClassName: (classNames) async => spoken.add(classNames.join(' + ')),
    );
    final now = DateTime(2026);

    await controller.handleEvents([
      event('red_light_circle', now),
      event('go_straight_arrow', now),
    ]);

    // 'ไฟแดง หยุดรถ ตรงไปได้' เป็นคำสั่งที่ขัดกันเอง ทั้งในประโยคเดียวและคนละประโยค
    expect(spoken, ['red_light_circle']);
    expect(controller.pendingCount, 0);
  });

  test('ไฟเหลืองและไฟเสียก็ต้องพูดเดี่ยวเช่นกัน', () async {
    final now = DateTime(2026);

    for (final soloClass in ['yellow_light', 'off_light']) {
      final spoken = <String>[];
      final controller = VoiceAlertController(
        speakClassName: (classNames) async =>
            spoken.add(classNames.join(' + ')),
      );

      await controller.handleEvents([
        event(soloClass, now),
        event('turn_right', now),
      ]);

      expect(spoken, [soloClass], reason: '$soloClass ต้องพูดเดี่ยว');
    }
  });

  test('ลูกศรที่เห็นคนละจังหวะกับไฟแดงยังพูดได้ตามปกติ', () async {
    final spoken = <String>[];
    final controller = VoiceAlertController(
      speakClassName: (classNames) async => spoken.add(classNames.join(' + ')),
      combineWindow: const Duration(seconds: 1),
    );
    final now = DateTime(2026);

    await controller.handleEvents([event('red_light_circle', now)]);
    await controller.handleEvents([
      event('turn_right', now.add(const Duration(seconds: 5))),
    ]);

    expect(spoken, ['red_light_circle', 'turn_right']);
  });

  test('ไม่รวมสถานะไฟสองสีเข้าด้วยกัน', () async {
    final spoken = <String>[];
    final controller = VoiceAlertController(
      speakClassName: (classNames) async => spoken.add(classNames.join(' + ')),
    );
    final now = DateTime(2026);

    await controller.handleEvents([
      event('red_light_circle', now),
      event('green_light_circle', now),
    ]);

    // แดงกับเขียวเป็นจริงพร้อมกันไม่ได้ พูดรวมกันจะเป็นคำสั่งที่ขัดกันเอง
    expect(spoken, ['red_light_circle']);
  });

  test('ไม่รวมสัญญาณที่เกิดคนละจังหวะเข้าด้วยกัน', () async {
    final spoken = <String>[];
    final controller = VoiceAlertController(
      speakClassName: (classNames) async => spoken.add(classNames.join(' + ')),
      combineWindow: const Duration(seconds: 1),
    );
    final now = DateTime(2026);

    await controller.handleEvents([
      event('turn_right', now),
      event('go_straight_arrow', now.add(const Duration(seconds: 3))),
    ]);

    // ยังได้ยินครบ แต่ต้องเป็นคนละประโยค (ไม่มี ' + ' = ไม่ถูกรวม)
    expect(spoken, ['turn_right', 'go_straight_arrow']);
  });

  test('applies the group cooldown to repeated classes', () async {
    final spoken = <String>[];
    final controller = VoiceAlertController(
      speakClassName: (classNames) async => spoken.add(classNames.join(' + ')),
    );
    final start = DateTime(2026);

    await controller.handleEvents([event('red_light_circle', start)]);
    await controller.handleEvents([
      event(
        'red_light_circle',
        start.add(const Duration(seconds: 2)),
        type: DetectionEventType.changed,
      ),
    ]);
    await controller.handleEvents([
      event(
        'red_light_circle',
        start.add(const Duration(seconds: 3)),
        type: DetectionEventType.changed,
      ),
    ]);

    expect(spoken, ['red_light_circle', 'red_light_circle']);
  });

  test('never announces the sign_number ROI class', () async {
    final spoken = <String>[];
    final controller = VoiceAlertController(
      speakClassName: (classNames) async => spoken.add(classNames.join(' + ')),
    );

    final selected = await controller.handleEvents([
      event('sign_number', DateTime(2026)),
    ]);

    expect(selected, isNull);
    expect(spoken, isEmpty);
  });

  test(
    'queues an event that arrives while speaking instead of dropping it',
    () async {
      final releaseSpeech = Completer<void>();
      final spoken = <String>[];
      final controller = VoiceAlertController(
        speakClassName: (classNames) async {
          spoken.add(classNames.join(' + '));
          await releaseSpeech.future;
        },
      );
      final now = DateTime(2026);

      final first = controller.handleEvents([event('turn_right', now)]);
      await Future<void>.delayed(Duration.zero);
      // ห้ามพูดซ้อน แต่ก็ห้ามทิ้ง event ทิ้งไปเฉย ๆ เพราะ stabilizer ยิงครั้งเดียว
      // (ไฟแดงที่โผล่มาระหว่างกำลังพูดอยู่ คือเคสที่เคยเงียบหายไปเลย)
      final overlapping = await controller.handleEvents([
        event('red_light_circle', now.add(const Duration(seconds: 1))),
      ]);
      final lost = await controller.handleEvents([
        event(
          'yellow_light',
          now.add(const Duration(seconds: 1)),
          type: DetectionEventType.lost,
        ),
      ]);

      expect(overlapping, isNull);
      expect(lost, isNull);
      expect(spoken, ['turn_right']);
      expect(controller.pendingCount, 1);

      releaseSpeech.complete();
      await first;

      expect(spoken, ['turn_right', 'red_light_circle']);
    },
  );

  test('a lost event removes that class from the waiting queue', () async {
    final releaseSpeech = Completer<void>();
    final spoken = <String>[];
    final controller = VoiceAlertController(
      speakClassName: (classNames) async {
        spoken.add(classNames.join(' + '));
        await releaseSpeech.future;
      },
    );
    final now = DateTime(2026);

    final first = controller.handleEvents([event('go_straight_arrow', now)]);
    await Future<void>.delayed(Duration.zero);
    await controller.handleEvents([
      event('turn_right', now.add(const Duration(seconds: 1))),
    ]);
    await controller.handleEvents([
      event(
        'turn_right',
        now.add(const Duration(seconds: 2)),
        type: DetectionEventType.lost,
      ),
    ]);
    expect(controller.pendingCount, 0);

    releaseSpeech.complete();
    await first;

    // ป้ายหลุดจอไปแล้ว จึงต้องไม่ถูกประกาศตามหลัง
    expect(spoken, ['go_straight_arrow']);
  });

  test('a more important event interrupts the message being spoken', () async {
    final releaseGreen = Completer<void>();
    final spoken = <String>[];
    var interruptCount = 0;
    final controller = VoiceAlertController(
      speakClassName: (classNames) async {
        final message = classNames.join(' + ');
        spoken.add(message);
        if (message == 'green_light_circle') {
          await releaseGreen.future;
        }
      },
      interruptSpeech: () async {
        interruptCount = interruptCount + 1;
        // จำลอง TrafficVoiceService.stop() ที่ทำให้ประโยคเดิมจบทันที
        releaseGreen.complete();
      },
    );
    final now = DateTime(2026);

    final greenSpeech = controller.handleEvents([
      event('green_light_circle', now),
    ]);
    await Future<void>.delayed(Duration.zero);
    final redSpeech = await controller.handleEvents([
      event('red_light_circle', now.add(const Duration(milliseconds: 500))),
    ]);
    await greenSpeech;

    expect(interruptCount, 1);
    expect(redSpeech?.detection.className, 'red_light_circle');
    expect(spoken, ['green_light_circle', 'red_light_circle']);
  });

  test('a less important event never interrupts', () async {
    final releaseSpeech = Completer<void>();
    final spoken = <String>[];
    var interruptCount = 0;
    final controller = VoiceAlertController(
      speakClassName: (classNames) async {
        spoken.add(classNames.join(' + '));
        await releaseSpeech.future;
      },
      interruptSpeech: () async {
        interruptCount = interruptCount + 1;
      },
    );
    final now = DateTime(2026);

    final first = controller.handleEvents([event('red_light_circle', now)]);
    await Future<void>.delayed(Duration.zero);
    await controller.handleEvents([
      event('turn_left', now.add(const Duration(milliseconds: 500))),
    ]);

    expect(interruptCount, 0);
    expect(spoken, ['red_light_circle']);

    releaseSpeech.complete();
    await first;
  });

  test('announces every direction signal seen at the same moment', () async {
    final spoken = <String>[];
    final controller = VoiceAlertController(
      speakClassName: (classNames) async => spoken.add(classNames.join(' + ')),
    );
    final now = DateTime(2026);

    await controller.handleEvents([
      event('go_straight_arrow', now),
      event('turn_right', now),
    ]);

    // ทิศทางสองอย่างเป็นจริงพร้อมกันได้ ต้องได้ยินครบในประโยคเดียว
    // (ถ้าแยกเป็นสองประโยค ไฟอาจเปลี่ยนไปก่อนจะพูดจบ)
    expect(spoken, ['turn_right + go_straight_arrow']);
  });

  test('drops queued events that are too old to still be true', () async {
    final releaseSpeech = Completer<void>();
    final spoken = <String>[];
    final controller = VoiceAlertController(
      speakClassName: (classNames) async {
        spoken.add(classNames.join(' + '));
        await releaseSpeech.future;
      },
      pendingRetention: const Duration(seconds: 1),
    );
    final now = DateTime(2026);

    final first = controller.handleEvents([event('red_light_circle', now)]);
    await Future<void>.delayed(Duration.zero);
    await controller.handleEvents([
      event('turn_right', now.add(const Duration(milliseconds: 100))),
    ]);
    expect(controller.pendingCount, 1);

    // เวลาเดินไปไกลกว่าอายุคิว -> ข้อมูลเก่าเกินกว่าจะพูดออกไปแล้ว
    await controller.handleEvents(
      const <DetectionEvent>[],
      timestamp: now.add(const Duration(seconds: 5)),
    );
    expect(controller.pendingCount, 0);

    releaseSpeech.complete();
    await first;

    expect(spoken, ['red_light_circle']);
  });

  test(
    'countdown message cannot overlap a yellow-light announcement',
    () async {
      final releaseSpeech = Completer<void>();
      final spoken = <String>[];
      final controller = VoiceAlertController(
        speakClassName: (classNames) async {
          spoken.add(classNames.join(' + '));
          await releaseSpeech.future;
        },
      );

      final yellowSpeech = controller.handleEvents([
        event('yellow_light', DateTime(2026)),
      ]);
      await Future<void>.delayed(Duration.zero);
      final didSpeakCountdown = await controller.speakMessageIfIdle(() async {
        spoken.add('countdown');
      });
      releaseSpeech.complete();
      await yellowSpeech;

      expect(didSpeakCountdown, isFalse);
      expect(spoken, ['yellow_light']);
    },
  );

  test(
    'skips highest priority candidate if on cooldown and announces next available candidate',
    () async {
      final spoken = <String>[];
      final controller = VoiceAlertController(
        speakClassName: (classNames) async =>
            spoken.add(classNames.join(' + ')),
      );
      final start = DateTime(2026);

      // 1. Speak turn_right first
      await controller.handleEvents([event('turn_right', start)]);
      expect(spoken, ['turn_right']);

      // 2. Next frame (2 seconds later): turn_right is on 5s cooldown, but go_straight_arrow is fresh
      final selected = await controller.handleEvents([
        event('turn_right', start.add(const Duration(seconds: 2))),
        event('go_straight_arrow', start.add(const Duration(seconds: 2))),
      ]);

      expect(selected?.detection.className, 'go_straight_arrow');
      expect(spoken, ['turn_right', 'go_straight_arrow']);
    },
  );
}
