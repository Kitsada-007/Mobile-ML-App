import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/services/yolo_result_adapter.dart';

Map<String, dynamic> detection({
  required String className,
  required double left,
  double confidence = 0.9,
}) {
  return {
    'classIndex': 0,
    'className': className,
    'confidence': confidence,
    'boundingBox': {
      'left': left * 100,
      'top': 10.0,
      'right': (left * 100) + 20,
      'bottom': 40.0,
    },
    'normalizedBox': {
      'left': left,
      'top': 0.1,
      'right': left + 0.2,
      'bottom': 0.4,
    },
  };
}

void main() {
  group('parseYoloDetections', () {
    test('converts native detection maps into typed results', () {
      final results = parseYoloDetections([
        detection(className: 'red_light_circle', left: 0.2),
      ]);

      expect(results, hasLength(1));
      expect(results.single.className, 'red_light_circle');
      expect(results.single.confidence, 0.9);
      expect(results.single.normalizedBox.left, 0.2);
    });

    test('ignores malformed entries at the platform boundary', () {
      final results = parseYoloDetections([
        null,
        'not-a-map',
        {'className': 'missing-required-values'},
        detection(className: 'green_light_circle', left: 0.4),
      ]);

      expect(results, hasLength(1));
      expect(results.single.className, 'green_light_circle');
    });
  });

  group('readDigitSequence', () {
    test('sorts digits left to right and limits the result length', () {
      final results = parseYoloDetections([
        detection(className: '5', left: 0.6),
        detection(className: '1', left: 0.1),
        detection(className: '8', left: 0.8),
      ]);

      expect(readDigitSequence(results, maxDigits: 2), '15');
    });

    test('keeps every digit when no limit is requested', () {
      final results = parseYoloDetections([
        detection(className: '5', left: 0.6),
        detection(className: '1', left: 0.1),
        detection(className: '8', left: 0.8),
      ]);

      expect(readDigitSequence(results), '158');
    });

    test('ignores non-digit detections', () {
      final results = parseYoloDetections([
        detection(className: 'sign_number', left: 0.1),
      ]);

      expect(readDigitSequence(results), isNull);
    });
  });
}
