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
    final String message = getThaiMessage(className);
    if (message.isEmpty) return;

    final now = DateTime.now();
    if (now.difference(_lastSpeakTime).inSeconds >= 3) {
      await speak(message);
      _lastSpokenClass = className;
      _lastSpeakTime = now;
    }
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
        return "ป้ายตัวเลข";
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
        return "พบป้ายตัวเลข";
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
    await _tts.stop();
  }
}
