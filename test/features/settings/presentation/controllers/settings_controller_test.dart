import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trffic_ilght_app/core/services/voice/traffic_voice_service.dart';
import 'package:trffic_ilght_app/features/settings/presentation/controllers/settings_controller.dart';

/// TrafficVoiceService ปลอม: บันทึกค่าที่ถูก push เข้ามาไว้ตรวจสอบ
class RecordingVoiceService implements TrafficVoiceService {
  bool isEnabledValue = true;
  double volume = 1.0;
  double speed = 0.6;
  double pitch = 1.0;
  int applyCallCount = 0;
  int stopCallCount = 0;
  final List<String> spokenMessages = [];

  @override
  bool get isEnabled => isEnabledValue;

  @override
  Future<void> get ready async {}

  @override
  Future<void> applySettings({
    required bool isEnabled,
    required double volume,
    required double speed,
    required double pitch,
  }) async {
    applyCallCount = applyCallCount + 1;
    isEnabledValue = isEnabled;
    this.volume = volume;
    this.speed = speed;
    this.pitch = pitch;
  }

  @override
  Future<void> setEnabled(bool value) async {
    isEnabledValue = value;
  }

  @override
  Future<void> reloadSettings() async {}

  @override
  Future<void> speak(String message) async {
    spokenMessages.add(message);
  }

  @override
  String getThaiMessage(String className) => className;

  @override
  Future<void> stop() async {
    stopCallCount = stopCallCount + 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ส่งค่าที่บันทึกไว้ให้ TTS ตั้งแต่ตอนโหลดค่าเริ่มต้น', () async {
    SharedPreferences.setMockInitialValues({
      'ttsVolume': 0.2,
      'ttsSpeed': 0.5,
      'ttsPitch': 1.4,
    });
    final voiceService = RecordingVoiceService();

    final provider = SettingsProvider(voiceService: voiceService);
    await Future<void>.delayed(Duration.zero); // รอ _loadSettings

    expect(voiceService.volume, 0.2);
    expect(voiceService.speed, 0.5);
    expect(voiceService.pitch, 1.4);
    provider.dispose();
  });

  test('เลื่อนสไลเดอร์เสียงแล้วต้องถึง TTS ทันที ไม่ต้องรีสตาร์ทแอป', () async {
    SharedPreferences.setMockInitialValues({});
    final voiceService = RecordingVoiceService();
    final provider = SettingsProvider(voiceService: voiceService);
    await Future<void>.delayed(Duration.zero);

    await provider.setTtsVolume(0.3);
    await provider.setTtsSpeed(0.8);
    await provider.setTtsPitch(0.7);

    expect(voiceService.volume, 0.3);
    expect(voiceService.speed, 0.8);
    expect(voiceService.pitch, 0.7);
    provider.dispose();
  });

  test('ปิดเสียงในหน้า Settings แล้ว TTS ต้องถูกปิดทันที', () async {
    SharedPreferences.setMockInitialValues({});
    final voiceService = RecordingVoiceService();
    final provider = SettingsProvider(voiceService: voiceService);
    await Future<void>.delayed(Duration.zero);

    await provider.toggleVoice(false);

    expect(provider.isVoiceEnabled, false);
    expect(voiceService.isEnabled, false);
    provider.dispose();
  });

  test('กรอบตรวจจับปิดไว้เป็นค่าเริ่มต้น และสลับแล้วถูกบันทึก', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);

    expect(provider.showDetectionOverlay, isFalse);

    await provider.toggleDetectionOverlay(true);
    expect(provider.showDetectionOverlay, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('showDetectionOverlay'), isTrue);
    provider.dispose();
  });

  test('ค่าที่บันทึกไว้ถูกอ่านกลับมาตอนเปิดแอป', () async {
    SharedPreferences.setMockInitialValues({'showDetectionOverlay': true});
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);

    expect(provider.showDetectionOverlay, isTrue);
    provider.dispose();
  });

  test('ค่าที่ตั้งถูกบันทึกลง SharedPreferences ด้วย', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = SettingsProvider();
    await Future<void>.delayed(Duration.zero);

    await provider.setIouThreshold(0.7);
    await provider.setConfidenceThreshold(0.6);
    await provider.setNumItemsThreshold(20);
    await provider.setTtsSpeed(0.4);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('iouThreshold'), 0.7);
    expect(prefs.getDouble('confidenceThreshold'), 0.6);
    expect(prefs.getInt('numItemsThreshold'), 20);
    expect(prefs.getDouble('ttsSpeed'), 0.4);
    provider.dispose();
  });

  test(
    'แจ้ง listener ก่อน แล้วค่อยบันทึก (หน้ากล้องจึงได้ค่าใหม่ทันที)',
    () async {
      SharedPreferences.setMockInitialValues({});
      final provider = SettingsProvider();
      await Future<void>.delayed(Duration.zero);

      double? seenIouThreshold;
      provider.addListener(() {
        seenIouThreshold = provider.iouThreshold;
      });

      final pending = provider.setIouThreshold(0.75);
      expect(seenIouThreshold, 0.75); // ต้องเห็นค่าใหม่ก่อนที่การบันทึกจะเสร็จ
      await pending;
      provider.dispose();
    },
  );

  test('resetThresholds คืนค่าเสียงกลับเป็นค่าเริ่มต้นให้ TTS ด้วย', () async {
    SharedPreferences.setMockInitialValues({});
    final voiceService = RecordingVoiceService();
    final provider = SettingsProvider(voiceService: voiceService);
    await Future<void>.delayed(Duration.zero);

    await provider.setTtsVolume(0.1);
    await provider.setTtsSpeed(0.4);
    await provider.resetThresholds();

    expect(voiceService.volume, 1.0);
    expect(voiceService.speed, 0.6);
    expect(voiceService.pitch, 1.0);
    provider.dispose();
  });

  test('previewVoice เล่นเสียงผ่าน service ตัวเดียวกับที่แอปใช้', () async {
    SharedPreferences.setMockInitialValues({});
    final voiceService = RecordingVoiceService();
    final provider = SettingsProvider(voiceService: voiceService);
    await Future<void>.delayed(Duration.zero);

    await provider.previewVoice();

    expect(voiceService.stopCallCount, 1);
    expect(voiceService.spokenMessages, hasLength(1));
    provider.dispose();
  });

  test(
    'ไม่มี voice service ก็ต้องไม่พัง (เช่นในเทสต์ที่ไม่ได้ใช้เสียง)',
    () async {
      SharedPreferences.setMockInitialValues({});
      final provider = SettingsProvider();
      await Future<void>.delayed(Duration.zero);

      await provider.toggleVoice(false);
      await provider.previewVoice();

      expect(provider.isVoiceEnabled, false);
      provider.dispose();
    },
  );
}
