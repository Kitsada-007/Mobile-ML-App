import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:trffic_ilght_app/shared/utils/optional_provider.dart';

class _Counter {
  const _Counter(this.value);
  final int value;
}

void main() {
  testWidgets('คืนค่า provider ที่มีอยู่จริง', (tester) async {
    _Counter? found;

    await tester.pumpWidget(
      Provider<_Counter>.value(
        value: const _Counter(7),
        child: Builder(
          builder: (context) {
            found = readOptionalProvider<_Counter>(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(found?.value, 7);
  });

  testWidgets('ไม่มี provider ครอบก็ต้องคืน null ไม่ใช่โยน exception', (
    tester,
  ) async {
    _Counter? found = const _Counter(1);

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          found = readOptionalProvider<_Counter>(context);
          return const SizedBox();
        },
      ),
    );

    expect(found, isNull);
    expect(tester.takeException(), isNull);
  });
}
