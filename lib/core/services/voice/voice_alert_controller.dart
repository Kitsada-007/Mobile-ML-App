import 'package:trffic_ilght_app/core/services/detection/detection_alert_config.dart';
import 'package:trffic_ilght_app/core/services/detection/detection_stabilizer.dart';

typedef StableClassSpeaker = Future<void> Function(String className);

/// แปลง stable events เป็นคำสั่งเสียงเพียงหนึ่งรายการต่อเฟรม
final class VoiceAlertController {
  VoiceAlertController({
    required StableClassSpeaker speakClassName,
    this.config = const DetectionAlertConfig(),
  }) {
    _speakClassName = speakClassName;
  }

  late final StableClassSpeaker _speakClassName;
  final DetectionAlertConfig config;
  final Map<String, DateTime> _lastSpokenAtByClass = {};
  bool _isSpeaking = false;
  int _sessionGeneration = 0;

  bool get isSpeaking => _isSpeaking;

  Future<DetectionEvent?> handleEvents(Iterable<DetectionEvent> events) async {
    if (_isSpeaking) return null;

    final candidates = events
        .where(
          (event) =>
              config.participatesInVoiceAlerts(event.detection.className) &&
              (event.type == DetectionEventType.detected ||
                  event.type == DetectionEventType.changed),
        )
        .toList();
    candidates.sort((first, second) {
      final firstRule = config.ruleFor(first.detection.className);
      final secondRule = config.ruleFor(second.detection.className);
      return firstRule.priority.compareTo(secondRule.priority);
    });
    if (candidates.isEmpty) return null;

    DetectionEvent? selected;
    for (final candidate in candidates) {
      final className = candidate.detection.className;
      final cooldown = config.ruleFor(className).voiceCooldown;
      final lastSpokenAt = _lastSpokenAtByClass[className];
      if (lastSpokenAt == null ||
          candidate.timestamp.difference(lastSpokenAt) >= cooldown) {
        selected = candidate;
        break;
      }
    }
    if (selected == null) return null;

    final className = selected.detection.className;
    final didSpeak = await speakMessageIfIdle(() => _speakClassName(className));
    if (!didSpeak) return null;
    _lastSpokenAtByClass[className] = selected.timestamp;
    return selected;
  }

  Future<bool> speakMessageIfIdle(Future<void> Function() speaker) async {
    if (_isSpeaking) return false;

    final generation = _sessionGeneration;
    _isSpeaking = true;
    try {
      await speaker();
      return generation == _sessionGeneration;
    } finally {
      if (generation == _sessionGeneration) _isSpeaking = false;
    }
  }

  void reset() {
    _sessionGeneration += 1;
    _lastSpokenAtByClass.clear();
    _isSpeaking = false;
  }
}
