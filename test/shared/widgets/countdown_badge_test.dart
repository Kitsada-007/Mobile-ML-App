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
    test('ไฟกะพริบใช้ชุดสีเดียวกับไฟนิ่งสีนั้น และเปิด pulse', () {
      final red = CountdownBadge.paletteFor(
        TrafficSignalClasses.redLightCircle,
      );
      final flashingRed = CountdownBadge.paletteFor(
        TrafficSignalClasses.flashingRed,
      );
      expect(flashingRed.background, red.background);
      expect(flashingRed.number, red.number);
      expect(red.pulse, isFalse);
      expect(flashingRed.pulse, isTrue);

      final yellow = CountdownBadge.paletteFor(TrafficSignalClasses.yellowLight);
      final flashingYellow = CountdownBadge.paletteFor(
        TrafficSignalClasses.flashingYellow,
      );
      expect(flashingYellow.number, yellow.number);
      expect(flashingYellow.pulse, isTrue);
    });

    test('คลาสที่ไม่รู้จักหรือ null ได้ชุดสีกลางเดียวกัน (default ชัดเจน)', () {
      final unknown = CountdownBadge.paletteFor('some_future_class');
      final none = CountdownBadge.paletteFor(null);
      expect(unknown.background, none.background);
      expect(unknown.number, none.number);
      expect(unknown.pulse, isFalse);
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

    testWidgets('ไฟกะพริบ: กรอบเต้นเมื่อ animation ปกติ และนิ่งเมื่อปิด animation', (
      tester,
    ) async {
      await _pumpBadge(
        tester,
        countdown: null,
        trafficLightClassName: TrafficSignalClasses.flashingRed,
      );
      // เดินเวลาให้ pulse ขยับ — ต้องไม่ throw และกรอบเปลี่ยนจากค่าตั้งต้น
      await tester.pump(const Duration(milliseconds: 225));
      final container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final border =
          ((container.decoration! as BoxDecoration).border! as Border).top;
      expect(
        border.color,
        isNot(CountdownBadge.paletteFor(TrafficSignalClasses.flashingRed).border),
      );

      // ปิด animation ของระบบ -> กรอบต้องค้างที่สีเต็ม (ไม่เต้น)
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: CountdownBadge(
                countdown: null,
                trafficLightClassName: TrafficSignalClasses.flashingRed,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 225));
      final still = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final stillBorder =
          ((still.decoration! as BoxDecoration).border! as Border).top;
      expect(
        stillBorder.color,
        CountdownBadge.paletteFor(TrafficSignalClasses.flashingRed).border,
      );
    });
  });
}
