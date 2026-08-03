import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/features/camera_detection/data/services/traffic_light_state_stabilizer.dart';

TrafficLightObservation _light(
  String className, {
  double confidence = 0.9,
  double left = 0.4,
  double top = 0.1,
  double right = 0.6,
  double bottom = 0.3,
}) {
  return TrafficLightObservation(
    className: className,
    confidence: confidence,
    left: left,
    top: top,
    right: right,
    bottom: bottom,
  );
}

void main() {
  group('TrafficLightStateStabilizer', () {
    test('confirms a red light after two consistent frames', () {
      final stabilizer = TrafficLightStateStabilizer();
      final startedAt = DateTime(2026, 1, 1);

      final first = stabilizer.update([
        _light('red_light_circle'),
      ], timestamp: startedAt);
      final second = stabilizer.update([
        _light('red_light_circle'),
      ], timestamp: startedAt.add(const Duration(milliseconds: 120)));
      final third = stabilizer.update([
        _light('red_light_circle'),
      ], timestamp: startedAt.add(const Duration(milliseconds: 240)));

      expect(first.confirmedClassName, isNull);
      expect(second.confirmedClassName, 'red_light_circle');
      expect(second.stateChanged, isTrue);
      expect(third.confirmedClassName, 'red_light_circle');
      expect(third.stateChanged, isFalse);
    });

    test('requires four green frames before replacing confirmed red', () {
      final stabilizer = TrafficLightStateStabilizer();
      final startedAt = DateTime(2026, 1, 1);

      stabilizer.update([_light('red_light_circle')], timestamp: startedAt);
      stabilizer.update([
        _light('red_light_circle'),
      ], timestamp: startedAt.add(const Duration(milliseconds: 100)));

      for (var frame = 1; frame <= 3; frame++) {
        final update = stabilizer.update([
          _light('green_light_circle'),
        ], timestamp: startedAt.add(Duration(milliseconds: 100 + frame * 100)));
        expect(update.confirmedClassName, 'red_light_circle');
        expect(update.stateChanged, isFalse);
      }

      final confirmedGreen = stabilizer.update([
        _light('green_light_circle'),
      ], timestamp: startedAt.add(const Duration(milliseconds: 500)));

      expect(confirmedGreen.confirmedClassName, 'green_light_circle');
      expect(confirmedGreen.stateChanged, isTrue);
    });

    test('initially prefers a centered light over a distant side light', () {
      final stabilizer = TrafficLightStateStabilizer();
      final startedAt = DateTime(2026, 1, 1);
      final detections = [
        _light('green_light_circle', confidence: 0.99, left: 0.78, right: 0.94),
        _light('red_light_circle', confidence: 0.86),
      ];

      stabilizer.update(detections, timestamp: startedAt);
      final update = stabilizer.update(
        detections,
        timestamp: startedAt.add(const Duration(milliseconds: 120)),
      );

      expect(update.confirmedClassName, 'red_light_circle');
    });

    test('does not jump to another light during a short tracking miss', () {
      final stabilizer = TrafficLightStateStabilizer();
      final startedAt = DateTime(2026, 1, 1);

      stabilizer.update([_light('red_light_circle')], timestamp: startedAt);
      stabilizer.update([
        _light('red_light_circle'),
      ], timestamp: startedAt.add(const Duration(milliseconds: 100)));

      final update = stabilizer.update([
        _light('green_light_circle', confidence: 0.99, left: 0.78, right: 0.94),
      ], timestamp: startedAt.add(const Duration(milliseconds: 300)));

      expect(update.confirmedClassName, 'red_light_circle');
      expect(update.stateChanged, isFalse);
    });

    test('clears the confirmed state after the tracked light times out', () {
      final stabilizer = TrafficLightStateStabilizer(
        trackingTimeout: const Duration(milliseconds: 800),
      );
      final startedAt = DateTime(2026, 1, 1);

      stabilizer.update([_light('yellow_light')], timestamp: startedAt);
      stabilizer.update([
        _light('yellow_light'),
      ], timestamp: startedAt.add(const Duration(milliseconds: 100)));
      final update = stabilizer.update(
        const [],
        timestamp: startedAt.add(const Duration(milliseconds: 901)),
      );

      expect(update.confirmedClassName, isNull);
      expect(update.stateChanged, isTrue);
    });

    test('does not confirm low-confidence observations', () {
      final stabilizer = TrafficLightStateStabilizer(
        minimumObservationConfidence: 0.5,
      );
      final startedAt = DateTime(2026, 1, 1);

      for (var frame = 0; frame < 5; frame++) {
        stabilizer.update([
          _light('red_light_circle', confidence: 0.49),
        ], timestamp: startedAt.add(Duration(milliseconds: frame * 100)));
      }

      expect(stabilizer.confirmedClassName, isNull);
    });

    test('keeps a tracking id and allocates a new one after timeout', () {
      final stabilizer = TrafficLightStateStabilizer(
        trackingTimeout: const Duration(milliseconds: 500),
      );
      final startedAt = DateTime(2026, 1, 1);

      final first = stabilizer.update([
        _light('red_light_circle'),
      ], timestamp: startedAt);
      final second = stabilizer.update([
        _light('red_light_circle', left: 0.41, right: 0.61),
      ], timestamp: startedAt.add(const Duration(milliseconds: 100)));
      final expired = stabilizer.update(
        const [],
        timestamp: startedAt.add(const Duration(milliseconds: 601)),
      );
      final reacquired = stabilizer.update([
        _light('red_light_circle'),
      ], timestamp: startedAt.add(const Duration(milliseconds: 700)));

      expect(first.trackingId, 1);
      expect(second.trackingId, 1);
      expect(expired.trackingId, isNull);
      expect(reacquired.trackingId, 2);
    });
  });
}
