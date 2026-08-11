import 'package:trffic_ilght_app/core/services/detection/detection_alert_config.dart';
import 'package:trffic_ilght_app/core/services/detection/detection_stabilizer.dart';

typedef StableClassSpeaker = Future<void> Function(String className);

/// แปลง stable events เป็นคำสั่งเสียงเพียงหนึ่งรายการต่อเฟรม
final class VoiceAlertController {
  VoiceAlertController({
    required StableClassSpeaker speakClassName,
    this.config = const DetectionAlertConfig(),
  }) : _speakClassName = speakClassName;

  final StableClassSpeaker _speakClassName;
  final DetectionAlertConfig config;
  final Map<String, DateTime> _lastSpokenAtByClass = {};
  bool _isSpeaking = false;
  int _sessionGeneration = 0;

  bool get isSpeaking => _isSpeaking;

  Future<DetectionEvent?> handleEvents(Iterable<DetectionEvent> events) async {
    if (_isSpeaking) return null;

    final candidates =
        events
            .where(
              (event) =>
                  event.type == DetectionEventType.detected ||
                  event.type == DetectionEventType.changed,
            )
            .toList()
          ..sort(
            (first, second) => config
                .ruleFor(first.detection.className)
                .priority
                .compareTo(config.ruleFor(second.detection.className).priority),
          );
    if (candidates.isEmpty) return null;

    final selected = candidates.first;
    final className = selected.detection.className;
    final cooldown = config.ruleFor(className).voiceCooldown;
    final lastSpokenAt = _lastSpokenAtByClass[className];
    if (lastSpokenAt != null &&
        selected.timestamp.difference(lastSpokenAt) < cooldown) {
      return null;
    }

    final generation = _sessionGeneration;
    _isSpeaking = true;
    try {
      await _speakClassName(className);
      if (generation == _sessionGeneration) {
        _lastSpokenAtByClass[className] = selected.timestamp;
      }
      return selected;
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
