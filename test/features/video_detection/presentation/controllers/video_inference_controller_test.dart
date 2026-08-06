import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/core/services/inference/signal_interpreter.dart';
import 'package:trffic_ilght_app/core/services/voice/traffic_voice_service.dart';
import 'package:trffic_ilght_app/features/video_detection/presentation/controllers/video_inference_controller.dart';

class FakeTrafficVoiceService implements TrafficVoiceService {
  bool _enabled = true;

  @override
  bool get isEnabled => _enabled;

  @override
  Future<void> setEnabled(bool value) async {
    _enabled = value;
  }

  @override
  Future<void> speak(String message) async {}

  @override
  Future<void> speakNumber(String number, {String? activeLightClass}) async {}

  @override
  Future<void> processDetection(
    String className,
    double confidence, {
    bool isSignActive = false,
    bool hasSpokenGetReady = false,
    bool announceImmediately = false,
  }) async {}

  @override
  String getFormalThaiName(String className) => className;

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
        const YOLOResult(
          className: 'red_light_circle',
          confidence: 0.9,
          boundingBox: Rect.fromLTRB(0, 0, 10, 10),
        )
      ]);
      expect(redLightResult.action, SignalAction.stop);
      expect(redLightResult.message, 'ไฟแดง หยุดรถ');
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
  });
}
