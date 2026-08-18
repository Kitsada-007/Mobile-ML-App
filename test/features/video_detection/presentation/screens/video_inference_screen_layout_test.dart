import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/screens/video_inference_screen.dart';

/// ตั้งขนาดจอจำลอง แล้วคืนขนาดเป็น logical pixel
Size _useScreen(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  return size;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final portraitSizes = <String, Size>{
    'จอเล็ก': const Size(360, 640),
    'จอมาตรฐาน': const Size(390, 844),
    'จอใหญ่': const Size(430, 932),
  };

  portraitSizes.forEach((label, size) {
    testWidgets('video layout fills the viewport on $label', (tester) async {
      _useScreen(tester, size);

      await tester.pumpWidget(const MaterialApp(home: VideoInferenceScreen()));
      await tester.pump();

      final panel = find.byKey(const Key('videoDetectionPanel'));
      final placeholder = find.text('ตรวจจับจากไฟล์วิดีโอ');

      expect(panel, findsOneWidget);
      expect(placeholder, findsOneWidget);
      // การ์ดเลือกวิดีโออยู่เหนือแผงผลเสมอ
      expect(
        tester.getBottomLeft(placeholder).dy,
        lessThan(tester.getTopLeft(panel).dy),
      );
      // เนื้อหายืดเต็มจอ และยังอยู่ในจอ (ไม่ต้องเลื่อนหาแผงผล)
      expect(tester.getBottomLeft(panel).dy, greaterThan(size.height * 0.9));
      expect(tester.getBottomLeft(panel).dy, lessThanOrEqualTo(size.height));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('video layout places the panel beside the card in landscape', (
    tester,
  ) async {
    final size = _useScreen(tester, const Size(844, 390));

    await tester.pumpWidget(const MaterialApp(home: VideoInferenceScreen()));
    await tester.pump();

    final panel = find.byKey(const Key('videoDetectionPanel'));
    final placeholder = find.text('ตรวจจับจากไฟล์วิดีโอ');

    expect(
      tester.getTopRight(placeholder).dx,
      lessThanOrEqualTo(tester.getTopLeft(panel).dx),
    );
    expect(tester.getBottomLeft(panel).dy, lessThanOrEqualTo(size.height));
    expect(find.byKey(const Key('videoDetectionScrollView')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
