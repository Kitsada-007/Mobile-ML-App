import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/core/services/voice/countdown_alert_controller.dart';

void main() {
  group('CountdownAlertController', () {
    test('red light at five seconds emits prepare-to-depart once', () {
      final controller = CountdownAlertController();

      final first = controller.update(
        isSignDetected: true,
        detectedNumber: '5',
        stableTrafficLightClassName: 'red_light_circle',
      );
      final repeated = controller.update(
        isSignDetected: true,
        detectedNumber: '5',
        stableTrafficLightClassName: 'red_light_circle',
      );

      expect(first.uiMessage, 'เหลืออีก 5 วินาที · เตรียมออกตัว');
      expect(first.event?.type, CountdownEventType.countdownThresholdReached);
      expect(first.event?.voiceMessage, 'ไฟแดงใกล้หมด เตรียมออกตัว');
      expect(repeated.event, isNull);
    });

    test('green light at five seconds emits prepare-to-stop once', () {
      final controller = CountdownAlertController();

      final update = controller.update(
        isSignDetected: true,
        detectedNumber: '5',
        stableTrafficLightClassName: 'green_light_circle',
      );

      expect(update.uiMessage, 'เหลืออีก 5 วินาที · เตรียมหยุด');
      expect(update.event?.voiceMessage, 'ไฟเขียวใกล้หมด เตรียมหยุด');
    });

    test('five down to one does not repeat the threshold event', () {
      final controller = CountdownAlertController();
      final events = <CountdownAlertEvent>[];

      for (final number in ['5', '4', '3', '2', '1']) {
        final update = controller.update(
          isSignDetected: true,
          detectedNumber: number,
          stableTrafficLightClassName: 'red_light_circle',
        );
        if (update.event != null) events.add(update.event!);
      }

      expect(events, hasLength(1));
    });

    test('number without a stable light stays visible and silent', () {
      final controller = CountdownAlertController();

      final update = controller.update(
        isSignDetected: true,
        detectedNumber: '5',
        stableTrafficLightClassName: null,
      );

      expect(update.uiMessage, 'เหลืออีก 5 วินาที');
      expect(update.event, isNull);
    });

    test('unreadable number stays silent', () {
      final controller = CountdownAlertController();

      final update = controller.update(
        isSignDetected: true,
        detectedNumber: null,
        stableTrafficLightClassName: 'red_light_circle',
      );

      expect(update.uiMessage, isNull);
      expect(update.event, isNull);
    });

    test('yellow countdown shows stop but emits no countdown voice', () {
      final controller = CountdownAlertController();

      final update = controller.update(
        isSignDetected: true,
        detectedNumber: '5',
        stableTrafficLightClassName: 'yellow_light',
      );

      expect(update.uiMessage, 'เหลืออีก 5 วินาที · หยุด');
      expect(update.event, isNull);
    });

    test('sign loss and a number above threshold re-arm the event', () {
      final controller = CountdownAlertController();

      controller.update(
        isSignDetected: true,
        detectedNumber: '5',
        stableTrafficLightClassName: 'red_light_circle',
      );
      controller.update(
        isSignDetected: false,
        detectedNumber: null,
        stableTrafficLightClassName: 'red_light_circle',
      );
      final afterLoss = controller.update(
        isSignDetected: true,
        detectedNumber: '5',
        stableTrafficLightClassName: 'red_light_circle',
      );
      controller.update(
        isSignDetected: true,
        detectedNumber: '6',
        stableTrafficLightClassName: 'red_light_circle',
      );
      final afterAboveThreshold = controller.update(
        isSignDetected: true,
        detectedNumber: '5',
        stableTrafficLightClassName: 'red_light_circle',
      );

      expect(afterLoss.event, isNotNull);
      expect(afterAboveThreshold.event, isNotNull);
    });

    test('a verified traffic-light change re-arms the event', () {
      final controller = CountdownAlertController();

      controller.update(
        isSignDetected: true,
        detectedNumber: '5',
        stableTrafficLightClassName: 'red_light_circle',
      );
      final changed = controller.update(
        isSignDetected: true,
        detectedNumber: '5',
        stableTrafficLightClassName: 'green_light_circle',
      );

      expect(changed.event?.voiceMessage, 'ไฟเขียวใกล้หมด เตรียมหยุด');
    });
  });
}
