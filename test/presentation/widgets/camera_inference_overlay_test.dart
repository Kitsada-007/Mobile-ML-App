import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/presentation/controllers/camera_inference_controller.dart';
import 'package:trffic_ilght_app/presentation/widgets/camera_widgets/camera_detection_panel.dart';
import 'package:trffic_ilght_app/presentation/widgets/camera_widgets/camera_inference_content.dart';
import 'package:trffic_ilght_app/presentation/widgets/camera_widgets/camera_inference_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        (call) async => 1,
      );

  testWidgets('camera content shows a user-friendly preparing state', (
    tester,
  ) async {
    final controller = CameraInferenceController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CameraInferenceContent(controller: controller)),
      ),
    );

    expect(find.text('กำลังเตรียมระบบตรวจจับ'), findsOneWidget);
    expect(find.text('No model path available'), findsNothing);
  });

  testWidgets(
    'camera HUD shows branding, live state, and an overlay back button',
    (tester) async {
      var didGoBack = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                CameraInferenceOverlay(
                  detectionCount: 2,
                  currentFps: 15.5,
                  isLandscape: false,
                  onLeadingPressed: () => didGoBack = true,
                ),
              ],
            ),
          ),
        ),
      );

      final hud = tester.widget<DecoratedBox>(
        find.byKey(const Key('cameraStatusHud')),
      );
      final decoration = hud.decoration as BoxDecoration;
      expect(decoration.color, Colors.black.withValues(alpha: 0.7));
      expect(find.text('DETECTIONS: 2'), findsOneWidget);
      expect(find.text('FPS: 15.5'), findsOneWidget);
      expect(find.text('Berng Fai'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);

      await tester.tap(find.byTooltip('ย้อนกลับ'));
      expect(didGoBack, isTrue);

      expect(find.byTooltip('สลับกล้อง'), findsNothing);
    },
  );

  testWidgets('camera HUD can expose the app drawer menu action', (
    tester,
  ) async {
    var didOpenMenu = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              CameraInferenceOverlay(
                detectionCount: 0,
                currentFps: 0,
                isLandscape: false,
                showMenuButton: true,
                onLeadingPressed: () => didOpenMenu = true,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('เปิดเมนู'));
    expect(didOpenMenu, isTrue);
  });

  testWidgets('detection panel uses a responsive translucent black surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              CameraDetectionPanel(
                formalNames: [],
                alertMessages: [],
                detectedNumber: null,
                isLandscape: false,
              ),
            ],
          ),
        ),
      ),
    );

    final panel = tester.widget<DecoratedBox>(
      find.byKey(const Key('cameraDetectionPanel')),
    );
    final decoration = panel.decoration as BoxDecoration;
    expect(decoration.color, Colors.black.withValues(alpha: 0.7));
    expect(
      find.byKey(const Key('cameraDetectionPanelPosition')),
      findsOneWidget,
    );
    expect(find.text('LIVE DETECTION'), findsOneWidget);
    expect(find.text('กำลังสแกนหาป้ายจราจรและสัญญาณไฟ...'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detection panel shows traffic-light countdown in seconds', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              CameraDetectionPanel(
                formalNames: ['สัญญาณไฟนับถอยหลัง'],
                alertMessages: ['พบสัญญาณไฟนับถอยหลัง'],
                detectedNumber: '12',
                isLandscape: false,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('สัญญาณไฟนับถอยหลัง 12 วินาที'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.textContaining('ป้ายจำกัดความเร็ว'), findsNothing);
    expect(find.textContaining('กม./ชม.'), findsNothing);
  });

  testWidgets('countdown from three displays get-ready message', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              CameraDetectionPanel(
                formalNames: ['สัญญาณไฟนับถอยหลัง'],
                alertMessages: ['พบสัญญาณไฟนับถอยหลัง'],
                detectedNumber: '3',
                isLandscape: false,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('เตรียมตัวไป'), findsOneWidget);
  });

  testWidgets('countdown from five displays get-ready message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              CameraDetectionPanel(
                formalNames: ['สัญญาณไฟนับถอยหลัง'],
                alertMessages: ['พบสัญญาณไฟนับถอยหลัง'],
                detectedNumber: '5',
                isLandscape: false,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('เตรียมตัวไป'), findsOneWidget);
  });
}
