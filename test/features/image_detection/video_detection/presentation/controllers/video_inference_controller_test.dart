import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/core/services/inference/signal_interpreter.dart';
import 'package:trffic_ilght_app/core/services/voice/traffic_voice_service.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/controllers/video_inference_controller.dart';
import 'package:ultralytics_yolo/yolo.dart';

class FakeTrafficVoiceService implements TrafficVoiceService {
  bool _enabled = true;

  @override
  bool get isEnabled => _enabled;

  @override
  Future<void> setEnabled(bool value) async {
    _enabled = value;
  }

  @override
  Future<void> reloadSettings() async {}

  @override
  Future<void> speak(String message) async {}

  @override
  String getThaiMessage(String className) => className;

  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VideoInferenceController - DriverSignalResult', () {
    test('initializes with empty DriverSignalResult', () {
      final controller = VideoInferenceController(
        voiceService: FakeTrafficVoiceService(),
      );
      expect(controller.currentDriverSignalResult.message, '');
      expect(controller.currentDriverSignalResult.action, SignalAction.none);
    });

    test('updates DriverSignalResult on frame update', () {
      final redLightResult = SignalInterpreter.interpret([
        YOLOResult(
          classIndex: 0,
          className: 'red_light_circle',
          confidence: 0.9,
          boundingBox: Rect.fromLTRB(0, 0, 10, 10),
          normalizedBox: Rect.fromLTRB(0, 0, 1, 1),
        ),
      ]);
      expect(redLightResult.action, SignalAction.stop);
      expect(redLightResult.message, 'ไฟแดง - หยุดรอ');
    });

    test('toggles voice notification state', () {
      final controller = VideoInferenceController(
        voiceService: FakeTrafficVoiceService(),
      );
      expect(controller.isVoiceEnabled, true);

      controller.toggleVoice();
      expect(controller.isVoiceEnabled, false);

      controller.toggleVoice();
      expect(controller.isVoiceEnabled, true);
    });

    test('clears snackBarMessage when clearSnackBarMessage is called', () {
      final controller = VideoInferenceController(
        voiceService: FakeTrafficVoiceService(),
      );
      controller.clearSnackBarMessage();
      expect(controller.snackBarMessage, isNull);
    });

    test(
      'pause resets detection session and handles uninitialized controller safely',
      () async {
        final controller = VideoInferenceController(
          voiceService: FakeTrafficVoiceService(),
        );
        await controller.pause();
        expect(controller.currentDriverSignalResult.action, SignalAction.none);
        expect(controller.currentFormalNames, isEmpty);
      },
    );

    test('dispose safely cleans up controller and voice service', () {
      final controller = VideoInferenceController(
        voiceService: FakeTrafficVoiceService(),
      );
      controller.dispose();
      expect(controller.currentDriverSignalResult.action, SignalAction.none);
    });
  });
}
