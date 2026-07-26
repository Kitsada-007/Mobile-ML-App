// This is a basic Flutter widget test for trffic_ilght_app.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trffic_ilght_app/main.dart';
import 'package:trffic_ilght_app/presentation/controllers/settings_controller.dart';
import 'package:trffic_ilght_app/presentation/pages/camera_inference_page.dart';
import 'package:trffic_ilght_app/presentation/pages/setting_page.dart';
import 'package:trffic_ilght_app/presentation/pages/single_image_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App launches directly into the camera-first experience', (
    WidgetTester tester,
  ) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider(create: (_) => SettingsProvider())],
        child: const MyApp(initializeCamera: false),
      ),
    );

    // Re-render to let the future resolve and local storage values load
    await tester.pumpAndSettle();

    // The production home is the realtime camera, not a mode-selection screen.
    expect(find.byType(CameraInferencePage), findsOneWidget);
    expect(find.text('Berng Fai'), findsWidgets);
    expect(find.text('เลือกโหมดการตรวจจับ'), findsNothing);
  });

  testWidgets(
    'opens Settings from the drawer without a bottom navigation bar',
    (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ],
          child: const MyApp(initializeCamera: false),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final rootScaffold = tester.widget<Scaffold>(
        find.byWidgetPredicate(
          (widget) => widget is Scaffold && widget.drawer != null,
        ),
      );
      expect(rootScaffold.bottomNavigationBar, isNull);

      await tester.tap(find.byTooltip('เปิดเมนู'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Settings'), findsOneWidget);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opens Single Image Test only from the drawer', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider(create: (_) => SettingsProvider())],
        child: const MyApp(initializeCamera: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ทดสอบรูปภาพ'), findsNothing);

    await tester.tap(find.byTooltip('เปิดเมนู'));
    await tester.pumpAndSettle();
    expect(find.text('Single Image Test'), findsOneWidget);

    await tester.tap(find.text('Single Image Test'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(SingleImageScreen), findsOneWidget);
  });

  test(
    'SettingsProvider resetThresholds resets thresholds to default values',
    () async {
      final provider = SettingsProvider();

      // Set non-default values
      await provider.setIouThreshold(0.8);
      await provider.setConfidenceThreshold(0.7);
      await provider.setNumItemsThreshold(25);

      expect(provider.iouThreshold, 0.8);
      expect(provider.confidenceThreshold, 0.7);
      expect(provider.numItemsThreshold, 25);

      // Reset values
      await provider.resetThresholds();

      expect(provider.iouThreshold, 0.45);
      expect(provider.confidenceThreshold, 0.5);
      expect(provider.numItemsThreshold, 11);
    },
  );
}
