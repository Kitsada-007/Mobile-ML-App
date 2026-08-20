import 'dart:async';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trffic_ilght_app/core/services/voice/traffic_voice_service.dart';

/// เจ้าของค่าการตั้งค่าทั้งแอป (บันทึกลง SharedPreferences และแจ้ง UI)
///
/// ค่าที่ตั้งจากหน้านี้ต้องมีผลทันทีโดยไม่ต้องรีสตาร์ทแอป จึงต้องส่งต่อให้ผู้ใช้ค่าจริง ๆ ด้วย
/// - ค่าเสียง: push เข้า [TrafficVoiceService] ตัวที่ทั้งแอปใช้ร่วมกัน (ผ่าน [voiceService])
/// - ค่า threshold: หน้ากล้องเป็นผู้ฟัง notifyListeners แล้วส่งต่อให้ YOLO ฝั่ง native
class SettingsProvider extends ChangeNotifier {
  bool _isLightMode = true;
  bool _isVoiceEnabled = true;

  /// ค่าเริ่มต้นเป็น false เพราะกรอบที่ native วาดมาจากผลดิบรายเฟรม (threshold ≤ 0.25)
  /// ไม่ใช่ผลที่ผ่านการยืนยันแล้ว จึงขึ้นกรอบทั้งที่ยังไม่มีเสียงเตือน ทำให้คนขับสับสน
  /// เปิดไว้ใช้ตอนทดสอบ/สาธิตว่าโมเดลกำลังเห็นอะไรอยู่
  bool _showDetectionOverlay = false;
  double _iouThreshold = 0.45;

  /// จำนวนเฟรมต่อเนื่องที่ต้องเห็น off_light ก่อนจะยืนยันว่าไฟเสีย (ใช้กับโหมดกล้อง)
  /// 30 เฟรม ≈ 3 วินาทีที่ 10fps
  int _offLightMinimumFrames = 30;
  double _confidenceThreshold = 0.5;
  int _numItemsThreshold = 11;
  double _ttsVolume = 1.0;
  double _ttsSpeed = 0.6;
  double _ttsPitch = 1.0;

  bool get isLightMode => _isLightMode;
  bool get isVoiceEnabled => _isVoiceEnabled;
  bool get showDetectionOverlay => _showDetectionOverlay;
  double get iouThreshold => _iouThreshold;
  int get offLightMinimumFrames => _offLightMinimumFrames;
  double get confidenceThreshold => _confidenceThreshold;
  int get numItemsThreshold => _numItemsThreshold;
  double get ttsVolume => _ttsVolume;
  double get ttsSpeed => _ttsSpeed;
  double get ttsPitch => _ttsPitch;

  /// [voiceService] เป็น optional เพราะเทสต์ที่สนใจแค่ค่าที่บันทึกไว้
  /// ไม่จำเป็นต้องมี TTS จริง ๆ (ถ้าเป็น null จะข้ามการส่งค่าเสียงไปเฉย ๆ)
  SettingsProvider({TrafficVoiceService? voiceService}) {
    _voiceService = voiceService;
    unawaited(_loadSettings());
  }

  TrafficVoiceService? _voiceService;

  Future<void> _loadSettings() async {
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (error, stackTrace) {
      // อ่านค่าที่บันทึกไว้ไม่ได้ ให้ใช้ค่าเริ่มต้นที่ประกาศไว้ด้านบนต่อไป
      log(
        'อ่านการตั้งค่าจาก SharedPreferences ไม่สำเร็จ: $error',
        stackTrace: stackTrace,
      );
      _applyVoiceSettings();
      notifyListeners();
      return;
    }

    // ค่าที่ยังไม่เคยถูกบันทึกจะได้ null กลับมา จึงต้องเทียบกับค่าเริ่มต้นทีละตัว
    final storedIsLightMode = prefs.getBool('isLightMode');
    if (storedIsLightMode == null) {
      _isLightMode = true;
    } else {
      _isLightMode = storedIsLightMode;
    }

    final storedIsVoiceEnabled = prefs.getBool('isVoiceEnabled');
    if (storedIsVoiceEnabled == null) {
      _isVoiceEnabled = true;
    } else {
      _isVoiceEnabled = storedIsVoiceEnabled;
    }

    final storedShowDetectionOverlay = prefs.getBool('showDetectionOverlay');
    if (storedShowDetectionOverlay == null) {
      _showDetectionOverlay = false;
    } else {
      _showDetectionOverlay = storedShowDetectionOverlay;
    }

    final storedOffLightMinimumFrames = prefs.getInt('offLightMinimumFrames');
    if (storedOffLightMinimumFrames == null) {
      _offLightMinimumFrames = 30;
    } else {
      _offLightMinimumFrames = storedOffLightMinimumFrames;
    }

    final storedIouThreshold = prefs.getDouble('iouThreshold');
    if (storedIouThreshold == null) {
      _iouThreshold = 0.45;
    } else {
      _iouThreshold = storedIouThreshold;
    }

    final storedConfidenceThreshold = prefs.getDouble('confidenceThreshold');
    if (storedConfidenceThreshold == null) {
      _confidenceThreshold = 0.5;
    } else {
      _confidenceThreshold = storedConfidenceThreshold;
    }

    final storedNumItemsThreshold = prefs.getInt('numItemsThreshold');
    if (storedNumItemsThreshold == null) {
      _numItemsThreshold = 11;
    } else {
      _numItemsThreshold = storedNumItemsThreshold;
    }

    final storedTtsVolume = prefs.getDouble('ttsVolume');
    if (storedTtsVolume == null) {
      _ttsVolume = 1.0;
    } else {
      _ttsVolume = storedTtsVolume;
    }

    final storedTtsSpeed = prefs.getDouble('ttsSpeed');
    if (storedTtsSpeed == null) {
      _ttsSpeed = 0.6;
    } else {
      _ttsSpeed = storedTtsSpeed;
    }

    final storedTtsPitch = prefs.getDouble('ttsPitch');
    if (storedTtsPitch == null) {
      _ttsPitch = 1.0;
    } else {
      _ttsPitch = storedTtsPitch;
    }

    _applyVoiceSettings();
    notifyListeners();
  }

  /// ส่งค่าเสียงชุดปัจจุบันให้ TTS ใช้ทันที
  /// (ไม่ await เพราะผู้เรียกเป็น setter ที่ต้อง notifyListeners ต่อทันที
  /// และ applySettings ตั้งค่าลงฟิลด์ของ service ให้ตั้งแต่บรรทัดแรกแบบ synchronous แล้ว)
  void _applyVoiceSettings() {
    final voiceService = _voiceService;
    if (voiceService == null) {
      return;
    }
    unawaited(
      voiceService.applySettings(
        isEnabled: _isVoiceEnabled,
        volume: _ttsVolume,
        speed: _ttsSpeed,
        pitch: _ttsPitch,
      ),
    );
  }

  /// เล่นเสียงตัวอย่างด้วยค่าปัจจุบัน (ปุ่ม "ทดลองฟังเสียงพูดแจ้งเตือน")
  /// stop() ก่อนเสมอ เพื่อให้กดซ้ำแล้วได้ยินค่าใหม่ทันที ไม่ติดกลไกกันพูดซ้ำ
  Future<void> previewVoice() async {
    final voiceService = _voiceService;
    if (voiceService == null) {
      return;
    }
    try {
      await voiceService.stop();
      await voiceService.speak('ทดสอบการแจ้งเตือนสัญญาณไฟจราจร');
    } catch (error, stackTrace) {
      log('เล่นเสียงตัวอย่างไม่สำเร็จ: $error', stackTrace: stackTrace);
    }
  }

  Future<void> toggleTheme(bool value) async {
    _isLightMode = value;
    notifyListeners();
    await _saveBool('isLightMode', value);
  }

  Future<void> toggleVoice(bool value) async {
    _isVoiceEnabled = value;
    _applyVoiceSettings();
    notifyListeners();
    await _saveBool('isVoiceEnabled', value);
  }

  /// เปิด/ปิดการวาดกรอบตรวจจับบนภาพกล้อง (หน้ากล้องเป็นผู้ส่งต่อให้ YOLO ฝั่ง native)
  Future<void> toggleDetectionOverlay(bool value) async {
    _showDetectionOverlay = value;
    notifyListeners();
    await _saveBool('showDetectionOverlay', value);
  }

  /// ปรับเกณฑ์ยืนยันไฟเสีย (ยิ่งน้อยยิ่งไว แต่เสี่ยงรายงานไฟที่กะพริบว่าเสีย)
  Future<void> setOffLightMinimumFrames(int value) async {
    _offLightMinimumFrames = value;
    notifyListeners();
    await _saveInt('offLightMinimumFrames', value);
  }

  Future<void> setIouThreshold(double value) async {
    _iouThreshold = value;
    notifyListeners();
    await _saveDouble('iouThreshold', value);
  }

  Future<void> setConfidenceThreshold(double value) async {
    _confidenceThreshold = value;
    notifyListeners();
    await _saveDouble('confidenceThreshold', value);
  }

  Future<void> setNumItemsThreshold(int value) async {
    _numItemsThreshold = value;
    notifyListeners();
    await _saveInt('numItemsThreshold', value);
  }

  Future<void> setTtsVolume(double value) async {
    _ttsVolume = value;
    _applyVoiceSettings();
    notifyListeners();
    await _saveDouble('ttsVolume', value);
  }

  Future<void> setTtsSpeed(double value) async {
    _ttsSpeed = value;
    _applyVoiceSettings();
    notifyListeners();
    await _saveDouble('ttsSpeed', value);
  }

  Future<void> setTtsPitch(double value) async {
    _ttsPitch = value;
    _applyVoiceSettings();
    notifyListeners();
    await _saveDouble('ttsPitch', value);
  }

  Future<void> resetThresholds() async {
    _iouThreshold = 0.45;
    _confidenceThreshold = 0.5;
    _numItemsThreshold = 11;
    _offLightMinimumFrames = 30;
    _ttsVolume = 1.0;
    _ttsSpeed = 0.6;
    _ttsPitch = 1.0;
    _applyVoiceSettings();
    notifyListeners();
    await _saveDouble('iouThreshold', 0.45);
    await _saveInt('offLightMinimumFrames', 30);
    await _saveDouble('confidenceThreshold', 0.5);
    await _saveInt('numItemsThreshold', 11);
    await _saveDouble('ttsVolume', 1.0);
    await _saveDouble('ttsSpeed', 0.6);
    await _saveDouble('ttsPitch', 1.0);
  }

  // การบันทึกอาจล้มเหลวได้ (storage เต็ม/plugin ไม่พร้อม) แต่ค่าที่อยู่ในหน่วยความจำ
  // เปลี่ยนไปแล้ว ผู้ใช้จึงยังได้ผลในรอบนี้ เพียงแต่จะไม่ถูกจำไว้รอบหน้า
  Future<void> _saveBool(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (error, stackTrace) {
      log('บันทึกค่า $key ไม่สำเร็จ: $error', stackTrace: stackTrace);
    }
  }

  Future<void> _saveDouble(String key, double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(key, value);
    } catch (error, stackTrace) {
      log('บันทึกค่า $key ไม่สำเร็จ: $error', stackTrace: stackTrace);
    }
  }

  Future<void> _saveInt(String key, int value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, value);
    } catch (error, stackTrace) {
      log('บันทึกค่า $key ไม่สำเร็จ: $error', stackTrace: stackTrace);
    }
  }
}
