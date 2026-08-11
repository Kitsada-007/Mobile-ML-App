import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/features/video_detection/data/services/video_processing_service.dart';

void main() {
  group('calculateSampleInterval', () {
    test(
      'calculates interval based on sourceFps and targetChecksPerSecond',
      () {
        expect(
          calculateSampleInterval(sourceFps: 30, targetChecksPerSecond: 4),
          8,
        );
        expect(
          calculateSampleInterval(sourceFps: 24, targetChecksPerSecond: 4),
          6,
        );
        expect(
          calculateSampleInterval(sourceFps: 60, targetChecksPerSecond: 4),
          15,
        );
        expect(
          calculateSampleInterval(sourceFps: 5, targetChecksPerSecond: 4),
          1,
        );
      },
    );

    test('handles edge cases gracefully', () {
      expect(
        calculateSampleInterval(sourceFps: 0, targetChecksPerSecond: 4),
        1,
      );
      expect(
        calculateSampleInterval(sourceFps: 30, targetChecksPerSecond: 0),
        1,
      );
      expect(
        calculateSampleInterval(sourceFps: -10, targetChecksPerSecond: 4),
        1,
      );
    });
  });
}
