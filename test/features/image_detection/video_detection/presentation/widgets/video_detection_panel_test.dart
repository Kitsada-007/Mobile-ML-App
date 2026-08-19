import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/widgets/video_detection_panel.dart';

void main() {
  testWidgets('renders VideoDetectionPanel with header and content', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VideoDetectionPanel(
            formalNames: ['สัญญาณไฟแดง'],
            alertMessages: ['สัญญาณไฟแดง (หยุด)'],
            detectedNumber: '15',
            isLandscape: false,
            statusText: 'กำลังตรวจจับวิดีโอ',
          ),
        ),
      ),
    );

    expect(find.byType(VideoDetectionPanel), findsOneWidget);
    expect(find.text('ผลการตรวจจับวิดีโอ'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
  });

  testWidgets(
    'renders countdown badge and traffic signal message when countdown > 5',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VideoDetectionPanel(
              formalNames: ['สัญญาณไฟนับถอยหลัง'],
              alertMessages: ['พบสัญญาณไฟนับถอยหลัง'],
              detectedNumber: '12',
              isLandscape: false,
              statusText: 'กำลังตรวจจับวิดีโอ',
            ),
          ),
        ),
      );

      // Position 1: Badge countdown number
      expect(find.text('12'), findsOneWidget);
      // Position 2: Countdown message is NOT displayed in Position 2 when countdown > 5
      expect(find.text('พบสัญญาณไฟนับถอยหลัง'), findsNothing);
    },
  );

  testWidgets('renders prepare to go message when countdown <= 5', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VideoDetectionPanel(
            formalNames: ['สัญญาณไฟนับถอยหลัง'],
            alertMessages: ['พบสัญญาณไฟนับถอยหลัง'],
            detectedNumber: '3',
            isLandscape: false,
            statusText: 'กำลังตรวจจับวิดีโอ',
          ),
        ),
      ),
    );

    // Position 1: Badge countdown number
    expect(find.text('3'), findsOneWidget);
    // Position 2: Prepare to go message
    expect(find.text('เตรียมตัวไป'), findsOneWidget);
  });

  testWidgets(
    'renders scanning message gracefully when detectedNumber is null or invalid',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VideoDetectionPanel(
              formalNames: ['สัญญาณไฟนับถอยหลัง'],
              alertMessages: ['พบสัญญาณไฟนับถอยหลัง'],
              detectedNumber: null,
              isLandscape: false,
              statusText: 'กำลังตรวจจับวิดีโอ',
            ),
          ),
        ),
      );

      // Position 1: Shows X when countdown is null
      expect(find.text('X'), findsOneWidget);
      // Position 2: Countdown message suppressed, displays scanning message if no other class
      expect(
        find.text('กำลังตรวจจับป้ายจราจรและสัญญาณไฟในวิดีโอ...'),
        findsOneWidget,
      );
    },
  );
}
