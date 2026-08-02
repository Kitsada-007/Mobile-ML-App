import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/core/services/inference/countdown_reading_stabilizer.dart';

void main() {
  test('requires two matching frames before accepting a countdown', () {
    final stabilizer = CountdownReadingStabilizer(requiredMatches: 2);

    expect(stabilizer.add('12'), isNull);
    expect(stabilizer.add('12'), '12');
  });

  test('rejects a countdown that jumps upward after stabilization', () {
    final stabilizer = CountdownReadingStabilizer(requiredMatches: 2);

    stabilizer
      ..add('12')
      ..add('12');

    expect(stabilizer.add('17'), isNull);
    expect(stabilizer.add('17'), isNull);
    expect(stabilizer.acceptedReading, '12');
  });

  test(
    'accepts a monotonic countdown transition immediately without delay',
    () {
      final stabilizer = CountdownReadingStabilizer(requiredMatches: 2);

      stabilizer
        ..add('12')
        ..add('12');

      expect(stabilizer.add('11'), '11');
    },
  );

  test('requires extra evidence before resynchronizing after a large drop', () {
    final stabilizer = CountdownReadingStabilizer(requiredMatches: 2);

    stabilizer
      ..add('12')
      ..add('12');

    expect(stabilizer.add('8'), isNull);
    expect(stabilizer.add('8'), isNull);
    expect(stabilizer.add('8'), '8');
  });

  test('recovers from an incorrect initial low reading after four frames', () {
    final stabilizer = CountdownReadingStabilizer(requiredMatches: 2);

    stabilizer
      ..add('3')
      ..add('3');

    expect(stabilizer.add('12'), isNull);
    expect(stabilizer.add('12'), isNull);
    expect(stabilizer.add('12'), isNull);
    expect(stabilizer.add('12'), '12');
  });

  test('rejects malformed and out-of-range readings', () {
    final stabilizer = CountdownReadingStabilizer(requiredMatches: 2);

    expect(stabilizer.add('abc'), isNull);
    expect(stabilizer.add('100'), isNull);
    expect(stabilizer.add('-1'), isNull);
  });

  test('reset allows a new traffic-light countdown cycle', () {
    final stabilizer = CountdownReadingStabilizer(requiredMatches: 2);

    stabilizer
      ..add('3')
      ..add('3')
      ..reset();

    expect(stabilizer.add('20'), isNull);
    expect(stabilizer.add('20'), '20');
  });
}
