import 'dart:developer';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrafficVoiceService {
  final FlutterTts _tts = FlutterTts();

  DateTime _lastSpeakTime = DateTime.now();

  bool _isEnabled = true;
  bool _isSpeaking = false;
  String? _lastSpokenMessage;

  double _volume = 1.0;
  // ค่าเริ่มต้นต้องตรงกับ SettingsProvider ไม่งั้นผู้ใช้ที่ยังไม่เคยแตะสไลเดอร์
  // จะเห็นค่าในหน้า Settings เป็นอีกค่าหนึ่งแต่ได้ยินเสียงอีกความเร็วหนึ่ง
  double _speed = 0.6;
  double _pitch = 1.0;

  /// true เมื่อมีการ push ค่าจากหน้า Settings เข้ามาแล้ว
  /// ใช้กัน reloadSettings() อ่านค่าเก่าจาก SharedPreferences มาทับค่าที่เพิ่งตั้ง
  bool _hasExternalSettings = false;

  /// งานตั้งค่า TTS ตอนสร้างวัตถุ (ภาษา/ระดับเสียง/handler)
  /// เก็บไว้ให้ speak() รอได้ ไม่ให้พูดตั้งแต่ยังตั้งค่าไม่เสร็จ
  late final Future<void> _initialization;

  TrafficVoiceService() {
    _initialization = _initTts();
  }

  /// รอให้การตั้งค่า TTS ตอนเริ่มต้นเสร็จก่อน (ใช้ในเทสต์และผู้เรียกที่ต้องการความแน่นอน)
  Future<void> get ready => _initialization;

  Future<void> _initTts() async {
    await reloadSettings();

    // ทุกคำสั่งด้านล่างวิ่งผ่าน plugin channel จึงพังได้ ต้องไม่ปล่อย error หลุด
    // ออกไปนอก _initialization เพราะ speak() รอ future ตัวนี้อยู่
    try {
      await _tts.setLanguage("th-TH");
      await _tts.setSpeechRate(_speed);
      await _tts.setPitch(_pitch);
      await _tts.setVolume(_volume);
      await _tts.awaitSpeakCompletion(true);
    } catch (error, stackTrace) {
      log('ตั้งค่า TTS เริ่มต้นไม่สำเร็จ: $error', stackTrace: stackTrace);
    }

    try {
      await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
        IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      ]);
    } catch (error, stackTrace) {
      // ตั้งค่า audio category ได้เฉพาะบน iOS แพลตฟอร์มอื่นจะโยน error ตรงนี้เสมอ
      // จึงไม่ถือเป็นความผิดพลาดร้ายแรง แค่บันทึกไว้ให้รู้ว่าพังตรงไหน
      log(
        'ตั้งค่า iOS audio category ไม่สำเร็จ: $error',
        stackTrace: stackTrace,
      );
    }

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
    // หน้า Settings เป็นเจ้าของค่าเหล่านี้แล้ว การอ่านซ้ำจะเป็นการย้อนค่ากลับ
    if (_hasExternalSettings) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      // เช็คซ้ำหลัง await: ระหว่างรออ่านค่า หน้า Settings อาจ push ค่าใหม่เข้ามาแล้ว
      // ถ้าเขียนทับตรงนี้ ค่าที่ผู้ใช้เพิ่งเลือกจะถูกย้อนกลับเป็นค่าเก่าที่บันทึกไว้
      if (_hasExternalSettings) {
        return;
      }

      final savedIsEnabled = prefs.getBool('isVoiceEnabled');
      if (savedIsEnabled == null) {
        _isEnabled = true;
      } else {
        _isEnabled = savedIsEnabled;
      }

      final savedVolume = prefs.getDouble('ttsVolume');
      if (savedVolume == null) {
        _volume = 1.0;
      } else {
        _volume = savedVolume;
      }

      final savedSpeed = prefs.getDouble('ttsSpeed');
      if (savedSpeed == null) {
        _speed = 0.6;
      } else {
        _speed = savedSpeed;
      }

      final savedPitch = prefs.getDouble('ttsPitch');
      if (savedPitch == null) {
        _pitch = 1.0;
      } else {
        _pitch = savedPitch;
      }
    } catch (error, stackTrace) {
      // อ่านค่าที่บันทึกไว้ไม่ได้ ให้ใช้ค่าที่ถืออยู่เดิมต่อไปแทนการล้มทั้งบริการเสียง
      log(
        'อ่านการตั้งค่าเสียงจาก SharedPreferences ไม่สำเร็จ: $error',
        stackTrace: stackTrace,
      );
    }
  }

  /// เปิด/ปิดเสียงประกาศ (ปิดแล้วจะหยุดการพูดที่ค้างอยู่ด้วย)
  Future<void> setEnabled(bool value) async {
    _isEnabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isVoiceEnabled', value);
    } catch (error, stackTrace) {
      // บันทึกค่าไม่ได้ แต่ _isEnabled ในหน่วยความจำเปลี่ยนแล้ว
      // ผู้ใช้จึงยังได้ผลทันทีในรอบนี้ เพียงแต่จะไม่ถูกจำไว้รอบหน้า
      log('บันทึกสถานะเปิด/ปิดเสียงไม่สำเร็จ: $error', stackTrace: stackTrace);
    }
    if (!value) {
      await stop();
    }
  }

  bool get isEnabled => _isEnabled;

  /// รับค่าจากหน้า Settings มาใช้กับ engine ทันที โดยไม่ต้องรีสตาร์ทแอป
  /// - ตั้งค่าลงฟิลด์แบบ synchronous ก่อน เพื่อให้ UI ที่อ่าน isEnabled เห็นค่าใหม่ทันที
  /// - ไม่บันทึกลง SharedPreferences เอง เพราะ SettingsProvider เป็นเจ้าของการบันทึก
  Future<void> applySettings({
    required bool isEnabled,
    required double volume,
    required double speed,
    required double pitch,
  }) async {
    _hasExternalSettings = true;
    _isEnabled = isEnabled;
    _volume = volume;
    _speed = speed;
    _pitch = pitch;

    if (!isEnabled) {
      await stop();
      return;
    }

    // ต้องรอ _initTts ให้จบก่อน ไม่งั้นค่าที่เพิ่งตั้งจะถูกคำสั่งใน _initTts ทับ
    await _initialization;

    try {
      await _tts.setVolume(_volume);
      await _tts.setSpeechRate(_speed);
      await _tts.setPitch(_pitch);
    } catch (error, stackTrace) {
      log(
        'ปรับค่าเสียงตามการตั้งค่าใหม่ไม่สำเร็จ: $error',
        stackTrace: stackTrace,
      );
    }
  }

  /// พูดข้อความภาษาไทยผ่าน TTS (มีกันสั่งซ้ำและกันขัดจังหวะถี่เกินไป)
  Future<void> speak(String message) async {
    if (message.isEmpty) return;

    // รอให้ตั้งค่าภาษา/ระดับเสียงเสร็จก่อน ไม่งั้นข้อความแรก (เช่นปุ่มทดลองฟังเสียง
    // ในหน้า Settings) จะถูกพูดด้วยค่าเริ่มต้นและอาจยังไม่ได้ตั้งภาษาไทย
    await _initialization;

    if (!_isEnabled) return;

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
    } catch (error, stackTrace) {
      // ปรับพารามิเตอร์เสียงไม่สำเร็จ ยังพูดต่อได้ด้วยค่าเดิมของ engine
      log(
        'ตั้งค่าระดับเสียง/ความเร็ว/โทนเสียงก่อนพูดไม่สำเร็จ: $error',
        stackTrace: stackTrace,
      );
    }

    _lastSpeakTime = DateTime.now();
    _lastSpokenMessage = message;
    _isSpeaking = true;

    try {
      await _tts.stop();
      await _tts.speak(message);
    } catch (error, stackTrace) {
      // ต้องปลด _isSpeaking เสมอ ไม่งั้นจะค้างและกันข้อความถัดไปไม่ให้พูดตลอดไป
      log(
        'สั่งพูดข้อความ "$message" ไม่สำเร็จ: $error',
        stackTrace: stackTrace,
      );
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
    try {
      await _tts.stop();
    } catch (error, stackTrace) {
      // ผู้เรียกส่วนใหญ่เรียกแบบ unawaited ถ้าปล่อย error หลุดจะกลายเป็น
      // unhandled async error ทั้งที่สถานะฝั่ง Dart ถูกล้างเรียบร้อยแล้ว
      log('สั่งหยุดเสียงไม่สำเร็จ: $error', stackTrace: stackTrace);
    }
  }
}
