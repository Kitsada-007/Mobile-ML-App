import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trffic_ilght_app/core/services/voice/traffic_voice_service.dart';

/// เทสต์ชุดนี้ดักคำสั่งที่ถูกส่งออก plugin channel ของ flutter_tts
/// เพื่อพิสูจน์ว่า "ค่าที่ผู้ใช้ตั้ง" ถูกส่งถึง engine จริง ไม่ใช่แค่เก็บไว้ในตัวแปร
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_tts');
  final invokedCalls = <MethodCall>[];

  setUp(() {
    invokedCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          invokedCalls.add(call);
          return 1;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  List<MethodCall> callsOf(String method) {
    return invokedCalls.where((call) => call.method == method).toList();
  }

  test('ตั้งภาษาไทยและใช้ค่าที่บันทึกไว้ตั้งแต่ตอนสร้าง service', () async {
    SharedPreferences.setMockInitialValues({
      'ttsVolume': 0.4,
      'ttsSpeed': 0.9,
      'ttsPitch': 1.2,
    });

    final service = TrafficVoiceService();
    await service.ready;

    expect(callsOf('setLanguage').single.arguments, 'th-TH');
    expect(callsOf('setSpeechRate').single.arguments, 0.9);
    expect(callsOf('setVolume').single.arguments, 0.4);
    expect(callsOf('setPitch').single.arguments, 1.2);
  });

  test('ค่าเริ่มต้นความเร็วเสียงต้องตรงกับ SettingsProvider (0.6)', () async {
    SharedPreferences.setMockInitialValues({});

    final service = TrafficVoiceService();
    await service.ready;

    expect(callsOf('setSpeechRate').single.arguments, 0.6);
  });

  test(
    'applySettings ส่งค่าใหม่ถึง engine โดยไม่ต้องสร้าง service ใหม่',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = TrafficVoiceService();
      await service.ready;

      await service.applySettings(
        isEnabled: true,
        volume: 0.3,
        speed: 0.5,
        pitch: 0.8,
      );

      expect(callsOf('setVolume').last.arguments, 0.3);
      expect(callsOf('setSpeechRate').last.arguments, 0.5);
      expect(callsOf('setPitch').last.arguments, 0.8);
      expect(service.isEnabled, true);
    },
  );

  test('applySettings(false) หยุดเสียงที่ค้างอยู่ทันที', () async {
    SharedPreferences.setMockInitialValues({});
    final service = TrafficVoiceService();
    await service.ready;

    await service.applySettings(
      isEnabled: false,
      volume: 1.0,
      speed: 0.6,
      pitch: 1.0,
    );

    expect(service.isEnabled, false);
    expect(callsOf('stop'), isNotEmpty);
  });

  test('ค่าที่ push เข้ามาระหว่างที่ยังโหลดค่าเก่าอยู่ต้องไม่ถูกทับ', () async {
    // เคสจริง: SettingsProvider โหลดเสร็จ/ผู้ใช้เลื่อนสไลเดอร์ ก่อนที่ _initTts จะอ่าน prefs เสร็จ
    SharedPreferences.setMockInitialValues({'ttsSpeed': 0.9});
    final service = TrafficVoiceService();

    final applied = service.applySettings(
      isEnabled: true,
      volume: 1.0,
      speed: 0.4,
      pitch: 1.0,
    );
    await applied;
    await service.ready;

    expect(callsOf('setSpeechRate').last.arguments, 0.4);
  });

  test('speak รอให้ตั้งค่าภาษาเสร็จก่อนเสมอ', () async {
    SharedPreferences.setMockInitialValues({});
    final service = TrafficVoiceService();

    // ไม่ await ready ก่อน เพื่อจำลองการกดปุ่มทดลองฟังเสียงทันทีที่ service ถูกสร้าง
    await service.speak('ทดสอบ');

    final methodOrder = invokedCalls.map((call) => call.method).toList();
    expect(methodOrder, contains('speak'));
    expect(
      methodOrder.indexOf('setLanguage'),
      lessThan(methodOrder.indexOf('speak')),
    );
  });

  test('ปิดเสียงแล้วต้องไม่สั่งพูด', () async {
    SharedPreferences.setMockInitialValues({'isVoiceEnabled': false});
    final service = TrafficVoiceService();
    await service.ready;

    await service.speak('ทดสอบ');

    expect(callsOf('speak'), isEmpty);
  });
}
