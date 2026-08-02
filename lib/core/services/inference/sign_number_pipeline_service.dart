import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:trffic_ilght_app/core/services/inference/number_detection_service.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

export 'package:trffic_ilght_app/core/services/inference/number_detection_service.dart'
    show digitConfidenceThreshold, digitIouThreshold;

const int minimumDigitCropEdge = 128;
const int maximumDigitCropEdge = 640;
const double tightHorizontalPaddingFactor = 0.15;
const double tightVerticalPaddingFactor = 0.10;
const double wideHorizontalPaddingFactor = 0.30;
const double wideVerticalPaddingFactor = 0.15;

void _debugPipeline(String message) {
  if (kDebugMode) debugPrint(message);
}

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

/// YOLOView 0.6.10 reports boxes in the upright frame coordinate space but
/// streams the camera bitmap before CameraX rotation. Normalize the bitmap
/// before applying those boxes.
@visibleForTesting
Uint8List orientFrameForDetectionCoordinates(
  Uint8List frameBytes, {
  int? expectedWidth,
  int? expectedHeight,
  int? rotationDegrees,
}) {
  final decoded = img.decodeImage(frameBytes);
  if (decoded == null) return frameBytes;

  img.Image oriented = img.bakeOrientation(decoded);
  final normalizedRotation = rotationDegrees == null
      ? null
      : ((rotationDegrees % 360) + 360) % 360;
  final dimensionsAreReversed =
      expectedWidth != null &&
      expectedHeight != null &&
      oriented.width == expectedHeight &&
      oriented.height == expectedWidth;

  final degrees = normalizedRotation ?? (dimensionsAreReversed ? 90 : 0);
  if (degrees == 0) return frameBytes;

  oriented = img.copyRotate(oriented, angle: degrees);
  return Uint8List.fromList(img.encodeJpg(oriented, quality: 95));
}

bool _frameDimensionsAreReversed(
  Uint8List frameBytes, {
  required int expectedWidth,
  required int expectedHeight,
}) {
  final decoded = img.decodeImage(frameBytes);
  if (decoded == null) return false;
  final oriented = img.bakeOrientation(decoded);
  return oriented.width == expectedHeight && oriented.height == expectedWidth;
}

class OrientFrameData {
  final Uint8List frameBytes;
  final int? expectedWidth;
  final int? expectedHeight;
  final int? rotationDegrees;

  const OrientFrameData({
    required this.frameBytes,
    this.expectedWidth,
    this.expectedHeight,
    this.rotationDegrees,
  });
}

Uint8List _orientFrameTask(OrientFrameData data) {
  return orientFrameForDetectionCoordinates(
    data.frameBytes,
    expectedWidth: data.expectedWidth,
    expectedHeight: data.expectedHeight,
    rotationDegrees: data.rotationDegrees,
  );
}

class ReversedDimensionsData {
  final Uint8List frameBytes;
  final int expectedWidth;
  final int expectedHeight;

  const ReversedDimensionsData({
    required this.frameBytes,
    required this.expectedWidth,
    required this.expectedHeight,
  });
}

bool _frameDimensionsAreReversedTask(ReversedDimensionsData data) {
  return _frameDimensionsAreReversed(
    data.frameBytes,
    expectedWidth: data.expectedWidth,
    expectedHeight: data.expectedHeight,
  );
}

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
      _debugPipeline('Crop ไม่ถูกต้อง');
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

    _debugPipeline('Crop พร้อมตรวจเลข: ${cropped.width}x${cropped.height}');

    return Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
  } catch (e, stackTrace) {
    _debugPipeline('Isolate Crop Error: $e');
    _debugPipeline('$stackTrace');
    return null;
  }
}

class RealtimeFrameTaskData {
  final Uint8List frameBytes;
  final List<YOLOResult> detectionResults;
  final int? expectedFrameWidth;
  final int? expectedFrameHeight;
  final int? rotationDegrees;
  final bool runAlternative;

  RealtimeFrameTaskData({
    required this.frameBytes,
    required this.detectionResults,
    this.expectedFrameWidth,
    this.expectedFrameHeight,
    this.rotationDegrees,
    this.runAlternative = false,
  });
}

class RealtimeFrameTaskResult {
  final Uint8List? tightCropBytes;
  final Uint8List? wideCropBytes;
  final YOLOResult? selectedSign;

  RealtimeFrameTaskResult({
    this.tightCropBytes,
    this.wideCropBytes,
    this.selectedSign,
  });
}

RealtimeFrameTaskResult _processRealtimeFrameTask(RealtimeFrameTaskData data) {
  final signResults = data.detectionResults
      .where((result) => result.className == 'sign_number')
      .toList();

  if (signResults.isEmpty) {
    return RealtimeFrameTaskResult();
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

  final decoded = img.decodeImage(data.frameBytes);
  if (decoded == null) return RealtimeFrameTaskResult();

  img.Image original = img.bakeOrientation(decoded);

  int degrees = 0;
  if (data.rotationDegrees != null) {
    degrees = ((data.rotationDegrees! % 360) + 360) % 360;
  } else if (data.expectedFrameWidth != null &&
      data.expectedFrameHeight != null) {
    final dimensionsAreReversed =
        original.width == data.expectedFrameHeight &&
        original.height == data.expectedFrameWidth;
    if (data.runAlternative) {
      degrees = dimensionsAreReversed ? 270 : 180;
    } else {
      degrees = dimensionsAreReversed ? 90 : 0;
    }
  }

  if (degrees != 0) {
    original = img.copyRotate(original, angle: degrees);
  }

  final int imageWidth = original.width;
  final int imageHeight = original.height;

  double x1 = rect.left;
  double y1 = rect.top;
  double x2 = rect.right;
  double y2 = rect.bottom;

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

  final bounds = (left: left, top: top, right: right, bottom: bottom);
  final int cropWidth = bounds.right - bounds.left;
  final int cropHeight = bounds.bottom - bounds.top;

  if (cropWidth <= 0 || cropHeight <= 0) {
    return RealtimeFrameTaskResult();
  }

  Uint8List? cropAndEncode(double hPadding, double vPadding) {
    final padded = expandCropBounds(
      bounds,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      horizontalPaddingFactor: hPadding,
      verticalPaddingFactor: vPadding,
    );

    img.Image cropped = img.copyCrop(
      original,
      x: padded.left,
      y: padded.top,
      width: padded.right - padded.left,
      height: padded.bottom - padded.top,
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

    cropped = img.grayscale(cropped);
    return Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
  }

  final tightBytes = cropAndEncode(
    tightHorizontalPaddingFactor,
    tightVerticalPaddingFactor,
  );
  final wideBytes = cropAndEncode(
    wideHorizontalPaddingFactor,
    wideVerticalPaddingFactor,
  );

  return RealtimeFrameTaskResult(
    tightCropBytes: tightBytes,
    wideCropBytes: wideBytes,
    selectedSign: sign,
  );
}

class SignNumberPipelineService {
  SignNumberPipelineService({
    NumberDetectionService? numberDetectionService,
    YOLO? digitYolo,
  }) : _numberDetectionService = _resolveNumberDetectionService(
         numberDetectionService: numberDetectionService,
         digitYolo: digitYolo,
       );

  final NumberDetectionService _numberDetectionService;

  static NumberDetectionService _resolveNumberDetectionService({
    NumberDetectionService? numberDetectionService,
    YOLO? digitYolo,
  }) {
    if (numberDetectionService != null) return numberDetectionService;
    if (digitYolo != null) {
      return NumberDetectionService(numberYolo: digitYolo);
    }
    throw ArgumentError('numberDetectionService or digitYolo must be provided');
  }

  Future<String?> detectNumberFromSign({
    required Uint8List frameBytes,
    required List<YOLOResult> detectionResults,
    int? expectedFrameWidth,
    int? expectedFrameHeight,
    int? rotationDegrees,
  }) async {
    final analysis = await analyzeRealtimeFrame(
      frameBytes: frameBytes,
      detectionResults: detectionResults,
      expectedFrameWidth: expectedFrameWidth,
      expectedFrameHeight: expectedFrameHeight,
      rotationDegrees: rotationDegrees,
    );
    return analysis.number;
  }

  Future<SignNumberAnalysis> analyzeRealtimeFrame({
    required Uint8List frameBytes,
    required List<YOLOResult> detectionResults,
    int? expectedFrameWidth,
    int? expectedFrameHeight,
    int? rotationDegrees,
  }) async {
    final taskResult = await compute(
      _processRealtimeFrameTask,
      RealtimeFrameTaskData(
        frameBytes: frameBytes,
        detectionResults: detectionResults,
        expectedFrameWidth: expectedFrameWidth,
        expectedFrameHeight: expectedFrameHeight,
        rotationDegrees: rotationDegrees,
      ),
    );

    if (taskResult.tightCropBytes == null) {
      return const SignNumberAnalysis();
    }

    final tightReading = await _numberDetectionService.detect(
      taskResult.tightCropBytes!,
    );
    if (tightReading.digitCount >= 2) {
      return SignNumberAnalysis(
        cropBytes: taskResult.tightCropBytes,
        number: tightReading.number,
        selectedSign: taskResult.selectedSign,
      );
    }

    final wideReading = taskResult.wideCropBytes != null
        ? await _numberDetectionService.detect(taskResult.wideCropBytes!)
        : const NumberDetectionResult();

    final preferred = wideReading.digitCount != tightReading.digitCount
        ? (wideReading.digitCount > tightReading.digitCount
              ? wideReading
              : tightReading)
        : (wideReading.averageConfidence > tightReading.averageConfidence
              ? wideReading
              : tightReading);

    final selectedBytes = preferred == wideReading
        ? taskResult.wideCropBytes
        : taskResult.tightCropBytes;

    if (preferred.number != null ||
        rotationDegrees != null ||
        expectedFrameWidth == null ||
        expectedFrameHeight == null) {
      return SignNumberAnalysis(
        cropBytes: selectedBytes,
        number: preferred.number,
        selectedSign: taskResult.selectedSign,
      );
    }

    final altResult = await compute(
      _processRealtimeFrameTask,
      RealtimeFrameTaskData(
        frameBytes: frameBytes,
        detectionResults: detectionResults,
        expectedFrameWidth: expectedFrameWidth,
        expectedFrameHeight: expectedFrameHeight,
        runAlternative: true,
      ),
    );

    if (altResult.tightCropBytes == null) {
      return const SignNumberAnalysis();
    }

    final altTightReading = await _numberDetectionService.detect(
      altResult.tightCropBytes!,
    );
    if (altTightReading.digitCount >= 2) {
      return SignNumberAnalysis(
        cropBytes: altResult.tightCropBytes,
        number: altTightReading.number,
        selectedSign: altResult.selectedSign,
      );
    }

    final altWideReading = altResult.wideCropBytes != null
        ? await _numberDetectionService.detect(altResult.wideCropBytes!)
        : const NumberDetectionResult();

    final altPreferred = altWideReading.digitCount != altTightReading.digitCount
        ? (altWideReading.digitCount > altTightReading.digitCount
              ? altWideReading
              : altTightReading)
        : (altWideReading.averageConfidence > altTightReading.averageConfidence
              ? altWideReading
              : altTightReading);

    final altSelectedBytes = altPreferred == altWideReading
        ? altResult.wideCropBytes
        : altResult.tightCropBytes;

    return SignNumberAnalysis(
      cropBytes: altSelectedBytes,
      number: altPreferred.number,
      selectedSign: altResult.selectedSign,
    );
  }

  Future<SignNumberAnalysis> analyzeSingleImage({
    required Uint8List frameBytes,
    required List<YOLOResult> detectionResults,
  }) async {
    final signResults = detectionResults
        .where((result) => result.className == 'sign_number')
        .toList();

    if (signResults.isEmpty) {
      _debugPipeline('ไม่พบคลาส sign_number');
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

    _debugPipeline('Normalized box: ${sign.normalizedBox}');
    _debugPipeline('Bounding box: ${sign.boundingBox}');
    _debugPipeline('Selected crop box: $rect');

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
      _debugPipeline('สร้างภาพ crop ไม่สำเร็จ');
      return const _DigitCandidate(reading: NumberDetectionResult());
    }

    final reading = await _numberDetectionService.detect(processedBytes);
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
}

class _DigitCandidate {
  final Uint8List? cropBytes;
  final NumberDetectionResult reading;

  const _DigitCandidate({this.cropBytes, required this.reading});
}
