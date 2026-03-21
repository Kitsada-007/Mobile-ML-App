import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:trffic_ilght_app/presentation/controllers/settings_controller.dart';
import 'package:trffic_ilght_app/presentation/pages/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => SettingsProvider())],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return GetMaterialApp(
      title: 'Traffic Light App',
      theme: settings.isLightMode ? ThemeData.light() : ThemeData.dark(),
      home: const HomePage(),
    );
  }
}
