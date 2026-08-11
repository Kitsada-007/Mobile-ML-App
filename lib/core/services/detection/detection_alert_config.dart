enum DetectionGroup { trafficLight, turnSignal, sign, countdown, other }

final class DetectionRule {
  const DetectionRule({
    required this.historySize,
    required this.requiredVotes,
    required this.missingGracePeriod,
    required this.voiceCooldown,
    required this.priority,
    this.minimumConsecutiveFrames,
    this.minimumContinuousDuration,
  });

  final int historySize;
  final int requiredVotes;
  final Duration missingGracePeriod;
  final Duration voiceCooldown;
  final int priority;
  final int? minimumConsecutiveFrames;
  final Duration? minimumContinuousDuration;
}

/// รวมค่าคอนฟิก tracking, smoothing และเสียงไว้ที่เดียว
final class DetectionAlertConfig {
  const DetectionAlertConfig({
    this.minimumTrackingIou = 0.2,
    this.minimumConfidence = 0.25,
    this.trafficHistorySize = 5,
    this.trafficRequiredVotes = 4,
    this.trafficMissingGracePeriod = const Duration(seconds: 1),
    this.trafficVoiceCooldown = const Duration(seconds: 3),
    this.offLightMinimumFrames = 6,
    this.offLightMinimumDuration = const Duration(seconds: 1),
    this.turnHistorySize = 3,
    this.turnRequiredVotes = 3,
    this.turnMissingGracePeriod = const Duration(seconds: 1),
    this.turnVoiceCooldown = const Duration(seconds: 5),
    this.signHistorySize = 3,
    this.signRequiredVotes = 3,
    this.signMissingGracePeriod = const Duration(milliseconds: 1500),
    this.signVoiceCooldown = const Duration(seconds: 8),
    this.countdownHistorySize = 3,
    this.countdownRequiredVotes = 3,
    this.countdownMissingGracePeriod = const Duration(milliseconds: 1500),
    this.countdownVoiceCooldown = const Duration(seconds: 10),
  });

  static const trafficLightClasses = <String>{
    'red_light_circle',
    'yellow_light',
    'green_light_circle',
    'off_light',
  };

  static const turnSignalClasses = <String>{'turn_left', 'turn_right'};

  static const signClasses = <String>{
    'dont_go_straight_arrow',
    'dont_turn_left',
    'dont_turn_right',
    'go_straight_arrow',
  };

  final double minimumTrackingIou;
  final double minimumConfidence;

  final int trafficHistorySize;
  final int trafficRequiredVotes;
  final Duration trafficMissingGracePeriod;
  final Duration trafficVoiceCooldown;
  final int offLightMinimumFrames;
  final Duration offLightMinimumDuration;

  final int turnHistorySize;
  final int turnRequiredVotes;
  final Duration turnMissingGracePeriod;
  final Duration turnVoiceCooldown;

  final int signHistorySize;
  final int signRequiredVotes;
  final Duration signMissingGracePeriod;
  final Duration signVoiceCooldown;

  final int countdownHistorySize;
  final int countdownRequiredVotes;
  final Duration countdownMissingGracePeriod;
  final Duration countdownVoiceCooldown;

  DetectionGroup groupFor(String className) {
    if (trafficLightClasses.contains(className)) {
      return DetectionGroup.trafficLight;
    }
    if (turnSignalClasses.contains(className)) {
      return DetectionGroup.turnSignal;
    }
    if (signClasses.contains(className)) return DetectionGroup.sign;
    if (className == 'sign_number') return DetectionGroup.countdown;
    return DetectionGroup.other;
  }

  DetectionRule ruleFor(String className) {
    return switch (groupFor(className)) {
      DetectionGroup.trafficLight => DetectionRule(
        historySize: trafficHistorySize,
        requiredVotes: trafficRequiredVotes,
        missingGracePeriod: trafficMissingGracePeriod,
        voiceCooldown: trafficVoiceCooldown,
        priority: _priorityFor(className),
        minimumConsecutiveFrames: className == 'off_light'
            ? offLightMinimumFrames
            : null,
        minimumContinuousDuration: className == 'off_light'
            ? offLightMinimumDuration
            : null,
      ),
      DetectionGroup.turnSignal => DetectionRule(
        historySize: turnHistorySize,
        requiredVotes: turnRequiredVotes,
        missingGracePeriod: turnMissingGracePeriod,
        voiceCooldown: turnVoiceCooldown,
        priority: _priorityFor(className),
      ),
      DetectionGroup.sign => DetectionRule(
        historySize: signHistorySize,
        requiredVotes: signRequiredVotes,
        missingGracePeriod: signMissingGracePeriod,
        voiceCooldown: signVoiceCooldown,
        priority: _priorityFor(className),
      ),
      DetectionGroup.countdown => DetectionRule(
        historySize: countdownHistorySize,
        requiredVotes: countdownRequiredVotes,
        missingGracePeriod: countdownMissingGracePeriod,
        voiceCooldown: countdownVoiceCooldown,
        priority: _priorityFor(className),
      ),
      DetectionGroup.other => DetectionRule(
        historySize: signHistorySize,
        requiredVotes: signRequiredVotes,
        missingGracePeriod: signMissingGracePeriod,
        voiceCooldown: signVoiceCooldown,
        priority: _priorityFor(className),
      ),
    };
  }

  int maximumHistorySizeFor(DetectionGroup group) {
    if (group == DetectionGroup.trafficLight) {
      return offLightMinimumFrames > trafficHistorySize
          ? offLightMinimumFrames
          : trafficHistorySize;
    }
    return switch (group) {
      DetectionGroup.turnSignal => turnHistorySize,
      DetectionGroup.sign || DetectionGroup.other => signHistorySize,
      DetectionGroup.countdown => countdownHistorySize,
      DetectionGroup.trafficLight => trafficHistorySize,
    };
  }

  int _priorityFor(String className) {
    return switch (className) {
      'off_light' => 0,
      'red_light_circle' => 1,
      'yellow_light' => 2,
      'green_light_circle' => 3,
      'turn_left' || 'turn_right' => 4,
      'dont_go_straight_arrow' || 'dont_turn_left' || 'dont_turn_right' => 5,
      'go_straight_arrow' => 6,
      'sign_number' => 7,
      _ => 8,
    };
  }
}
