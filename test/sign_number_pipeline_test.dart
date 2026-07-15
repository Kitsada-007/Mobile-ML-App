import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/services/sign_number_pipeline_service.dart';

void main() {
  group('resolveCropBounds', () {
    test('maps normalized coordinates to padded pixel bounds', () {
      final bounds = resolveCropBounds(
        CropData(Uint8List(0), 0.25, 0.20, 0.75, 0.80),
        imageWidth: 200,
        imageHeight: 100,
      );

      expect(bounds.left, 35);
      expect(bounds.top, 11);
      expect(bounds.right, 165);
      expect(bounds.bottom, 89);
    });

    test('keeps pixel coordinates in the source image coordinate space', () {
      final bounds = resolveCropBounds(
        CropData(Uint8List(0), 50, 20, 150, 80),
        imageWidth: 200,
        imageHeight: 100,
      );

      expect(bounds.left, 35);
      expect(bounds.top, 11);
      expect(bounds.right, 165);
      expect(bounds.bottom, 89);
    });
  });
}
