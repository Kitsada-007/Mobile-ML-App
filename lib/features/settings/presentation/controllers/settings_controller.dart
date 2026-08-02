import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  bool _isLightMode = true;
  bool _isVoiceEnabled = true;
  double _iouThreshold = 0.45;
  double _confidenceThreshold = 0.5;
  int _numItemsThreshold = 11;
  double _ttsVolume = 1.0;
  double _ttsSpeed = 0.6;
  double _ttsPitch = 1.0;

  bool get isLightMode => _isLightMode;
  bool get isVoiceEnabled => _isVoiceEnabled;
  double get iouThreshold => _iouThreshold;
  double get confidenceThreshold => _confidenceThreshold;
  int get numItemsThreshold => _numItemsThreshold;
  double get ttsVolume => _ttsVolume;
  double get ttsSpeed => _ttsSpeed;
  double get ttsPitch => _ttsPitch;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isLightMode = prefs.getBool('isLightMode') ?? true;
    _isVoiceEnabled = prefs.getBool('isVoiceEnabled') ?? true;
    _iouThreshold = prefs.getDouble('iouThreshold') ?? 0.45;
    _confidenceThreshold = prefs.getDouble('confidenceThreshold') ?? 0.5;
    _numItemsThreshold = prefs.getInt('numItemsThreshold') ?? 11;
    _ttsVolume = prefs.getDouble('ttsVolume') ?? 1.0;
    _ttsSpeed = prefs.getDouble('ttsSpeed') ?? 0.6;
    _ttsPitch = prefs.getDouble('ttsPitch') ?? 1.0;
    notifyListeners();
  }

  Future<void> toggleTheme(bool value) async {
    _isLightMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLightMode', value);
    notifyListeners();
  }

  Future<void> toggleVoice(bool value) async {
    _isVoiceEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isVoiceEnabled', value);
    notifyListeners();
  }

  Future<void> setIouThreshold(double value) async {
    _iouThreshold = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('iouThreshold', value);
    notifyListeners();
  }

  Future<void> setConfidenceThreshold(double value) async {
    _confidenceThreshold = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('confidenceThreshold', value);
    notifyListeners();
  }

  Future<void> setNumItemsThreshold(int value) async {
    _numItemsThreshold = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('numItemsThreshold', value);
    notifyListeners();
  }

  Future<void> setTtsVolume(double value) async {
    _ttsVolume = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('ttsVolume', value);
    notifyListeners();
  }

  Future<void> setTtsSpeed(double value) async {
    _ttsSpeed = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('ttsSpeed', value);
    notifyListeners();
  }

  Future<void> setTtsPitch(double value) async {
    _ttsPitch = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('ttsPitch', value);
    notifyListeners();
  }

  Future<void> resetThresholds() async {
    _iouThreshold = 0.45;
    _confidenceThreshold = 0.5;
    _numItemsThreshold = 11;
    _ttsVolume = 1.0;
    _ttsSpeed = 0.6;
    _ttsPitch = 1.0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('iouThreshold', 0.45);
    await prefs.setDouble('confidenceThreshold', 0.5);
    await prefs.setInt('numItemsThreshold', 11);
    await prefs.setDouble('ttsVolume', 1.0);
    await prefs.setDouble('ttsSpeed', 0.6);
    await prefs.setDouble('ttsPitch', 1.0);
    notifyListeners();
  }
}
