import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/controllers/camera_inference_controller.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/screens/camera_inference_page.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/widgets/camera_detection_panel.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/widgets/camera_inference_content.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/widgets/camera_inference_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        (call) async => 1,
      );

  testWidgets('camera preview is bounded above the detection output', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(home: CameraInferencePage(initializeOnStart: false)),
    );
    await tester.pump();

    final preview = find.byKey(const Key('cameraPreviewCard'));
    final output = find.byKey(const Key('cameraDetectionPanel'));

    expect(find.byKey(const Key('fullscreenCameraStack')), findsNothing);
    expect(find.byKey(const Key('cameraDetectionScrollView')), findsOneWidget);
    expect(find.text('ระบบตรวจจับไฟจราจร'), findsOneWidget);
    expect(preview, findsOneWidget);
    expect(output, findsOneWidget);
    expect(
      tester.getBottomLeft(preview).dy,
      lessThan(tester.getTopLeft(output).dy),
    );
    expect(tester.getSize(preview).height, lessThan(844 * 0.6));
    expect(tester.takeException(), isNull);
  });

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

  test('camera analysis preserves detail for small countdown digits', () {
    expect(cameraAnalysisResolution, const Size(1280, 960));
    expect(cameraInferenceFrequency, 15);
    expect(cameraResultMaxFps, 10);
  });

  testWidgets('camera header shows the page title and back action', (
    tester,
  ) async {
    var didGoBack = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraInferenceOverlay(
            onLeadingPressed: () => didGoBack = true,
          ),
        ),
      ),
    );

    expect(find.text('ระบบตรวจจับไฟจราจร'), findsOneWidget);
    expect(find.text('Traffic Light Detection'), findsOneWidget);
    expect(find.text('Berng Fai'), findsOneWidget);

    await tester.tap(find.byTooltip('ย้อนกลับ'));
    expect(didGoBack, isTrue);

    expect(find.byTooltip('สลับกล้อง'), findsNothing);
  });

  testWidgets('camera HUD can expose the app drawer menu action', (
    tester,
  ) async {
    var didOpenMenu = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraInferenceOverlay(
            showMenuButton: true,
            onLeadingPressed: () => didOpenMenu = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('เปิดเมนู'));
    expect(didOpenMenu, isTrue);
  });

  testWidgets('detection output uses a standalone light result card', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: CameraDetectionPanel(
              formalNames: [],
              alertMessages: [],
              detectedNumber: null,
              isLandscape: false,
            ),
          ),
        ),
      ),
    );

    final panel = tester.widget<DecoratedBox>(
      find.byKey(const Key('cameraDetectionPanel')),
    );
    final decoration = panel.decoration as BoxDecoration;
    expect(decoration.color, Colors.white);
    expect(find.byKey(const Key('cameraDetectionPanelPosition')), findsNothing);
    expect(find.text('ผลการตรวจจับ'), findsOneWidget);
    expect(find.text('กำลังสแกนหาป้ายจราจรและสัญญาณไฟ...'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detection panel reports realtime pipeline health', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CameraDetectionPanel(
            formalNames: [],
            alertMessages: [],
            detectedNumber: null,
            isLandscape: false,
            isPipelineStale: false,
            latencyP50: Duration(milliseconds: 42),
            latencyP95: Duration(milliseconds: 88),
            latencyP99: Duration(milliseconds: 120),
            droppedFrameCount: 3,
            trackingId: 7,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('realtimePipelineStatus')), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('P50 42 ms'), findsOneWidget);
    expect(find.text('P95 88 ms'), findsOneWidget);
    expect(find.text('P99 120 ms'), findsOneWidget);
    expect(find.text('DROP 3'), findsOneWidget);
    expect(find.text('TRACK #7'), findsOneWidget);
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
