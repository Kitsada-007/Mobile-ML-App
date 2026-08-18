import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/core/services/inference/signal_interpreter.dart';
import 'package:trffic_ilght_app/shared/widgets/countdown_badge.dart';

// สีพื้น/สีตัวเลขของ badge ที่เรนเดอร์อยู่จริง (จาก AnimatedContainer/TextStyle)
(Color background, Color number) _renderedColors(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.descendant(
      of: find.byType(CountdownBadge),
      matching: find.byType(AnimatedContainer),
    ),
  );
  final decoration = container.decoration! as BoxDecoration;
  // AnimatedDefaultTextStyle ตัวแรกคือตัวเลขใหญ่ (fontSize 36)
  final numberStyle = tester
      .widgetList<AnimatedDefaultTextStyle>(
        find.descendant(
          of: find.byType(CountdownBadge),
          matching: find.byType(AnimatedDefaultTextStyle),
        ),
      )
      .first
      .style;
  return (decoration.color!, numberStyle.color!);
}

Future<void> _pumpBadge(
  WidgetTester tester, {
  required int? countdown,
  String? trafficLightClassName,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CountdownBadge(
          countdown: countdown,
          trafficLightClassName: trafficLightClassName,
        ),
      ),
    ),
  );
}

void main() {
  group('CountdownBadge.paletteFor', () {
    test('คลาสที่ไม่รู้จักหรือ null ได้ชุดสีกลางเดียวกัน (default ชัดเจน)', () {
      final unknown = CountdownBadge.paletteFor('some_future_class');
      final none = CountdownBadge.paletteFor(null);
      expect(unknown.background, none.background);
      expect(unknown.number, none.number);
    });
  });

  group('CountdownBadge widget', () {
    testWidgets('แสดงชุดสีเขียวเมื่อไฟเสถียรเป็น green_light_circle', (
      tester,
    ) async {
      await _pumpBadge(
        tester,
        countdown: 12,
        trafficLightClassName: TrafficSignalClasses.greenLightCircle,
      );

      final expected = CountdownBadge.paletteFor(
        TrafficSignalClasses.greenLightCircle,
      );
      final (background, number) = _renderedColors(tester);
      expect(background, expected.background);
      expect(number, expected.number);
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('แสดงชุดสีแดงเมื่อไฟเสถียรเป็น red_light_circle', (
      tester,
    ) async {
      await _pumpBadge(
        tester,
        countdown: 5,
        trafficLightClassName: TrafficSignalClasses.redLightCircle,
      );

      final expected = CountdownBadge.paletteFor(
        TrafficSignalClasses.redLightCircle,
      );
      final (background, number) = _renderedColors(tester);
      expect(background, expected.background);
      expect(number, expected.number);
    });

    testWidgets('ไม่มีไฟยืนยัน -> ใช้สีกลาง ไม่ใช่สีแดงแบบฮาร์ดโค้ดเดิม', (
      tester,
    ) async {
      await _pumpBadge(tester, countdown: 9);

      final expected = CountdownBadge.paletteFor(null);
      final (background, number) = _renderedColors(tester);
      expect(background, expected.background);
      expect(number, expected.number);
    });

    testWidgets('Semantics บอกสีไฟกำกับตัวเลขเสมอ (ไม่สื่อด้วยสีทางเดียว)', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpBadge(
        tester,
        countdown: 12,
        trafficLightClassName: TrafficSignalClasses.redLightCircle,
      );
      expect(
        tester.getSemantics(find.byType(CountdownBadge)),
        matchesSemantics(label: 'ไฟแดง ตัวเลขนับถอยหลัง 12 วินาที'),
      );

      // ไม่พบตัวเลข: ยังต้องอ่านสถานะออก
      await _pumpBadge(
        tester,
        countdown: null,
        trafficLightClassName: TrafficSignalClasses.greenLightCircle,
      );
      expect(
        tester.getSemantics(find.byType(CountdownBadge)),
        matchesSemantics(label: 'ไฟเขียว ไม่พบตัวเลขนับถอยหลัง'),
      );
      semantics.dispose();
    });
  });
}
