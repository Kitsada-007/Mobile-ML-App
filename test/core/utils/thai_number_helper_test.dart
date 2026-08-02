import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/core/utils/thai_number_helper.dart';

void main() {
  group('Thai Number Conversion Tests', () {
    test('Single digits', () {
      expect(convertToThaiWords(0), 'ศูนย์');
      expect(convertToThaiWords(1), 'หนึ่ง');
      expect(convertToThaiWords(5), 'ห้า');
      expect(convertToThaiWords(9), 'เก้า');
    });

    test('Teens (10-19)', () {
      expect(convertToThaiWords(10), 'สิบ');
      expect(convertToThaiWords(11), 'สิบเอ็ด');
      expect(convertToThaiWords(12), 'สิบสอง');
      expect(convertToThaiWords(19), 'สิบเก้า');
    });

    test('Tens (20-99)', () {
      expect(convertToThaiWords(20), 'ยี่สิบ');
      expect(convertToThaiWords(21), 'ยี่สิบเอ็ด');
      expect(convertToThaiWords(25), 'ยี่สิบห้า');
      expect(convertToThaiWords(30), 'สามสิบ');
      expect(convertToThaiWords(50), 'ห้าสิบ');
      expect(convertToThaiWords(80), 'แปดสิบ');
      expect(convertToThaiWords(99), 'เก้าสิบเก้า');
    });
  });

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
