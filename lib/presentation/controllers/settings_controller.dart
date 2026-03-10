import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  bool _isLightMode = true;
  bool _isVoiceEnabled = true;

  bool get isLightMode => _isLightMode;
  bool get isVoiceEnabled => _isVoiceEnabled;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isLightMode = prefs.getBool('isLightMode') ?? true;
    _isVoiceEnabled = prefs.getBool('isVoiceEnabled') ?? true;
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
}
