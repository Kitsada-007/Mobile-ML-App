import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trffic_ilght_app/core/services/model_management/model_file_store.dart';
import 'package:trffic_ilght_app/core/services/model_management/model_registry.dart';
import 'package:trffic_ilght_app/core/services/model_management/model_update_client.dart';
import 'package:trffic_ilght_app/core/services/model_management/model_updater.dart';

/// เริ่มการเช็คอัปเดตโมเดลระยะไกล 1 ครั้งต่อเซสชัน (ไม่บล็อก UI)
/// - เรียกใช้เมื่อเปิดแอป
/// - ทำงานแบบเบื้องหลัง ไม่บล็อกการเริ่มแอป
final class RemoteModelUpdateBootstrap {
  RemoteModelUpdateBootstrap._();

  static final Uri manifestUri = Uri.parse(
    'https://github.com/Kitsada-007/Mobile-ML-App/'
    'releases/download/model-latest/model_manifest.json',
  );

  static Future<ModelUpdateReport?>? _sessionCheck;

  /// เช็คครั้งเดียวต่อเซสชัน (ครั้งถัดไปจะคืนผลเดิม)
  static Future<ModelUpdateReport?> checkOnce() {
    return _sessionCheck ??= _performCheck();
  }

  static Future<ModelUpdateReport?> _performCheck() async {
    if (!Platform.isAndroid) return null;

    final client = http.Client();
    try {
      final preferences = await SharedPreferences.getInstance();
      final packageInfo = await PackageInfo.fromPlatform();
      final updater = ModelUpdater(
        ModelUpdateClient(client, manifestUri: manifestUri),
        ModelFileStore(client),
        ModelRegistry(preferences),
        currentAppVersion: packageInfo.version,
      );

      final report = await updater.checkForUpdates();
      _logReport(report);
      return report;
    } catch (error, stackTrace) {
      debugPrint('Remote model update could not start: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    } finally {
      client.close();
    }
  }

  /// บันทึกผลการอัปเดตลง log เพื่อดูภายหลัง
  static void _logReport(ModelUpdateReport report) {
    if (report.error != null) {
      debugPrint('Remote model update check failed: ${report.error}');
      return;
    }

    for (final entry in report.results.entries) {
      debugPrint(
        'Remote model ${entry.key}: '
        '${entry.value.status.name} ${entry.value.version}',
      );
    }
  }
}
