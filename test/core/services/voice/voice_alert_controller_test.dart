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
      speakClassName: (className) async => spoken.add(className),
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

  test('applies the group cooldown to repeated classes', () async {
    final spoken = <String>[];
    final controller = VoiceAlertController(
      speakClassName: (className) async => spoken.add(className),
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
      speakClassName: (className) async => spoken.add(className),
    );

    final selected = await controller.handleEvents([
      event('sign_number', DateTime(2026)),
    ]);

    expect(selected, isNull);
    expect(spoken, isEmpty);
  });

  test('does not overlap speech and ignores lost events', () async {
    final releaseSpeech = Completer<void>();
    final spoken = <String>[];
    final controller = VoiceAlertController(
      speakClassName: (className) async {
        spoken.add(className);
        await releaseSpeech.future;
      },
    );
    final now = DateTime(2026);

    final first = controller.handleEvents([event('red_light_circle', now)]);
    await Future<void>.delayed(Duration.zero);
    final overlapping = await controller.handleEvents([
      event('off_light', now.add(const Duration(seconds: 1))),
    ]);
    final lost = await controller.handleEvents([
      event(
        'yellow_light',
        now.add(const Duration(seconds: 1)),
        type: DetectionEventType.lost,
      ),
    ]);
    releaseSpeech.complete();
    await first;

    expect(overlapping, isNull);
    expect(lost, isNull);
    expect(spoken, ['red_light_circle']);
  });

  test(
    'countdown message cannot overlap a yellow-light announcement',
    () async {
      final releaseSpeech = Completer<void>();
      final spoken = <String>[];
      final controller = VoiceAlertController(
        speakClassName: (className) async {
          spoken.add(className);
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
}
