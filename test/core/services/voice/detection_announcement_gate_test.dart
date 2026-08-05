import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/core/services/voice/detection_announcement_gate.dart';

void main() {
  test('requires two consecutive frames for a detection', () {
    final gate = DetectionAnnouncementGate();
    final first = DateTime(2026);
    expect(gate.shouldAnnounce('red_light_circle', first), isFalse);
    expect(
      gate.shouldAnnounce(
        'red_light_circle',
        first.add(const Duration(milliseconds: 100)),
      ),
      isTrue,
    );
  });

  test('blocks the same detection during cooldown', () {
    final gate = DetectionAnnouncementGate();
    final first = DateTime(2026);
    gate.shouldAnnounce('red_light_circle', first);
    gate.record('red_light_circle', first.add(const Duration(milliseconds: 100)));
    expect(
      gate.shouldAnnounce(
        'red_light_circle',
        first.add(const Duration(seconds: 2)),
      ),
      isFalse,
    );
  });

  test('allows a changed detection immediately', () {
    final gate = DetectionAnnouncementGate();
    final first = DateTime(2026);
    gate.shouldAnnounce('red_light_circle', first);
    gate.record('red_light_circle', first.add(const Duration(milliseconds: 100)));
    expect(
      gate.shouldAnnounce(
        'green_light_circle',
        first.add(const Duration(seconds: 1)),
      ),
      isFalse,
    );
    expect(
      gate.shouldAnnounce(
        'green_light_circle',
        first.add(const Duration(seconds: 1, milliseconds: 100)),
      ),
      isTrue,
    );
  });
}
