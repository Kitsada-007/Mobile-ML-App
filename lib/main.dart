import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trffic_ilght_app/app/app.dart';
import 'package:trffic_ilght_app/core/services/model_management/remote_model_update_bootstrap.dart';
import 'package:trffic_ilght_app/features/settings/settings.dart';

export 'package:trffic_ilght_app/app/app.dart' show MyApp;

/// จุดเริ่มต้นของแอปพลิเคชัน (Composition Root)
/// - ตั้งค่า Provider สำหรับ SettingsProvider (state การตั้งค่าทั่วแอป)
/// - เรียก RemoteModelUpdateBootstrap.checkOnce() แบบ fire-and-forget
///   เพื่อตรวจสอบอัปเดตโมเดลจาก GitHub Releases ทุกครั้งที่เปิดแอป
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => SettingsProvider())],
      child: const MyApp(),
    ),
  );
  unawaited(RemoteModelUpdateBootstrap.checkOnce());
}
