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
  Future<void> get ready async {}

  @override
  Future<void> setEnabled(bool value) async {
    _enabled = value;
  }

  @override
  Future<void> applySettings({
    required bool isEnabled,
    required double volume,
    required double speed,
    required double pitch,
  }) async {
    _enabled = isEnabled;
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

YOLOResult _detection(String className, {double confidence = 0.9}) {
  return YOLOResult(
    classIndex: 0,
    className: className,
    confidence: confidence,
    boundingBox: const Rect.fromLTRB(40, 10, 60, 30),
    normalizedBox: const Rect.fromLTRB(0.4, 0.1, 0.6, 0.3),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VideoInferenceController - seek detection', () {
    test('การเล่นต่อเนื่องไม่ถือเป็นการ seek', () {
      expect(
        isSeekJump(previousIndex: 10, nextIndex: 11, maximumContinuousGap: 8),
        isFalse,
      );
    });

    test('ข้ามเฟรมที่วิเคราะห์ไม่สำเร็จไม่กี่เฟรมยังไม่ถือเป็นการ seek', () {
      expect(
        isSeekJump(previousIndex: 10, nextIndex: 16, maximumContinuousGap: 8),
        isFalse,
      );
    });

    test('seek ถอยหลังต้องเริ่ม session ใหม่', () {
      expect(
        isSeekJump(previousIndex: 40, nextIndex: 5, maximumContinuousGap: 8),
        isTrue,
      );
    });

    test('seek เดินหน้าไกล ๆ ก็ต้องเริ่ม session ใหม่เช่นกัน', () {
      expect(
        isSeekJump(previousIndex: 10, nextIndex: 90, maximumContinuousGap: 8),
        isTrue,
      );
    });
  });

  group('VideoInferenceController - confidence threshold', () {
    test('ใช้ threshold ของผู้ใช้กรองผลเหมือนโหมดเรียลไทม์', () {
      final controller = VideoInferenceController(
        voiceService: FakeTrafficVoiceService(),
      );
      controller.applyDetectionSettings(confidenceThreshold: 0.9);

      final greenLight = _detection('green_light_circle', confidence: 0.6);
      for (var frame = 0; frame < 5; frame++) {
        controller.updateCurrentFrameAnalysis(
          [greenLight],
          null,
          signPresent: false,
          timestamp: DateTime(2026).add(Duration(milliseconds: 250 * frame)),
        );
      }

      expect(controller.currentFormalNames, isEmpty);
      controller.dispose();
    });

    test('threshold ที่สูงลิ่วยังต้องไม่ปิดเสียงไฟแดง', () {
      final controller = VideoInferenceController(
        voiceService: FakeTrafficVoiceService(),
      );
      controller.applyDetectionSettings(confidenceThreshold: 0.9);

      final redLight = _detection('red_light_circle', confidence: 0.6);
      for (var frame = 0; frame < 5; frame++) {
        controller.updateCurrentFrameAnalysis(
          [redLight],
          null,
          signPresent: false,
          timestamp: DateTime(2026).add(Duration(milliseconds: 250 * frame)),
        );
      }

      expect(controller.currentDriverSignalResult.action, SignalAction.stop);
      controller.dispose();
    });
  });

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
