import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrafficVoiceService {
  final FlutterTts _tts = FlutterTts();

  String? _lastSpokenClass;
  DateTime _lastSpeakTime = DateTime.now();

  bool _isEnabled = true;

  TrafficVoiceService() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("th-TH");
    await _tts.setSpeechRate(0.6);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
  }

  void setEnabled(bool value) {
    _isEnabled = value;
    if (!value) {
      _tts.stop();
    }
  }

  bool get isEnabled => _isEnabled;

  Future<void> speak(String message) async {
    if (!_isEnabled) return;
    if (message.isEmpty) return;

    await _tts.stop();
    await _tts.speak(message);
  }

  Future<void> processDetection(String className, double confidence) async {
    if (!_isEnabled) return;
    if (confidence < 0.40) return;

    final prefs = await SharedPreferences.getInstance();
    final isVoiceEnabled = prefs.getBool('isVoiceEnabled') ?? true;
    if (!isVoiceEnabled) return;
    final String message = _getThaiMessage(className);
    if (message.isEmpty) return;

    final now = DateTime.now();

    // เช็คแค่ว่าพูดครั้งล่าสุดผ่านไป 3 วินาทีหรือยัง
    // (ตัดเงื่อนไข className != _lastSpokenClass ทิ้ง)
    if (now.difference(_lastSpeakTime).inSeconds >= 3) {
      await speak(message);
      _lastSpokenClass = className; // เก็บไว้เผื่อใช้ทำอย่างอื่น
      _lastSpeakTime = now;
    }
  }

  String _getThaiMessage(String className) {
    switch (className) {
      case 'turn_left':
        return "เลี้ยวซ้ายได้";

      case 'turn_right':
        return "เลี้ยวขวาได้";

      case 'green_light_circle':
      case 'go_straight_arrow':
        return "ตรงไปได้";

      case 'dont_turn_left':
        return "ห้ามเลี้ยวซ้าย";

      case 'dont_turn_right':
        return "ห้ามเลี้ยวขวา";

      case 'red_light_circle':
        return "ไฟแดง หยุดรถ";

      case 'yellow_light':
        return "ไฟเหลือง เตรียมหยุด";

      case 'off_light':
        return "ระวัง สัญญาณไฟเสีย";

      case 'flashing_light':
        return "ไฟกระพริบ โปรดระวัง";

      default:
        return "";
    }
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}
