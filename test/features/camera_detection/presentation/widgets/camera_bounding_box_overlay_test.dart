import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/widgets/video_bounding_box_overlay.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

void main() {
  testWidgets('renders CustomPaint with bounding boxes', (tester) async {
    final detections = [
      YOLOResult.fromMap({
        'classIndex': 0,
        'className': 'red_light_circle',
        'confidence': 0.9,
        'boundingBox': {
          'left': 10.0,
          'top': 10.0,
          'right': 50.0,
          'bottom': 50.0,
        },
        'normalizedBox': {'left': 0.1, 'top': 0.1, 'right': 0.5, 'bottom': 0.5},
      }),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: VideoBoundingBoxOverlay(
              detections: detections,
              videoSize: const Size(640, 480),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(VideoBoundingBoxOverlay), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(VideoBoundingBoxOverlay),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
  });
}
