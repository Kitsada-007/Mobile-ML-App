import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
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
      final stabilizer = DetectionStabilizer();
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
