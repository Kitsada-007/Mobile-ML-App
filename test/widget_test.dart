// This is a basic Flutter widget test for trffic_ilght_app.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trffic_ilght_app/main.dart';
import 'package:trffic_ilght_app/presentation/controllers/settings_controller.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App launches and shows Traffic Light AI title', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: const MyApp(),
      ),
    );

    // Re-render to let the future resolve and local storage values load
    await tester.pumpAndSettle();

    // Verify that our app starts and displays key elements.
    expect(find.text('Traffic Light AI'), findsOneWidget);
    expect(find.text('เลือกโหมดการตรวจจับ'), findsOneWidget);
  });

  testWidgets('Settings page renders without hidden ListTile material effects', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  test('SettingsProvider resetThresholds resets thresholds to default values', () async {
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
  });
}
