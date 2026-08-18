import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/core/utils/thai_number_helper.dart';

void main() {
  group('Countdown get-ready threshold', () {
    test('starts the get-ready alert at five seconds', () {
      expect(shouldPrepareToGo(5), isTrue);
      expect(shouldPrepareToGo(1), isTrue);
    });

    test('continues announcing the number above five seconds', () {
      expect(shouldPrepareToGo(6), isFalse);
      expect(shouldPrepareToGo(20), isFalse);
    });
  });
}
