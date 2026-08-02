import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:trffic_ilght_app/app/app.dart';
import 'package:trffic_ilght_app/core/services/model_management/remote_model_update_bootstrap.dart';
import 'package:trffic_ilght_app/features/settings/settings.dart';

export 'package:trffic_ilght_app/app/app.dart' show MyApp;

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
