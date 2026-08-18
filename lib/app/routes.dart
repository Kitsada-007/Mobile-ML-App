import 'package:flutter/material.dart';
import 'package:trffic_ilght_app/features/camera_detection/camera_detection.dart';

import 'package:trffic_ilght_app/features/settings/settings.dart';
import 'package:trffic_ilght_app/features/video_detection/video_detection.dart';

abstract final class AppRoutes {
  static Route<void> cameraDetection() =>
      MaterialPageRoute<void>(builder: (_) => const CameraInferencePage());

  static Route<void> videoDetection() =>
      MaterialPageRoute<void>(builder: (_) => const VideoInferenceScreen());

  static Route<void> settings() =>
      MaterialPageRoute<void>(builder: (_) => const SettingPage());
}
