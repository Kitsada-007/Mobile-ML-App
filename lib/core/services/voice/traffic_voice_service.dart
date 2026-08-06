import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trffic_ilght_app/core/utils/thai_number_helper.dart';
import 'package:trffic_ilght_app/core/services/voice/detection_announcement_gate.dart';

class TrafficVoiceService {
  static const double minVoiceConfidence = 0.40;

  final FlutterTts _tts = FlutterTts();

  DateTime _lastSpeakTime = DateTime.now();
  final DetectionAnnouncementGate _announcementGate =
      DetectionAnnouncementGate();

  bool _isEnabled = true;
  bool _isSpeaking = false;
  String? _lastSpokenMessage;

  double _volume = 1.0;
  double _speed = 0.5;
  double _pitch = 1.0;

  TrafficVoiceService() {
    _initTts();
  }

  Future<void> _initTts() async {
    await reloadSettings();

    await _tts.setLanguage("th-TH");
    await _tts.setSpeechRate(_speed);
    await _tts.setPitch(_pitch);
    await _tts.setVolume(_volume);
    await _tts.awaitSpeakCompletion(true);

    try {
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
      );
    } catch (_) {}

    _tts.setStartHandler(() {
      _isSpeaking = true;
    });

    _tts.setCompletionHandler(() {
      _isSpeaking = false;
    });

    _tts.setCancelHandler(() {
      _isSpeaking = false;
    });

    _tts.setErrorHandler((_) {
      _isSpeaking = false;
    });
  }

  Future<void> reloadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool('isVoiceEnabled') ?? true;
      _volume = prefs.getDouble('ttsVolume') ?? 1.0;
      _speed = prefs.getDouble('ttsSpeed') ?? 0.5;
      _pitch = prefs.getDouble('ttsPitch') ?? 1.0;
    } catch (_) {}
  }

  Future<void> setEnabled(bool value) async {
    _isEnabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isVoiceEnabled', value);
    } catch (_) {}
    if (!value) {
      await stop();
    }
  }

  bool get isEnabled => _isEnabled;

  Future<void> speak(String message) async {
    if (!_isEnabled) return;
    if (message.isEmpty) return;

    // ป้องกันไม่ให้ส่งคำสั่งซ้ำกรณีที่กำลังออกเสียงข้อความเดียวกัน
    if (_isSpeaking && _lastSpokenMessage == message) {
      return;
    }

    // หากกำลังออกเสียงข้อความอื่นอยู่ ให้รออย่างน้อย 1.5 วินาที ก่อนขัดจังหวะ
    if (_isSpeaking &&
        DateTime.now().difference(_lastSpeakTime).inMilliseconds < 1500) {
      return;
    }

    try {
      await _tts.setVolume(_volume);
      await _tts.setSpeechRate(_speed);
      await _tts.setPitch(_pitch);
    } catch (_) {}

    _lastSpeakTime = DateTime.now();
    _lastSpokenMessage = message;
    _isSpeaking = true;

    try {
      await _tts.stop();
      await _tts.speak(message);
    } catch (_) {
      _isSpeaking = false;
    }
  }

  Future<void> speakNumber(String number, {String? activeLightClass}) async {
    if (!_isEnabled) return;

    final int? val = int.tryParse(number);
    if (val == null) return;

    if (shouldPrepareToGo(val)) {
      if (activeLightClass != 'green_light_circle') {
        await speak("เตรียมตัวไป");
      }
    } else {
      final word = convertToThaiWords(val);
      await speak(word);
    }
  }

  Future<void> processDetection(
    String className,
    double confidence, {
    bool isSignActive = false,
    bool hasSpokenGetReady = false,
    bool announceImmediately = false,
  }) async {
    if (!_isEnabled) return;
    if (confidence < minVoiceConfidence) return;

    // หากพูด "เตรียมตัวไป" แล้ว ไม่ต้องร้องเตือนอีกในรอบนี้
    if (hasSpokenGetReady) return;

    final String message = getThaiMessage(className);
    if (message.isEmpty) return;

    final now = DateTime.now();
    // ถ้ามี sign_number อยู่ในภาพเดียวกัน ขยาย cooldown เสียงเตือนไฟจราจรจาก 3 วินาที เป็น 8 วินาที
    final cooldown = isSignActive ? 8 : 3;
    if (!announceImmediately &&
        now.difference(_lastSpeakTime).inSeconds < cooldown) {
      return;
    }
    if (!_announcementGate.shouldAnnounce(
      className,
      now,
      requiredFrames: announceImmediately ? 1 : 2,
    )) {
      return;
    }
    _announcementGate.record(className, now);
    await speak(message);
  }

  // สำหรับแสดงชื่อป้ายทางการบนหน้าจอ
  String getFormalThaiName(String className) {
    switch (className) {
      case 'dont_go_straight_arrow':
        return "ป้ายห้ามตรงไป";
      case 'dont_turn_left':
        return "ป้ายห้ามเลี้ยวซ้าย";
      case 'dont_turn_right':
        return "ป้ายห้ามเลี้ยวขวา";
      case 'go_straight_arrow':
        return "ป้ายบังคับให้ตรงไป";
      case 'green_light_circle':
        return "สัญญาณไฟจราจรสีเขียว";
      case 'off_light':
        return "สัญญาณไฟจราจรขัดข้อง";
      case 'red_light_circle':
        return "สัญญาณไฟจราจรสีแดง";
      case 'sign_number':
        return "สัญญาณไฟนับถอยหลัง";
      case 'turn_left':
        return "สัญญาณไฟเลี้ยวซ้าย";
      case 'turn_right':
        return "สัญญาณไฟเลี้ยวขวา";
      case 'yellow_light':
        return "สัญญาณไฟจราจรสีเหลือง";
      default:
        return className;
    }
  }

  // สำหรับเสียงพูดเตือนและข้อความแจ้งเตือน
  String getThaiMessage(String className) {
    switch (className) {
      case 'dont_go_straight_arrow':
        return "ห้ามตรงไป";
      case 'dont_turn_left':
        return "ห้ามเลี้ยวซ้าย";
      case 'dont_turn_right':
        return "ห้ามเลี้ยวขวา";
      case 'go_straight_arrow':
        return "ตรงไปได้";
      case 'green_light_circle':
        return "ไฟเขียว ไปได้";
      case 'off_light':
        return "ระวัง สัญญาณไฟเสีย";
      case 'red_light_circle':
        return "ไฟแดง หยุดรถ";
      case 'sign_number':
        return "พบสัญญาณไฟนับถอยหลัง";
      case 'turn_left':
        return "เลี้ยวซ้ายได้";
      case 'turn_right':
        return "เลี้ยวขวาได้";
      case 'yellow_light':
        return "ไฟเหลือง เตรียมหยุด";
      default:
        return "";
    }
  }

  Future<void> stop() async {
    _isSpeaking = false;
    _lastSpokenMessage = null;
    await _tts.stop();
  }
}
