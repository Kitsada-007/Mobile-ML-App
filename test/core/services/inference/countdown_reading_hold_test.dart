import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/core/services/inference/countdown_reading_hold.dart';

void main() {
  final start = DateTime(2026);

  test('คืนเลขที่เพิ่งอ่านได้ทันที', () {
    final hold = CountdownReadingHold();

    expect(hold.update('12', timestamp: start), '12');
    expect(hold.reading, '12');
  });

  test('คงเลขเดิมไว้ระหว่างที่ยังอ่านไม่ได้ (กันเลขกะพริบหาย)', () {
    final hold = CountdownReadingHold(
      holdDuration: const Duration(milliseconds: 1500),
    );
    hold.update('12', timestamp: start);

    expect(
      hold.update(
        null,
        timestamp: start.add(const Duration(milliseconds: 400)),
      ),
      '12',
    );
    expect(
      hold.update(
        null,
        timestamp: start.add(const Duration(milliseconds: 1500)),
      ),
      '12',
    );
  });

  test('ปล่อยเลขทิ้งเมื่อพ้นเวลาที่ถือไว้ (กันเลขเก่าค้างบนจอ)', () {
    final hold = CountdownReadingHold(
      holdDuration: const Duration(milliseconds: 1500),
    );
    hold.update('12', timestamp: start);

    expect(
      hold.update(
        null,
        timestamp: start.add(const Duration(milliseconds: 1501)),
      ),
      isNull,
    );
    expect(hold.reading, isNull);
  });

  test('เลขใหม่ต่ออายุการถือใหม่ทุกครั้ง', () {
    final hold = CountdownReadingHold(
      holdDuration: const Duration(milliseconds: 1000),
    );
    hold.update('12', timestamp: start);
    hold.update('11', timestamp: start.add(const Duration(milliseconds: 900)));

    expect(
      hold.update(
        null,
        timestamp: start.add(const Duration(milliseconds: 1800)),
      ),
      '11',
    );
  });

  test('reset ล้างเลขที่ถืออยู่', () {
    final hold = CountdownReadingHold();
    hold.update('9', timestamp: start);
    hold.reset();

    expect(hold.reading, isNull);
    expect(
      hold.update(null, timestamp: start.add(const Duration(seconds: 1))),
      isNull,
    );
  });
}
