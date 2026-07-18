import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/core/models/semantic_version.dart';

void main() {
  group('SemanticVersion', () {
    test('orders multi-digit minor versions numerically', () {
      final newer = SemanticVersion.parse('1.10.0');
      final older = SemanticVersion.parse('1.9.0');

      expect(newer.compareTo(older), greaterThan(0));
    });

    test('orders major, minor, and patch components', () {
      expect(
        SemanticVersion.parse('2.0.0'),
        greaterThan(SemanticVersion.parse('1.99.99')),
      );
      expect(
        SemanticVersion.parse('1.2.1'),
        greaterThan(SemanticVersion.parse('1.2.0')),
      );
    });

    test('rejects versions outside major.minor.patch format', () {
      expect(() => SemanticVersion.parse('v1.2.0'), throwsFormatException);
      expect(() => SemanticVersion.parse('1.2'), throwsFormatException);
      expect(() => SemanticVersion.parse('1.02.0'), throwsFormatException);
    });

    test('preserves the normalized version string', () {
      expect(SemanticVersion.parse('10.20.30').toString(), '10.20.30');
    });
  });
}
