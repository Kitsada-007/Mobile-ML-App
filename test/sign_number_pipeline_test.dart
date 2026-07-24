import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:trffic_ilght_app/services/sign_number_pipeline_service.dart';

void main() {
  group('resolveCropBounds', () {
    test(
      'keeps extra horizontal context so the leading digit is not clipped',
      () {
        final bounds = resolveCropBounds(
          CropData(Uint8List(0), 0.25, 0.20, 0.75, 0.80),
          imageWidth: 200,
          imageHeight: 100,
        );

        expect(bounds.left, 20);
        expect(bounds.right, 180);
      },
    );

    test('maps normalized coordinates to padded pixel bounds', () {
      final bounds = resolveCropBounds(
        CropData(Uint8List(0), 0.25, 0.20, 0.75, 0.80),
        imageWidth: 200,
        imageHeight: 100,
      );

      expect(bounds.left, 20);
      expect(bounds.top, 11);
      expect(bounds.right, 180);
      expect(bounds.bottom, 89);
    });

    test('keeps pixel coordinates in the source image coordinate space', () {
      final bounds = resolveCropBounds(
        CropData(Uint8List(0), 50, 20, 150, 80),
        imageWidth: 200,
        imageHeight: 100,
      );

      expect(bounds.left, 20);
      expect(bounds.top, 11);
      expect(bounds.right, 180);
      expect(bounds.bottom, 89);
    });
  });

  test('preprocessing preserves color information', () {
    final source = img.Image(width: 8, height: 8);
    img.fill(source, color: img.ColorRgb8(220, 30, 20));

    final processedBytes = processSignCrop(
      CropData(Uint8List.fromList(img.encodePng(source)), 0, 0, 8, 8),
    );

    expect(processedBytes, isNotNull);
    final processed = img.decodeImage(processedBytes!);
    expect(processed, isNotNull);

    final centerPixel = processed!.getPixel(
      processed.width ~/ 2,
      processed.height ~/ 2,
    );
    expect((centerPixel.r - centerPixel.g).abs(), greaterThan(50));
  });

  test('preprocessing preserves the crop aspect ratio', () {
    final source = img.Image(width: 20, height: 10);
    img.fill(source, color: img.ColorRgb8(220, 30, 20));

    final processedBytes = processSignCrop(
      CropData(Uint8List.fromList(img.encodePng(source)), 0, 0, 20, 10),
    );

    final processed = img.decodeImage(processedBytes!);
    expect(processed!.width / processed.height, closeTo(2, 0.05));
  });
}
