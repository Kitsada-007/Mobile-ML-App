import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trffic_ilght_app/core/utils/thai_number_helper.dart';

class TrafficVoiceService {
  final FlutterTts _tts = FlutterTts();

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

    try {
      final prefs = await SharedPreferences.getInstance();
      final double volume = prefs.getDouble('ttsVolume') ?? 1.0;
      final double speed = prefs.getDouble('ttsSpeed') ?? 0.6;
      final double pitch = prefs.getDouble('ttsPitch') ?? 1.0;

      await _tts.setVolume(volume);
      await _tts.setSpeechRate(speed);
      await _tts.setPitch(pitch);
    } catch (_) {}

    _lastSpeakTime = DateTime.now();
    await _tts.stop();
    await _tts.speak(message);
  }

  Future<void> speakNumber(String number) async {
    if (!_isEnabled) return;
    final prefs = await SharedPreferences.getInstance();
    final isVoiceEnabled = prefs.getBool('isVoiceEnabled') ?? true;
    if (!isVoiceEnabled) return;

    final int? val = int.tryParse(number);
    if (val == null) return;

    if (shouldPrepareToGo(val)) {
      await speak("เตรียมตัวไป");
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
  }) async {
    if (!_isEnabled) return;
    if (confidence < 0.40) return;

    // หากพูด "เตรียมตัวไป" แล้ว ไม่ต้องร้องเตือน "ไฟแดง หยุดรถ" หรือสัญญาณไฟอีกในรอบนี้
    if (hasSpokenGetReady) return;

    final prefs = await SharedPreferences.getInstance();
    final isVoiceEnabled = prefs.getBool('isVoiceEnabled') ?? true;
    if (!isVoiceEnabled) return;
    final String message = getThaiMessage(className);
    if (message.isEmpty) return;

    final now = DateTime.now();
    // ถ้ามี sign_number อยู่ในภาพเดียวกัน ขยาย cooldown เสียงเตือนไฟจราจรจาก 3 วินาที เป็น 8 วินาที เพื่อไม่ให้พูดถี่เกินไป
    final cooldown = isSignActive ? 8 : 3;
    if (now.difference(_lastSpeakTime).inSeconds >= cooldown) {
      await speak(message);
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
    await _tts.stop();
  }
}
