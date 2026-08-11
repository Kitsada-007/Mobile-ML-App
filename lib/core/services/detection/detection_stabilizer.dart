import 'dart:collection';
import 'dart:ui';

import 'package:trffic_ilght_app/core/services/detection/detection_alert_config.dart';
import 'package:ultralytics_yolo/yolo.dart';

enum DetectionEventType { detected, changed, lost }

final class StableDetection {
  const StableDetection({
    required this.trackId,
    required this.className,
    required this.confidence,
    required this.boundingBox,
    required this.normalizedBox,
    this.classIndex = 0,
  });

  final int trackId;
  final int classIndex;
  final String className;
  final double confidence;
  final Rect boundingBox;
  final Rect normalizedBox;

  YOLOResult toYoloResult() => YOLOResult(
    classIndex: classIndex,
    className: className,
    confidence: confidence,
    boundingBox: boundingBox,
    normalizedBox: normalizedBox,
  );
}

final class DetectionEvent {
  const DetectionEvent({
    required this.type,
    required this.detection,
    required this.timestamp,
  });

  final DetectionEventType type;
  final StableDetection detection;
  final DateTime timestamp;
}

final class DetectionStabilizerUpdate {
  const DetectionStabilizerUpdate({
    required this.stableDetections,
    required this.events,
  });

  final List<StableDetection> stableDetections;
  final List<DetectionEvent> events;
}

final class DetectionObservation {
  const DetectionObservation({
    required this.className,
    required this.confidence,
    required this.timestamp,
  });

  final String className;
  final double confidence;
  final DateTime timestamp;
}

final class TrackedDetectionState {
  TrackedDetectionState._({
    required this.trackId,
    required this.group,
    required YOLOResult initialDetection,
    required DateTime timestamp,
  }) : _lastDetection = initialDetection,
       _lastSeenAt = timestamp;

  final int trackId;
  final DetectionGroup group;
  final Queue<DetectionObservation> _history = Queue();
  YOLOResult _lastDetection;
  DateTime _lastSeenAt;
  String? _stableClassName;

  List<DetectionObservation> get history => List.unmodifiable(_history);
  DateTime get lastSeenAt => _lastSeenAt;
  String? get stableClassName => _stableClassName;
}

final class DetectionStabilizer {
  DetectionStabilizer({this.config = const DetectionAlertConfig()});

  final DetectionAlertConfig config;
  final Map<int, TrackedDetectionState> _tracks = {};
  int _nextTrackId = 1;

  List<TrackedDetectionState> get tracks => List.unmodifiable(_tracks.values);

  List<StableDetection> get stableDetections => _tracks.values
      .where((track) => track._stableClassName != null)
      .map(_stableDetectionFor)
      .toList(growable: false);

  DetectionStabilizerUpdate update(
    Iterable<YOLOResult> rawDetections, {
    required DateTime timestamp,
  }) {
    final events = <DetectionEvent>[];
    _expireTracks(timestamp, events);

    final detections =
        rawDetections
            .where(
              (detection) =>
                  detection.confidence.isFinite &&
                  detection.confidence >= config.minimumConfidence &&
                  _trackingBox(detection).width > 0 &&
                  _trackingBox(detection).height > 0,
            )
            .toList()
          ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final matchedTrackIds = <int>{};

    for (final detection in detections) {
      final group = config.groupFor(detection.className);
      final track = _bestTrackFor(
        detection,
        group: group,
        excludedTrackIds: matchedTrackIds,
      );
      final selectedTrack =
          track ?? _createTrack(detection, group: group, timestamp: timestamp);
      matchedTrackIds.add(selectedTrack.trackId);
      _addObservation(selectedTrack, detection, timestamp);
      final event = _evaluateStableClass(selectedTrack, timestamp);
      if (event != null) events.add(event);
    }

    return DetectionStabilizerUpdate(
      stableDetections: stableDetections,
      events: List.unmodifiable(events),
    );
  }

  bool hasStableClass(String className) =>
      stableDetections.any((detection) => detection.className == className);

  void reset() {
    _tracks.clear();
    _nextTrackId = 1;
  }

  TrackedDetectionState _createTrack(
    YOLOResult detection, {
    required DetectionGroup group,
    required DateTime timestamp,
  }) {
    final track = TrackedDetectionState._(
      trackId: _nextTrackId++,
      group: group,
      initialDetection: detection,
      timestamp: timestamp,
    );
    _tracks[track.trackId] = track;
    return track;
  }

  TrackedDetectionState? _bestTrackFor(
    YOLOResult detection, {
    required DetectionGroup group,
    required Set<int> excludedTrackIds,
  }) {
    TrackedDetectionState? bestTrack;
    var bestIou = config.minimumTrackingIou;
    for (final track in _tracks.values) {
      if (track.group != group || excludedTrackIds.contains(track.trackId)) {
        continue;
      }
      final iou = _intersectionOverUnion(
        _trackingBox(track._lastDetection),
        _trackingBox(detection),
      );
      if (iou >= bestIou) {
        bestIou = iou;
        bestTrack = track;
      }
    }
    return bestTrack;
  }

  void _addObservation(
    TrackedDetectionState track,
    YOLOResult detection,
    DateTime timestamp,
  ) {
    track._lastDetection = detection;
    track._lastSeenAt = timestamp;
    track._history.addLast(
      DetectionObservation(
        className: detection.className,
        confidence: detection.confidence,
        timestamp: timestamp,
      ),
    );
    final maximumHistorySize = config.maximumHistorySizeFor(track.group);
    while (track._history.length > maximumHistorySize) {
      track._history.removeFirst();
    }
  }

  DetectionEvent? _evaluateStableClass(
    TrackedDetectionState track,
    DateTime timestamp,
  ) {
    final candidate = _winningClass(track);
    if (candidate == null || candidate == track._stableClassName) return null;

    final previousClass = track._stableClassName;
    track._stableClassName = candidate;
    return DetectionEvent(
      type: previousClass == null
          ? DetectionEventType.detected
          : DetectionEventType.changed,
      detection: _stableDetectionFor(track),
      timestamp: timestamp,
    );
  }

  String? _winningClass(TrackedDetectionState track) {
    if (track._history.isEmpty) return null;
    final latestClass = track._history.last.className;
    final rule = config.ruleFor(latestClass);
    final recent = track._history.length <= rule.historySize
        ? track._history.toList(growable: false)
        : track._history
              .skip(track._history.length - rule.historySize)
              .toList(growable: false);

    final voteCounts = <String, int>{};
    final confidenceScores = <String, double>{};
    for (final observation in recent) {
      voteCounts.update(
        observation.className,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      confidenceScores.update(
        observation.className,
        (score) => score + observation.confidence,
        ifAbsent: () => observation.confidence,
      );
    }

    final ranked = voteCounts.keys.toList()
      ..sort((first, second) {
        final countOrder = voteCounts[second]!.compareTo(voteCounts[first]!);
        if (countOrder != 0) return countOrder;
        return confidenceScores[second]!.compareTo(confidenceScores[first]!);
      });
    final candidate = ranked.first;
    final candidateRule = config.ruleFor(candidate);
    if (voteCounts[candidate]! < candidateRule.requiredVotes) return null;
    if (!_passesContinuousConfirmation(track, candidate, candidateRule)) {
      return null;
    }
    return candidate;
  }

  bool _passesContinuousConfirmation(
    TrackedDetectionState track,
    String candidate,
    DetectionRule rule,
  ) {
    final requiredFrames = rule.minimumConsecutiveFrames;
    final requiredDuration = rule.minimumContinuousDuration;
    if (requiredFrames == null && requiredDuration == null) return true;

    final consecutive = <DetectionObservation>[];
    for (final observation in track._history.toList().reversed) {
      if (observation.className != candidate) break;
      consecutive.add(observation);
    }
    final frameRequirementPassed =
        requiredFrames != null && consecutive.length >= requiredFrames;
    final durationRequirementPassed =
        requiredDuration != null &&
        consecutive.isNotEmpty &&
        consecutive.first.timestamp.difference(consecutive.last.timestamp) >=
            requiredDuration;
    return frameRequirementPassed || durationRequirementPassed;
  }

  void _expireTracks(DateTime timestamp, List<DetectionEvent> events) {
    final expiredIds = <int>[];
    for (final track in _tracks.values) {
      final referenceClass =
          track._stableClassName ?? track._lastDetection.className;
      final gracePeriod = config.ruleFor(referenceClass).missingGracePeriod;
      if (timestamp.difference(track._lastSeenAt) <= gracePeriod) continue;

      final stableClass = track._stableClassName;
      if (stableClass != null) {
        events.add(
          DetectionEvent(
            type: DetectionEventType.lost,
            detection: _stableDetectionFor(track),
            timestamp: timestamp,
          ),
        );
      }
      expiredIds.add(track.trackId);
    }
    for (final trackId in expiredIds) {
      _tracks.remove(trackId);
    }
  }

  StableDetection _stableDetectionFor(TrackedDetectionState track) {
    final stableClass = track._stableClassName!;
    final observations = track._history
        .where((observation) => observation.className == stableClass)
        .toList(growable: false);
    final confidence = observations.isEmpty
        ? track._lastDetection.confidence
        : observations
                  .map((observation) => observation.confidence)
                  .reduce((first, second) => first + second) /
              observations.length;
    return StableDetection(
      trackId: track.trackId,
      classIndex: track._lastDetection.classIndex,
      className: stableClass,
      confidence: confidence,
      boundingBox: track._lastDetection.boundingBox,
      normalizedBox: track._lastDetection.normalizedBox,
    );
  }
}

Rect _trackingBox(YOLOResult detection) {
  final normalized = detection.normalizedBox;
  return normalized.width > 0 && normalized.height > 0
      ? normalized
      : detection.boundingBox;
}

double _intersectionOverUnion(Rect first, Rect second) {
  final intersection = first.intersect(second);
  if (intersection.width <= 0 || intersection.height <= 0) return 0;
  final intersectionArea = intersection.width * intersection.height;
  final unionArea =
      first.width * first.height +
      second.width * second.height -
      intersectionArea;
  return unionArea <= 0 ? 0 : intersectionArea / unionArea;
}
