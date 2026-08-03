import 'dart:math' as math;

const Set<String> trafficLightStateClassNames = {
  'red_light_circle',
  'yellow_light',
  'green_light_circle',
};

bool isTrafficLightStateClass(String className) =>
    trafficLightStateClassNames.contains(className);

class TrafficLightObservation {
  const TrafficLightObservation({
    required this.className,
    required this.confidence,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String className;
  final double confidence;
  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => math.max(0, right - left);
  double get height => math.max(0, bottom - top);
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;
  double get area => width * height;

  bool get isValid =>
      isTrafficLightStateClass(className) &&
      confidence.isFinite &&
      width > 0 &&
      height > 0;
}

class TrafficLightStateUpdate {
  const TrafficLightStateUpdate({
    required this.confirmedClassName,
    required this.stateChanged,
    required this.trackingId,
  });

  final String? confirmedClassName;
  final bool stateChanged;
  final int? trackingId;
}

/// Tracks one relevant traffic light and stabilizes its color over time.
class TrafficLightStateStabilizer {
  TrafficLightStateStabilizer({
    this.minimumObservationConfidence = 0.5,
    this.emaAlpha = 0.4,
    this.confirmationThreshold = 0.7,
    this.minimumBeliefMargin = 0.2,
    this.redConfirmationFrames = 2,
    this.yellowConfirmationFrames = 2,
    this.greenConfirmationFrames = 4,
    this.trackingTimeout = const Duration(milliseconds: 800),
    this.maximumTrackingCenterDistance = 0.22,
    this.minimumTrackingIou = 0.02,
  }) : assert(emaAlpha > 0 && emaAlpha <= 1),
       assert(redConfirmationFrames > 0),
       assert(yellowConfirmationFrames > 0),
       assert(greenConfirmationFrames > 0);

  final double minimumObservationConfidence;
  final double emaAlpha;
  final double confirmationThreshold;
  final double minimumBeliefMargin;
  final int redConfirmationFrames;
  final int yellowConfirmationFrames;
  final int greenConfirmationFrames;
  final Duration trackingTimeout;
  final double maximumTrackingCenterDistance;
  final double minimumTrackingIou;

  final Map<String, double> _beliefs = {
    for (final className in trafficLightStateClassNames) className: 0,
  };

  TrafficLightObservation? _trackedBox;
  DateTime? _lastSeenAt;
  String? _pendingClassName;
  int _pendingFrameCount = 0;
  String? _confirmedClassName;
  int _nextTrackingId = 1;
  int? _activeTrackingId;

  String? get confirmedClassName => _confirmedClassName;
  int? get activeTrackingId => _activeTrackingId;

  TrafficLightStateUpdate update(
    Iterable<TrafficLightObservation> observations, {
    required DateTime timestamp,
  }) {
    final validObservations = observations
        .where(
          (observation) =>
              observation.isValid &&
              observation.confidence >= minimumObservationConfidence,
        )
        .toList(growable: false);

    final selected = _selectObservation(validObservations);
    if (selected == null) {
      return _handleMissingObservation(timestamp);
    }

    _activeTrackingId ??= _nextTrackingId++;
    _lastSeenAt = timestamp;
    _trackedBox = _smoothTrackedBox(selected);
    _updateBeliefs(selected);
    _updatePendingState(selected.className);

    final rankedBeliefs = _beliefs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final winner = rankedBeliefs.first;
    final beliefMargin = winner.value - rankedBeliefs[1].value;
    final requiredFrames = _requiredFrames(selected.className);

    final isConfirmedCandidate =
        winner.key == selected.className &&
        winner.value >= confirmationThreshold &&
        beliefMargin >= minimumBeliefMargin &&
        _pendingFrameCount >= requiredFrames;

    var stateChanged = false;
    if (isConfirmedCandidate && _confirmedClassName != winner.key) {
      _confirmedClassName = winner.key;
      stateChanged = true;
    }

    return TrafficLightStateUpdate(
      confirmedClassName: _confirmedClassName,
      stateChanged: stateChanged,
      trackingId: _activeTrackingId,
    );
  }

  TrafficLightObservation? _selectObservation(
    List<TrafficLightObservation> observations,
  ) {
    if (observations.isEmpty) return null;

    final tracked = _trackedBox;
    if (tracked == null) {
      return observations.reduce(
        (best, current) => _initialRelevance(current) > _initialRelevance(best)
            ? current
            : best,
      );
    }

    final associated = observations.where((observation) {
      return _iou(tracked, observation) >= minimumTrackingIou ||
          _centerDistance(tracked, observation) <=
              maximumTrackingCenterDistance;
    }).toList();
    if (associated.isEmpty) return null;

    return associated.reduce(
      (best, current) =>
          _trackingRelevance(tracked, current) >
              _trackingRelevance(tracked, best)
          ? current
          : best,
    );
  }

  double _initialRelevance(TrafficLightObservation observation) {
    final centeredness =
        1 - math.min(1.0, (observation.centerX - 0.5).abs() * 2);
    final sizeScore = math.min(1.0, math.sqrt(observation.area));
    return observation.confidence * 0.55 +
        centeredness * 0.30 +
        sizeScore * 0.15;
  }

  double _trackingRelevance(
    TrafficLightObservation tracked,
    TrafficLightObservation observation,
  ) {
    return _iou(tracked, observation) * 2 +
        (1 - math.min(1.0, _centerDistance(tracked, observation))) +
        observation.confidence * 0.25;
  }

  TrafficLightObservation _smoothTrackedBox(TrafficLightObservation selected) {
    final tracked = _trackedBox;
    if (tracked == null) return selected;

    const boxAlpha = 0.4;
    double smooth(double previous, double current) =>
        previous + boxAlpha * (current - previous);

    return TrafficLightObservation(
      className: selected.className,
      confidence: selected.confidence,
      left: smooth(tracked.left, selected.left),
      top: smooth(tracked.top, selected.top),
      right: smooth(tracked.right, selected.right),
      bottom: smooth(tracked.bottom, selected.bottom),
    );
  }

  void _updateBeliefs(TrafficLightObservation selected) {
    final remainingProbability = (1 - selected.confidence) / 2;
    final hasBelief = _beliefs.values.any((value) => value > 0);

    for (final className in trafficLightStateClassNames) {
      final evidence = className == selected.className
          ? selected.confidence
          : remainingProbability;
      _beliefs[className] = hasBelief
          ? emaAlpha * evidence + (1 - emaAlpha) * _beliefs[className]!
          : evidence;
    }
  }

  void _updatePendingState(String className) {
    if (_pendingClassName == className) {
      _pendingFrameCount += 1;
    } else {
      _pendingClassName = className;
      _pendingFrameCount = 1;
    }
  }

  int _requiredFrames(String className) {
    return switch (className) {
      'red_light_circle' => redConfirmationFrames,
      'yellow_light' => yellowConfirmationFrames,
      'green_light_circle' => greenConfirmationFrames,
      _ => greenConfirmationFrames,
    };
  }

  TrafficLightStateUpdate _handleMissingObservation(DateTime timestamp) {
    final lastSeenAt = _lastSeenAt;
    if (lastSeenAt == null ||
        timestamp.difference(lastSeenAt) <= trackingTimeout) {
      return TrafficLightStateUpdate(
        confirmedClassName: _confirmedClassName,
        stateChanged: false,
        trackingId: _activeTrackingId,
      );
    }

    final hadConfirmedState = _confirmedClassName != null;
    reset();
    return TrafficLightStateUpdate(
      confirmedClassName: null,
      stateChanged: hadConfirmedState,
      trackingId: null,
    );
  }

  void reset() {
    _trackedBox = null;
    _lastSeenAt = null;
    _pendingClassName = null;
    _pendingFrameCount = 0;
    _confirmedClassName = null;
    _activeTrackingId = null;
    for (final className in trafficLightStateClassNames) {
      _beliefs[className] = 0;
    }
  }
}

double _centerDistance(
  TrafficLightObservation first,
  TrafficLightObservation second,
) {
  final deltaX = first.centerX - second.centerX;
  final deltaY = first.centerY - second.centerY;
  return math.sqrt(deltaX * deltaX + deltaY * deltaY);
}

double _iou(TrafficLightObservation first, TrafficLightObservation second) {
  final intersectionWidth = math.max(
    0.0,
    math.min(first.right, second.right) - math.max(first.left, second.left),
  );
  final intersectionHeight = math.max(
    0.0,
    math.min(first.bottom, second.bottom) - math.max(first.top, second.top),
  );
  final intersectionArea = intersectionWidth * intersectionHeight;
  final unionArea = first.area + second.area - intersectionArea;
  return unionArea <= 0 ? 0 : intersectionArea / unionArea;
}
