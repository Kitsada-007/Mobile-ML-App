import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/screens/camera_inference_page.dart';

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
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        (call) async => 1,
      );

  final portraitSizes = <String, Size>{
    'จอเล็ก': const Size(360, 640),
    'จอมาตรฐาน': const Size(390, 844),
    'จอใหญ่': const Size(430, 932),
  };

  portraitSizes.forEach((label, size) {
    testWidgets('camera layout fills the viewport on $label', (tester) async {
      _useScreen(tester, size);

      await tester.pumpWidget(
        const MaterialApp(home: CameraInferencePage(initializeOnStart: false)),
      );
      await tester.pump();

      final preview = find.byKey(const Key('cameraPreviewCard'));
      final panel = find.byKey(const Key('cameraDetectionPanel'));

      expect(preview, findsOneWidget);
      expect(panel, findsOneWidget);
      // กล้องอยู่เหนือแผงผลเสมอ
      expect(
        tester.getBottomLeft(preview).dy,
        lessThan(tester.getTopLeft(panel).dy),
      );
      // กล้องต้องไม่กินเกินครึ่งค่อนจอ ไม่งั้นแผงผลจะถูกเบียดตกขอบ
      expect(tester.getSize(preview).height, lessThan(size.height * 0.6));
      // เนื้อหาต้องยืดเต็มจอ ไม่เหลือช่องว่างค้างด้านล่าง
      // และต้องไม่ล้นออกนอกจอจนต้องเลื่อนหาแผงผล
      expect(
        tester.getBottomLeft(panel).dy,
        greaterThan(size.height * 0.9),
      );
      expect(
        tester.getBottomLeft(panel).dy,
        lessThanOrEqualTo(size.height),
      );
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('camera layout places the panel beside the preview in landscape', (
    tester,
  ) async {
    final size = _useScreen(tester, const Size(844, 390));

    await tester.pumpWidget(
      const MaterialApp(home: CameraInferencePage(initializeOnStart: false)),
    );
    await tester.pump();

    final preview = find.byKey(const Key('cameraPreviewCard'));
    final panel = find.byKey(const Key('cameraDetectionPanel'));

    // แนวนอน: วางเคียงกัน (ไม่ใช่ซ้อนลงมา) จึงใช้ความสูงที่เตี้ยได้เต็ม
    expect(
      tester.getTopRight(preview).dx,
      lessThanOrEqualTo(tester.getTopLeft(panel).dx),
    );
    expect(tester.getSize(preview).height, greaterThan(size.height * 0.6));
    expect(find.byKey(const Key('cameraDetectionScrollView')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
