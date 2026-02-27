import 'package:flutter_tts/flutter_tts.dart';

class TrafficVoiceService {
  final FlutterTts _tts = FlutterTts();

  String? _lastSpokenClass;
  DateTime _lastSpeakTime = DateTime.now();

  TrafficVoiceService() {
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage("th-TH");
    await _tts.setSpeechRate(0.6);
    await _tts.setPitch(1.0);
  }

  /// 🔊 ฟังก์ชันใหม่: รับข้อความ String โดยตรง (สำหรับอ่านเลข 5, 4, 3, 2, 1)
  Future<void> speak(String message) async {
    if (message.isEmpty) return;

    // หยุดเสียงที่กำลังพูดอยู่ทันที เพื่อพูดตัวเลขปัจจุบัน (สำคัญมากสำหรับการนับถอยหลัง)
    await _tts.stop();
    await _tts.speak(message);
  }

  Future<void> processDetection(String className, double confidence) async {
    if (confidence < 0.65) return;

    String message = _getThaiMessage(className);
    if (message.isEmpty) return;

    final now = DateTime.now();

    if (className != _lastSpokenClass ||
        now.difference(_lastSpeakTime).inSeconds > 3) {
      await speak(message);
      _lastSpokenClass = className;
      _lastSpeakTime = now;
    }
  }

  String _getThaiMessage(String className) {
    switch (className) {
      case 'turn_left':
        return "เลี้ยวซ้ายได้";
      case 'turn_right':
        return "เลี้ยวขวาได้";
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
      case 'green_light_circle':
        return "ไฟเขียว ไปได้";
      case 'off_light':
        return "ระวัง สัญญาณไฟเสีย";
      case 'flashing_light':
        return "ไฟกระพริบ โปรดระวัง";
      default:
        return "";
    }
  }

  void stop() => _tts.stop();
}
