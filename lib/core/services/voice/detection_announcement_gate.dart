/// Prevents repeating the same alert while allowing a changed signal through.
final class DetectionAnnouncementGate {
  String? _lastClassName;
  DateTime? _lastAnnouncedAt;
  String? _pendingClassName;
  int _pendingFrames = 0;

  bool shouldAnnounce(String className, DateTime now, {int requiredFrames = 2}) {
    if (_pendingClassName == className) {
      _pendingFrames += 1;
    } else {
      _pendingClassName = className;
      _pendingFrames = 1;
    }
    if (_pendingFrames < requiredFrames) return false;
    if (_lastClassName != className || _lastAnnouncedAt == null) return true;
    return now.difference(_lastAnnouncedAt!).inSeconds >= 3;
  }

  void record(String className, DateTime now) {
    _lastClassName = className;
    _lastAnnouncedAt = now;
  }
}
