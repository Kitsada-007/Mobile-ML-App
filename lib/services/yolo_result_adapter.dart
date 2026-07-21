import 'package:ultralytics_yolo/ultralytics_yolo.dart';

/// Converts untrusted platform-channel data into typed YOLO detections.
List<YOLOResult> parseYoloDetections(Object? rawDetections) {
  if (rawDetections is! List) return const [];

  final results = <YOLOResult>[];
  for (final rawDetection in rawDetections) {
    if (rawDetection is! Map || !_hasRequiredDetectionFields(rawDetection)) {
      continue;
    }

    try {
      results.add(YOLOResult.fromMap(rawDetection));
    } on Object {
      // A malformed native entry must not discard valid detections in the frame.
    }
  }
  return results;
}

String? readDigitSequence(Iterable<YOLOResult> detections, {int? maxDigits}) {
  if (maxDigits != null && maxDigits <= 0) return null;

  final digits =
      detections
          .where(
            (detection) => RegExp(r'^\d$').hasMatch(detection.className.trim()),
          )
          .toList()
        ..sort((a, b) => _leftEdge(a).compareTo(_leftEdge(b)));

  if (digits.isEmpty) return null;
  return digits
      .take(maxDigits ?? digits.length)
      .map((detection) => detection.className.trim())
      .join();
}

bool _hasRequiredDetectionFields(Map<dynamic, dynamic> detection) {
  return detection['classIndex'] is num &&
      detection['className'] is String &&
      detection['confidence'] is num &&
      detection['boundingBox'] is Map &&
      detection['normalizedBox'] is Map;
}

double _leftEdge(YOLOResult detection) {
  final normalizedBox = detection.normalizedBox;
  if (normalizedBox.width > 0 && normalizedBox.height > 0) {
    return normalizedBox.left;
  }
  return detection.boundingBox.left;
}
