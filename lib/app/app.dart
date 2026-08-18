import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:trffic_ilght_app/app/app_shell.dart';
import 'package:trffic_ilght_app/app/theme.dart';
import 'package:trffic_ilght_app/features/settings/settings.dart';

/// Root widget ของแอปพลิเคชัน "Berng Fai" (เบิ้งไฟ - ผู้ช่วยจราจรเรียลไทม์)
/// - ใช้ GetMaterialApp เพื่อรองรับ GetX navigation/snackbar
/// - ใช้ Provider สำหรับ SettingsProvider (theme, voice settings)
/// - รองรับ Light/Dark theme ตามการตั้งค่าของผู้ใช้
/// - initializeCamera: ควบคุมว่าเปิดกล้องทันทีหรือไม่ (ใช้สำหรับ testing)
class MyApp extends StatelessWidget {
  const MyApp({super.key, this.initializeCamera = true});

  final bool initializeCamera;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    ThemeMode themeMode;
    if (settings.isLightMode) {
      themeMode = ThemeMode.light;
    } else {
      themeMode = ThemeMode.dark;
    }

    return GetMaterialApp(
      title: 'Berng Fai',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: MainScreen(initializeCamera: initializeCamera),
    );
  }
}
