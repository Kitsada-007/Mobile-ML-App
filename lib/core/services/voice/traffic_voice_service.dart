import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrafficVoiceService {
  final FlutterTts _tts = FlutterTts();

  DateTime _lastSpeakTime = DateTime.now();

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
      await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
        IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      ]);
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

  /// เปิด/ปิดเสียงประกาศ (ปิดแล้วจะหยุดการพูดที่ค้างอยู่ด้วย)
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

  /// พูดข้อความภาษาไทยผ่าน TTS (มีกันสั่งซ้ำและกันขัดจังหวะถี่เกินไป)
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

  // สำหรับเสียงพูดเตือนและข้อความแจ้งเตือน (คืน "" ถ้าไม่มีเสียงสำหรับคลาสนี้)
  String getThaiMessage(String className) {
    switch (className) {
      case 'dont_go_straight_arrow':
        return "ห้ามตรงไป";
      case 'dont_turn_left':
        return "ห้ามเลี้ยวซ้าย";
      case 'dont_turn_right':
        return "ห้ามเลี้ยวขวา";
      // สถานะสังเคราะห์ไฟกะพริบจาก DetectionStabilizer (ไม่ใช่คลาสโมเดล)
      case 'flashing_red':
        return "ไฟแดงกะพริบ หยุดก่อน แล้วไปเมื่อปลอดภัย";
      case 'flashing_yellow':
        return "ไฟเหลืองกะพริบ ชะลอความเร็ว ระวังทางแยก";
      case 'go_straight_arrow':
        return "ตรงไปได้";
      case 'green_light_circle':
        return "ไฟเขียว ไปได้";
      case 'off_light':
        return "ระวัง สัญญาณไฟเสีย";
      case 'red_light_circle':
        return "ไฟแดง หยุดรถ";
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

  /// หยุดการพูดทันทีและล้างสถานะ (ใช้เมื่อสลับกล้อง/ปิดเสียง)
  Future<void> stop() async {
    _isSpeaking = false;
    _lastSpokenMessage = null;
    await _tts.stop();
  }
}
