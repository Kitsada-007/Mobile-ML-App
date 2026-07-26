import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:trffic_ilght_app/services/yolo_result_adapter.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

const double digitConfidenceThreshold = 0.10;
const double digitIouThreshold = 0.45;
const int minimumDigitCropEdge = 128;
const int maximumDigitCropEdge = 640;
const double tightHorizontalPaddingFactor = 0.15;
const double tightVerticalPaddingFactor = 0.10;
const double wideHorizontalPaddingFactor = 0.30;
const double wideVerticalPaddingFactor = 0.15;

class CropData {
  final Uint8List imageBytes;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double horizontalPaddingFactor;
  final double verticalPaddingFactor;

  CropData(
    this.imageBytes,
    this.left,
    this.top,
    this.right,
    this.bottom, {
    this.horizontalPaddingFactor = tightHorizontalPaddingFactor,
    this.verticalPaddingFactor = tightVerticalPaddingFactor,
  });
}

typedef CropBounds = ({int left, int top, int right, int bottom});

class SignNumberAnalysis {
  final Uint8List? cropBytes;
  final String? number;
  final YOLOResult? selectedSign;

  const SignNumberAnalysis({this.cropBytes, this.number, this.selectedSign});
}

CropBounds resolveCropBounds(
  CropData data, {
  required int imageWidth,
  required int imageHeight,
}) {
  double x1 = data.left;
  double y1 = data.top;
  double x2 = data.right;
  double y2 = data.bottom;

  final bool isNormalized =
      x1 >= -0.01 && y1 >= -0.01 && x2 <= 1.01 && y2 <= 1.01;

  if (isNormalized) {
    x1 *= imageWidth;
    y1 *= imageHeight;
    x2 *= imageWidth;
    y2 *= imageHeight;
  }

  final int left = x1.floor().clamp(0, imageWidth - 1);
  final int top = y1.floor().clamp(0, imageHeight - 1);
  final int right = x2.ceil().clamp(left + 1, imageWidth);
  final int bottom = y2.ceil().clamp(top + 1, imageHeight);

  return (left: left, top: top, right: right, bottom: bottom);
}

@visibleForTesting
CropBounds expandCropBounds(
  CropBounds bounds, {
  required int imageWidth,
  required int imageHeight,
  required double horizontalPaddingFactor,
  required double verticalPaddingFactor,
}) {
  final int cropWidth = bounds.right - bounds.left;
  final int cropHeight = bounds.bottom - bounds.top;
  final int paddingX = max(2, (cropWidth * horizontalPaddingFactor).round());
  final int paddingY = max(2, (cropHeight * verticalPaddingFactor).round());

  return (
    left: max(0, bounds.left - paddingX),
    top: max(0, bounds.top - paddingY),
    right: min(imageWidth, bounds.right + paddingX),
    bottom: min(imageHeight, bounds.bottom + paddingY),
  );
}

@visibleForTesting
Uint8List? processSignCrop(CropData data) {
  try {
    final decoded = img.decodeImage(data.imageBytes);
    if (decoded == null) return null;

    final original = img.bakeOrientation(decoded);

    final int imageWidth = original.width;
    final int imageHeight = original.height;

    final bounds = resolveCropBounds(
      data,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );

    final int cropWidth = bounds.right - bounds.left;
    final int cropHeight = bounds.bottom - bounds.top;

    if (cropWidth <= 0 || cropHeight <= 0) {
      debugPrint('Crop ไม่ถูกต้อง');
      return null;
    }

    final paddedBounds = expandCropBounds(
      bounds,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      horizontalPaddingFactor: data.horizontalPaddingFactor,
      verticalPaddingFactor: data.verticalPaddingFactor,
    );

    img.Image cropped = img.copyCrop(
      original,
      x: paddedBounds.left,
      y: paddedBounds.top,
      width: paddedBounds.right - paddedBounds.left,
      height: paddedBounds.bottom - paddedBounds.top,
    );

    final int shortestEdge = min(cropped.width, cropped.height);
    final int longestEdge = max(cropped.width, cropped.height);
    double scale = shortestEdge < minimumDigitCropEdge
        ? minimumDigitCropEdge / shortestEdge
        : 1;

    if (longestEdge * scale > maximumDigitCropEdge) {
      scale = maximumDigitCropEdge / longestEdge;
    }

    if ((scale - 1).abs() > 0.001) {
      cropped = img.copyResize(
        cropped,
        width: max(1, (cropped.width * scale).round()),
        height: max(1, (cropped.height * scale).round()),
        interpolation: img.Interpolation.linear,
      );
    }

    // Number model was trained with grayscale images. Keep three output
    // channels so the encoded image remains compatible with YOLO input.
    cropped = img.grayscale(cropped);

    debugPrint('Crop พร้อมตรวจเลข: ${cropped.width}x${cropped.height}');

    return Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
  } catch (e, stackTrace) {
    debugPrint('Isolate Crop Error: $e');
    debugPrint('$stackTrace');
    return null;
  }
}

class SignNumberPipelineService {
  final YOLO digitYolo;

  SignNumberPipelineService({required this.digitYolo});

  Future<String?> detectNumberFromFrame({required Uint8List frameBytes}) =>
      _detectNumber(frameBytes);

  Future<String?> detectNumberFromSign({
    required Uint8List frameBytes,
    required List<YOLOResult> detectionResults,
  }) async {
    final analysis = await analyzeSingleImage(
      frameBytes: frameBytes,
      detectionResults: detectionResults,
    );
    return analysis.number;
  }

  Future<SignNumberAnalysis> analyzeSingleImage({
    required Uint8List frameBytes,
    required List<YOLOResult> detectionResults,
  }) async {
    final signResults = detectionResults
        .where((result) => result.className == 'sign_number')
        .toList();

    if (signResults.isEmpty) {
      debugPrint('ไม่พบคลาส sign_number');
      return const SignNumberAnalysis();
    }

    signResults.sort((a, b) => b.confidence.compareTo(a.confidence));

    final sign = signResults.first;
    final normalizedRect = sign.normalizedBox;

    final bool normalizedIsValid =
        normalizedRect.left >= 0 &&
        normalizedRect.top >= 0 &&
        normalizedRect.right > normalizedRect.left &&
        normalizedRect.bottom > normalizedRect.top &&
        normalizedRect.right <= 1.01 &&
        normalizedRect.bottom <= 1.01;

    final rect = normalizedIsValid ? normalizedRect : sign.boundingBox;

    debugPrint('Normalized box: ${sign.normalizedBox}');
    debugPrint('Bounding box: ${sign.boundingBox}');
    debugPrint('Selected crop box: $rect');

    final tightCandidate = await _analyzeCrop(
      frameBytes: frameBytes,
      rect: rect,
      horizontalPaddingFactor: tightHorizontalPaddingFactor,
      verticalPaddingFactor: tightVerticalPaddingFactor,
    );

    if (tightCandidate.reading.digitCount >= 2) {
      return SignNumberAnalysis(
        cropBytes: tightCandidate.cropBytes,
        number: tightCandidate.reading.number,
        selectedSign: sign,
      );
    }

    final wideCandidate = await _analyzeCrop(
      frameBytes: frameBytes,
      rect: rect,
      horizontalPaddingFactor: wideHorizontalPaddingFactor,
      verticalPaddingFactor: wideVerticalPaddingFactor,
    );
    final selectedCandidate = _preferDigitCandidate(
      tightCandidate,
      wideCandidate,
    );

    return SignNumberAnalysis(
      cropBytes: selectedCandidate.cropBytes,
      number: selectedCandidate.reading.number,
      selectedSign: sign,
    );
  }

  Future<_DigitCandidate> _analyzeCrop({
    required Uint8List frameBytes,
    required Rect rect,
    required double horizontalPaddingFactor,
    required double verticalPaddingFactor,
  }) async {
    final cropData = CropData(
      frameBytes,
      rect.left,
      rect.top,
      rect.right,
      rect.bottom,
      horizontalPaddingFactor: horizontalPaddingFactor,
      verticalPaddingFactor: verticalPaddingFactor,
    );
    final processedBytes = await compute(processSignCrop, cropData);

    if (processedBytes == null) {
      debugPrint('สร้างภาพ crop ไม่สำเร็จ');
      return const _DigitCandidate(reading: _DigitReading());
    }

    final reading = await _detectDigits(processedBytes);
    return _DigitCandidate(cropBytes: processedBytes, reading: reading);
  }

  _DigitCandidate _preferDigitCandidate(
    _DigitCandidate tight,
    _DigitCandidate wide,
  ) {
    if (wide.reading.digitCount != tight.reading.digitCount) {
      return wide.reading.digitCount > tight.reading.digitCount ? wide : tight;
    }
    return wide.reading.averageConfidence > tight.reading.averageConfidence
        ? wide
        : tight;
  }

  Future<String?> _detectNumber(Uint8List imageBytes) async {
    final reading = await _detectDigits(imageBytes);
    return reading.number;
  }

  Future<_DigitReading> _detectDigits(Uint8List imageBytes) async {
    final result = await digitYolo.predict(
      imageBytes,
      confidenceThreshold: digitConfidenceThreshold,
      iouThreshold: digitIouThreshold,
    );

    debugPrint('Raw digit detections: ${result['detections']}');

    final detections = parseYoloDetections(result['detections']);

    debugPrint('Parsed digit count: ${detections.length}');

    for (final detection in detections) {
      debugPrint(
        'เลข=${detection.className}, '
        'confidence=${detection.confidence}, '
        'box=${detection.boundingBox}',
      );
    }

    final digitDetections =
        detections
            .where(
              (detection) =>
                  RegExp(r'^\d$').hasMatch(detection.className.trim()),
            )
            .toList()
          ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final selectedDigits = digitDetections.take(2).toList();
    final number = readDigitSequence(selectedDigits, maxDigits: 2);
    final averageConfidence = selectedDigits.isEmpty
        ? 0.0
        : selectedDigits
                  .map((detection) => detection.confidence)
                  .reduce((a, b) => a + b) /
              selectedDigits.length;

    debugPrint('เลขที่อ่านได้: $number');

    return _DigitReading(
      number: number,
      digitCount: selectedDigits.length,
      averageConfidence: averageConfidence,
    );
  }
}

class _DigitCandidate {
  final Uint8List? cropBytes;
  final _DigitReading reading;

  const _DigitCandidate({this.cropBytes, required this.reading});
}

class _DigitReading {
  final String? number;
  final int digitCount;
  final double averageConfidence;

  const _DigitReading({
    this.number,
    this.digitCount = 0,
    this.averageConfidence = 0,
  });
}
