import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trffic_ilght_app/app/app.dart';
import 'package:trffic_ilght_app/core/services/model_management/remote_model_update_bootstrap.dart';
import 'package:trffic_ilght_app/core/services/voice/traffic_voice_service.dart';
import 'package:trffic_ilght_app/features/settings/settings.dart';

export 'package:trffic_ilght_app/app/app.dart' show MyApp;

/// จุดเริ่มต้นของแอปพลิเคชัน (Composition Root)
/// - สร้าง TrafficVoiceService ตัวเดียวให้ทั้งแอปใช้ร่วมกัน (ทุกหน้าจึงได้ยินค่าเสียงชุดเดียวกัน
///   และการเปลี่ยนค่าในหน้า Settings มีผลทันทีกับหน้าที่เปิดค้างอยู่)
/// - ตั้งค่า Provider สำหรับ SettingsProvider (state การตั้งค่าทั่วแอป)
/// - เรียก RemoteModelUpdateBootstrap.checkOnce() แบบ fire-and-forget
///   เพื่อตรวจสอบอัปเดตโมเดลจาก GitHub Releases ทุกครั้งที่เปิดแอป
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final voiceService = TrafficVoiceService();
  final settings = SettingsProvider(voiceService: voiceService);

  runApp(
    MultiProvider(
      providers: [
        // ใช้ .value เพราะทั้งสองตัวมีอายุเท่ากับแอป ไม่ต้องให้ Provider สร้าง/ทำลายให้
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        Provider<TrafficVoiceService>.value(value: voiceService),
      ],
      child: const MyApp(),
    ),
  );
  unawaited(RemoteModelUpdateBootstrap.checkOnce());
}
