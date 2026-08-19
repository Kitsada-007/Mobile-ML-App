import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trffic_ilght_app/core/services/inference/countdown_reading_hold.dart';
import 'package:trffic_ilght_app/core/services/inference/countdown_reading_stabilizer.dart';
import 'package:trffic_ilght_app/core/services/inference/signal_interpreter.dart';
import 'package:trffic_ilght_app/core/services/voice/traffic_voice_service.dart';
import 'package:trffic_ilght_app/features/camera_detection/presentation/controllers/camera_inference_controller.dart';
import 'package:trffic_ilght_app/core/services/inference/sign_number_pipeline_service.dart';
import 'package:trffic_ilght_app/core/services/model_management/model_manager.dart';
import 'package:trffic_ilght_app/shared/models/model_types.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

/// TrafficVoiceService ปลอมสำหรับเทสต์: บันทึกข้อความที่ถูกสั่งพูดไว้ตรวจสอบ
class FakeTrafficVoiceService implements TrafficVoiceService {
  FakeTrafficVoiceService({bool enabled = true}) {
    _enabled = enabled;
  }

  late bool _enabled;
  final List<String> spokenMessages = [];
  double appliedVolume = 1.0;
  double appliedSpeed = 0.6;
  double appliedPitch = 1.0;

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
    appliedVolume = volume;
    appliedSpeed = speed;
    appliedPitch = pitch;
  }

  @override
  Future<void> reloadSettings() async {}

  @override
  Future<void> speak(String message) async {
    spokenMessages.add(message);
  }

  @override
  String getThaiMessage(String className) => className;

  @override
  Future<void> stop() async {}
}

class RecordingDigitYolo extends YOLO {
  RecordingDigitYolo()
    : super(modelPath: 'unused.tflite', task: YOLOTask.detect);

  int predictCallCount = 0;
  Uint8List? receivedImageBytes;

  @override
  Future<Map<String, dynamic>> predict(
    Uint8List imageBytes, {
    double? confidenceThreshold,
    double? iouThreshold,
  }) async {
    predictCallCount += 1;
    receivedImageBytes = imageBytes;
    return {
      'detections': [
        _digitDetection('1', left: 0.2),
        _digitDetection('2', left: 0.6),
      ],
    };
  }
}

/// โมเดลตัวเลขปลอมที่คืนเลขหลักเดียว (ใช้ทดสอบช่วงนับถอยหลังใกล้หมด)
class SingleDigitYolo extends YOLO {
  SingleDigitYolo(this.digit)
    : super(modelPath: 'unused.tflite', task: YOLOTask.detect);

  final String digit;
  int predictCallCount = 0;

  @override
  Future<Map<String, dynamic>> predict(
    Uint8List imageBytes, {
    double? confidenceThreshold,
    double? iouThreshold,
  }) async {
    predictCallCount += 1;
    return {
      'detections': [_digitDetection(digit, left: 0.4)],
    };
  }
}

class BlockingDigitYolo extends RecordingDigitYolo {
  final firstPredictionStarted = Completer<void>();
  final releaseFirstPrediction = Completer<void>();

  @override
  Future<Map<String, dynamic>> predict(
    Uint8List imageBytes, {
    double? confidenceThreshold,
    double? iouThreshold,
  }) async {
    if (predictCallCount == 0) {
      firstPredictionStarted.complete();
      await releaseFirstPrediction.future;
    }
    return super.predict(
      imageBytes,
      confidenceThreshold: confidenceThreshold,
      iouThreshold: iouThreshold,
    );
  }
}

class ClockAdvancingDigitYolo extends RecordingDigitYolo {
  ClockAdvancingDigitYolo(this.advanceClock);

  final void Function() advanceClock;

  @override
  Future<Map<String, dynamic>> predict(
    Uint8List imageBytes, {
    double? confidenceThreshold,
    double? iouThreshold,
  }) async {
    final result = await super.predict(
      imageBytes,
      confidenceThreshold: confidenceThreshold,
      iouThreshold: iouThreshold,
    );
    advanceClock();
    return result;
  }
}

Map<String, dynamic> _digitDetection(String digit, {required double left}) {
  return {
    'classIndex': int.parse(digit),
    'className': digit,
    'confidence': 0.9,
    'boundingBox': {
      'left': left * 100,
      'top': 10.0,
      'right': (left + 0.2) * 100,
      'bottom': 40.0,
    },
    'normalizedBox': {
      'left': left,
      'top': 0.1,
      'right': left + 0.2,
      'bottom': 0.4,
    },
  };
}

Map<String, dynamic> _signDetection() {
  return {
    'classIndex': 0,
    'className': 'sign_number',
    'confidence': 0.9,
    'boundingBox': {'left': 25.0, 'top': 40.0, 'right': 75.0, 'bottom': 160.0},
    'normalizedBox': {'left': 0.25, 'top': 0.20, 'right': 0.75, 'bottom': 0.80},
  };
}

Map<String, dynamic> _trafficLightDetectionMap(String className) {
  return {
    'classIndex': 1,
    'className': className,
    'confidence': 0.9,
    'boundingBox': {'left': 40.0, 'top': 10.0, 'right': 60.0, 'bottom': 30.0},
    'normalizedBox': {'left': 0.4, 'top': 0.1, 'right': 0.6, 'bottom': 0.3},
  };
}

YOLOResult _trafficLightDetection(
  String className, {
  double confidence = 0.9,
  double left = 0.4,
  double right = 0.6,
}) {
  return YOLOResult.fromMap({
    'classIndex': switch (className) {
      'red_light_circle' => 1,
      'yellow_light' => 2,
      'green_light_circle' => 3,
      _ => 0,
    },
    'className': className,
    'confidence': confidence,
    'boundingBox': {
      'left': left * 100,
      'top': 10.0,
      'right': right * 100,
      'bottom': 30.0,
    },
    'normalizedBox': {'left': left, 'top': 0.1, 'right': right, 'bottom': 0.3},
  });
}

/// ModelManager ปลอม: คืน path เสมอ เพื่อให้ controller อยู่ในสถานะ "โมเดลพร้อม"
/// (toggleCamera จะไม่ทำงานเลยถ้า modelPath ยังเป็น null)
class FakeModelManager extends ModelManager {
  @override
  Future<String?> getModelPath(ModelType modelType) async =>
      'fake_${modelType.remoteId}.tflite';

  @override
  Future<String?> reportModelLoadFailure(
    ModelType modelType, {
    required String failedPath,
  }) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({'isVoiceEnabled': false});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter_tts'),
        (call) async => 1,
      );

  test('native threshold keeps sign detections down to 0.25', () {
    expect(nativeRealtimeConfidenceThreshold(0.50), 0.25);
    expect(nativeRealtimeConfidenceThreshold(0.10), 0.10);
  });

  test('real-time stream skips the Number model when no sign exists', () async {
    final digitYolo = RecordingDigitYolo();
    final controller = CameraInferenceController(
      signNumberPipelineService: SignNumberPipelineService(
        digitYolo: digitYolo,
      ),
      numberDetectionInterval: Duration.zero,
    );
    final frame = img.Image(width: 200, height: 100);

    await controller.onStreamingData({
      'detections': <Map<String, dynamic>>[],
      'originalImage': Uint8List.fromList(img.encodeJpg(frame)),
      'imageWidth': 100,
      'imageHeight': 200,
    });

    expect(digitYolo.predictCallCount, 0);
    controller.dispose();
  });

  test(
    'real-time stream crops the same sign frame before Number inference',
    () async {
      final digitYolo = RecordingDigitYolo();
      final controller = CameraInferenceController(
        signNumberPipelineService: SignNumberPipelineService(
          digitYolo: digitYolo,
        ),
        numberDetectionInterval: Duration.zero,
      );
      final frame = img.Image(width: 200, height: 100);
      img.fill(frame, color: img.ColorRgb8(220, 30, 20));
      final frameBytes = Uint8List.fromList(img.encodeJpg(frame));

      await controller.onStreamingData({
        'frameNumber': 1,
        'detections': [_signDetection()],
        'originalImage': frameBytes,
        'imageWidth': 200,
        'imageHeight': 100,
      });

      expect(digitYolo.predictCallCount, 1);
      expect(digitYolo.receivedImageBytes, isNot(same(frameBytes)));
      expect(controller.detectedNumber, isNull);

      await controller.onStreamingData({
        'frameNumber': 2,
        'detections': [_signDetection()],
        'originalImage': frameBytes,
        'imageWidth': 200,
        'imageHeight': 100,
      });

      expect(digitYolo.predictCallCount, 2);
      expect(controller.detectedNumber, '12');

      await controller.onStreamingData({
        'frameNumber': 3,
        'detections': [_signDetection()],
        'originalImage': frameBytes,
        'imageWidth': 200,
        'imageHeight': 100,
      });

      expect(digitYolo.predictCallCount, 3);
      expect(controller.detectedNumber, '12');
      controller.dispose();
    },
  );

  test('default freshness budget keeps a successful Number result', () async {
    var now = DateTime(2026, 8, 3, 12);
    final digitYolo = ClockAdvancingDigitYolo(
      () => now = now.add(const Duration(milliseconds: 600)),
    );
    final controller = CameraInferenceController(
      signNumberPipelineService: SignNumberPipelineService(
        digitYolo: digitYolo,
      ),
      numberDetectionInterval: Duration.zero,
      countdownStabilizer: CountdownReadingStabilizer(requiredMatches: 1),
      clock: () => now,
      enableFreshnessWatchdog: false,
    );
    final frame = img.Image(width: 200, height: 100);

    for (var frameNumber = 1; frameNumber <= 3; frameNumber++) {
      final frameCapturedAt = now;
      await controller.onStreamingData({
        'frameNumber': frameNumber,
        'timestamp': frameCapturedAt.millisecondsSinceEpoch,
        'detections': [_signDetection()],
        'originalImage': Uint8List.fromList(img.encodeJpg(frame)),
        'imageWidth': 200,
        'imageHeight': 100,
      });
    }

    expect(controller.detectedNumber, '12');
    expect(controller.isRealtimePipelineStale, isFalse);
    controller.dispose();
  });

  test(
    'real-time queue processes one frame and keeps only the latest',
    () async {
      final digitYolo = BlockingDigitYolo();
      final controller = CameraInferenceController(
        signNumberPipelineService: SignNumberPipelineService(
          digitYolo: digitYolo,
        ),
        numberDetectionInterval: Duration.zero,
      );
      final frame = img.Image(width: 200, height: 100);
      final frameBytes = Uint8List.fromList(img.encodeJpg(frame));

      Map<String, dynamic> packet(int frameNumber) => {
        'frameNumber': frameNumber,
        'detections': [_signDetection()],
        'originalImage': frameBytes,
        'imageWidth': 200,
        'imageHeight': 100,
      };

      final drain = controller.onStreamingData(packet(1));
      await digitYolo.firstPredictionStarted.future;
      unawaited(controller.onStreamingData(packet(2)));
      unawaited(controller.onStreamingData(packet(3)));
      digitYolo.releaseFirstPrediction.complete();
      await drain;

      expect(digitYolo.predictCallCount, 2);
      expect(controller.realtimeDiagnostics.map((event) => event.frameNumber), [
        1,
        3,
      ]);
      expect(controller.droppedStreamFrameCount, 1);
      controller.dispose();
    },
  );

  test(
    'disposing during Number inference does not apply a stale result',
    () async {
      final digitYolo = BlockingDigitYolo();
      final controller = CameraInferenceController(
        signNumberPipelineService: SignNumberPipelineService(
          digitYolo: digitYolo,
        ),
        numberDetectionInterval: Duration.zero,
      );
      final frame = img.Image(width: 200, height: 100);
      final frameBytes = Uint8List.fromList(img.encodeJpg(frame));

      final drain = controller.onStreamingData({
        'frameNumber': 1,
        'detections': [_signDetection()],
        'originalImage': frameBytes,
        'imageWidth': 200,
        'imageHeight': 100,
      });
      await digitYolo.firstPredictionStarted.future;

      controller.dispose();
      digitYolo.releaseFirstPrediction.complete();
      await drain;

      expect(controller.detectedNumber, isNull);
    },
  );

  test('real-time diagnostics retain only the latest twenty events', () async {
    final digitYolo = RecordingDigitYolo();
    final controller = CameraInferenceController(
      signNumberPipelineService: SignNumberPipelineService(
        digitYolo: digitYolo,
      ),
      numberDetectionInterval: Duration.zero,
    );

    for (var frameNumber = 1; frameNumber <= 25; frameNumber++) {
      await controller.onStreamingData({
        'frameNumber': frameNumber,
        'detections': [_signDetection()],
      });
    }

    expect(controller.realtimeDiagnostics, hasLength(20));
    expect(controller.realtimeDiagnostics.first.frameNumber, 6);
    expect(controller.realtimeDiagnostics.last.frameNumber, 25);
    controller.dispose();
  });

  test('UI exposes only the traffic-light class that wins voting', () async {
    final controller = CameraInferenceController();
    final redLight = _trafficLightDetection('red_light_circle');

    for (var frame = 0; frame < 3; frame++) {
      await controller.onDetectionResults([redLight]);
    }
    expect(controller.confirmedTrafficLightClassName, isNull);
    expect(controller.detectedFormalNames, isEmpty);

    await controller.onDetectionResults([redLight]);
    expect(controller.confirmedTrafficLightClassName, 'red_light_circle');
    expect(controller.detectedFormalNames, hasLength(1));
    controller.dispose();
  });

  test('stays silent while the user has voice turned off', () async {
    final voiceService = FakeTrafficVoiceService(enabled: false);
    final controller = CameraInferenceController(
      voiceService: voiceService,
      enableFreshnessWatchdog: false,
    );
    final redLight = _trafficLightDetection('red_light_circle');

    // ยิงจนผ่านโหวต (4 จาก 5 เฟรม) ให้เกิด stable detected event จริง
    for (var frame = 0; frame < 4; frame++) {
      await controller.onDetectionResults([redLight]);
    }

    expect(controller.isVoiceEnabled, false);
    // ยืนยันว่าเกิด stable event จริง ไม่ใช่เงียบเพราะไม่มีอะไรให้พูด
    expect(controller.confirmedTrafficLightClassName, 'red_light_circle');
    expect(voiceService.spokenMessages, isEmpty);
    controller.dispose();
  });

  test('announces the stable class when voice is enabled', () async {
    final voiceService = FakeTrafficVoiceService();
    final controller = CameraInferenceController(
      voiceService: voiceService,
      enableFreshnessWatchdog: false,
    );
    final redLight = _trafficLightDetection('red_light_circle');

    for (var frame = 0; frame < 4; frame++) {
      await controller.onDetectionResults([redLight]);
    }
    await Future<void>.delayed(Duration.zero); // รอ unawaited handleEvents

    expect(controller.isVoiceEnabled, true);
    expect(voiceService.spokenMessages, hasLength(1));
    expect(voiceService.spokenMessages.single, contains('red_light_circle'));
    controller.dispose();
  });

  test('applyDetectionSettings updates the thresholds used for filtering', () {
    final controller = CameraInferenceController(
      voiceService: FakeTrafficVoiceService(),
      enableFreshnessWatchdog: false,
    );
    expect(controller.confidenceThreshold, 0.5);
    expect(controller.iouThreshold, 0.45);
    expect(controller.numItemsThreshold, 11);

    var notifyCount = 0;
    controller.addListener(() {
      notifyCount = notifyCount + 1;
    });

    // ค่าที่ผู้ใช้เปลี่ยนในหน้า Settings ต้องมีผลกับหน้ากล้องที่เปิดค้างอยู่ทันที
    controller.applyDetectionSettings(
      confidenceThreshold: 0.8,
      iouThreshold: 0.6,
      numItemsThreshold: 20,
    );

    expect(controller.confidenceThreshold, 0.8);
    expect(controller.iouThreshold, 0.6);
    expect(controller.numItemsThreshold, 20);
    expect(notifyCount, 1);

    // ค่าเดิมซ้ำ ๆ ต้องไม่สั่ง notify ซ้ำ (กัน rebuild ทุกครั้งที่ provider แจ้งเตือน)
    controller.applyDetectionSettings(
      confidenceThreshold: 0.8,
      iouThreshold: 0.6,
      numItemsThreshold: 20,
    );
    expect(notifyCount, 1);
    controller.dispose();
  });

  test('applyDetectionSettings raises the confidence bar for detections', () async {
    final controller = CameraInferenceController(
      voiceService: FakeTrafficVoiceService(),
      enableFreshnessWatchdog: false,
    );
    controller.applyDetectionSettings(
      confidenceThreshold: 0.9,
      iouThreshold: 0.45,
      numItemsThreshold: 11,
    );

    // confidence 0.8 ต่ำกว่าเกณฑ์ใหม่ จึงต้องไม่ถูกนับเป็นการตรวจจับที่ผ่านเกณฑ์
    // (ใช้ไฟเขียวเพราะคลาสที่เกี่ยวกับความปลอดภัยมีเพดาน ปรับให้สูงกว่านั้นไม่ได้)
    final weakGreenLight = _trafficLightDetection(
      'green_light_circle',
      confidence: 0.8,
    );
    for (var frame = 0; frame < 5; frame++) {
      await controller.onDetectionResults([weakGreenLight]);
    }

    expect(controller.confirmedTrafficLightClassName, isNull);
    controller.dispose();
  });

  test('a high user threshold can never silence the red light', () async {
    final voiceService = FakeTrafficVoiceService();
    final controller = CameraInferenceController(
      voiceService: voiceService,
      enableFreshnessWatchdog: false,
    );
    // ผู้ใช้ดัน threshold ไปสุด = เท่ากับปิดการเตือนไฟแดงถ้าไม่มีเพดานความปลอดภัย
    controller.applyDetectionSettings(
      confidenceThreshold: 0.9,
      iouThreshold: 0.45,
      numItemsThreshold: 11,
    );

    final redLight = _trafficLightDetection(
      'red_light_circle',
      confidence: 0.6,
    );
    for (var frame = 0; frame < 4; frame++) {
      await controller.onDetectionResults([redLight]);
    }
    await Future<void>.delayed(Duration.zero); // รอ unawaited handleEvents

    expect(controller.confirmedTrafficLightClassName, 'red_light_circle');
    expect(voiceService.spokenMessages, hasLength(1));
    controller.dispose();
  });

  test(
    'speaks the countdown warning while the red light is running out',
    () async {
      final voiceService = FakeTrafficVoiceService();
      final controller = CameraInferenceController(
        voiceService: voiceService,
        signNumberPipelineService: SignNumberPipelineService(
          digitYolo: SingleDigitYolo('3'),
        ),
        numberDetectionInterval: Duration.zero,
        countdownStabilizer: CountdownReadingStabilizer(requiredMatches: 1),
        enableFreshnessWatchdog: false,
      );
      final frame = img.Image(width: 200, height: 100);
      final frameBytes = Uint8List.fromList(img.encodeJpg(frame));

      for (var frameNumber = 1; frameNumber <= 6; frameNumber++) {
        await controller.onStreamingData({
          'frameNumber': frameNumber,
          'detections': [
            _signDetection(),
            _trafficLightDetectionMap('red_light_circle'),
          ],
          'originalImage': frameBytes,
          'imageWidth': 200,
          'imageHeight': 100,
        });
        await Future<void>.delayed(Duration.zero); // รอ unawaited ของเสียง
      }

      expect(controller.detectedNumber, '3');
      // โหมดเรียลไทม์ต้องมีทั้งข้อความและเสียง ไม่ใช่แค่ตัวเลขบนจอ
      expect(controller.countdownUiMessage, 'เหลืออีก 3 วินาที · เตรียมออกตัว');
      expect(controller.driverSignalResult.message, contains('อีก 3 วินาที'));
      expect(
        voiceService.spokenMessages,
        contains('ไฟแดงใกล้หมด เตรียมออกตัว'),
      );
      controller.dispose();
    },
  );

  test('realtime countdown number is held briefly, then cleared', () async {
    var now = DateTime(2026, 8, 3, 12);
    final controller = CameraInferenceController(
      voiceService: FakeTrafficVoiceService(),
      clock: () => now,
      signNumberPipelineService: SignNumberPipelineService(
        digitYolo: SingleDigitYolo('3'),
      ),
      numberDetectionInterval: Duration.zero,
      countdownStabilizer: CountdownReadingStabilizer(requiredMatches: 1),
      countdownHold: CountdownReadingHold(
        holdDuration: const Duration(milliseconds: 1500),
      ),
      enableFreshnessWatchdog: false,
    );
    final frame = img.Image(width: 200, height: 100);
    final frameBytes = Uint8List.fromList(img.encodeJpg(frame));

    for (var frameNumber = 1; frameNumber <= 2; frameNumber++) {
      await controller.onStreamingData({
        'frameNumber': frameNumber,
        'detections': [_signDetection()],
        'originalImage': frameBytes,
        'imageWidth': 200,
        'imageHeight': 100,
      });
    }
    expect(controller.detectedNumber, '3');

    // ป้ายหายไปชั่วครู่ (LED กะพริบ) -> ยังต้องเห็นเลขเดิม
    now = now.add(const Duration(milliseconds: 1000));
    await controller.onStreamingData({
      'frameNumber': 3,
      'detections': const <Map<String, dynamic>>[],
    });
    expect(controller.detectedNumber, '3');

    // แต่หายนานเกินเวลาที่ถือไว้ -> ต้องล้างทิ้ง ไม่ปล่อยให้เลขเก่าค้างบนจอ
    now = now.add(const Duration(milliseconds: 1000));
    await controller.onStreamingData({
      'frameNumber': 4,
      'detections': const <Map<String, dynamic>>[],
    });
    expect(controller.detectedNumber, isNull);
    controller.dispose();
  });

  test('toggleVoice flips the announcement state', () {
    final controller = CameraInferenceController(
      voiceService: FakeTrafficVoiceService(),
      enableFreshnessWatchdog: false,
    );
    expect(controller.isVoiceEnabled, true);

    controller.toggleVoice();
    expect(controller.isVoiceEnabled, false);

    controller.toggleVoice();
    expect(controller.isVoiceEnabled, true);
    controller.dispose();
  });

  test('confirmed green light keeps reading the countdown number', () async {
    final digitYolo = RecordingDigitYolo();
    final controller = CameraInferenceController(
      signNumberPipelineService: SignNumberPipelineService(
        digitYolo: digitYolo,
      ),
      numberDetectionInterval: Duration.zero,
      countdownStabilizer: CountdownReadingStabilizer(requiredMatches: 1),
      enableFreshnessWatchdog: false,
    );
    final frame = img.Image(width: 200, height: 100);
    final frameBytes = Uint8List.fromList(img.encodeJpg(frame));

    for (var frameNumber = 1; frameNumber <= 3; frameNumber++) {
      await controller.onStreamingData({
        'frameNumber': frameNumber,
        'detections': [_signDetection()],
        'originalImage': frameBytes,
        'imageWidth': 200,
        'imageHeight': 100,
      });
    }
    expect(controller.detectedNumber, '12');
    expect(digitYolo.predictCallCount, 3);

    for (var frameNumber = 4; frameNumber <= 7; frameNumber++) {
      await controller.onStreamingData({
        'frameNumber': frameNumber,
        'detections': [
          _signDetection(),
          _trafficLightDetectionMap('green_light_circle'),
        ],
        'originalImage': frameBytes,
        'imageWidth': 200,
        'imageHeight': 100,
      });
    }

    // ไฟเขียวไม่ตัดการอ่านเลขอีกต่อไป — ต้องยังเห็นเลขนับถอยหลัง
    // (UI จะแสดงเป็นสีเขียว) และโมเดลตัวเลขต้องทำงานต่อทุกเฟรม
    expect(controller.confirmedTrafficLightClassName, 'green_light_circle');
    expect(controller.detectedNumber, '12');
    expect(digitYolo.predictCallCount, 7);

    await controller.onStreamingData({
      'frameNumber': 8,
      'detections': [
        _signDetection(),
        _trafficLightDetectionMap('green_light_circle'),
      ],
      'originalImage': frameBytes,
      'imageWidth': 200,
      'imageHeight': 100,
    });
    expect(controller.detectedNumber, '12');
    expect(digitYolo.predictCallCount, 8);
    controller.dispose();
  });

  test(
    'unconfirmed low-confidence traffic light is hidden from the UI',
    () async {
      final controller = CameraInferenceController();
      final redLight = _trafficLightDetection(
        'red_light_circle',
        confidence: 0.30,
      );

      await controller.onDetectionResults([redLight]);

      expect(controller.detectedFormalNames, isEmpty);
      controller.dispose();
    },
  );

  test('traffic light tracking selects the centered relevant light', () async {
    final controller = CameraInferenceController();
    final detections = [
      _trafficLightDetection(
        'green_light_circle',
        confidence: 0.99,
        left: 0.78,
        right: 0.94,
      ),
      _trafficLightDetection('red_light_circle', confidence: 0.86),
    ];

    for (var frame = 0; frame < 4; frame++) {
      await controller.onDetectionResults(detections);
    }

    expect(controller.confirmedTrafficLightClassName, 'red_light_circle');
    controller.dispose();
  });

  test('stale stream frames are rejected before updating detections', () async {
    final capturedAt = DateTime(2026, 8, 3, 12);
    final now = capturedAt.add(const Duration(milliseconds: 501));
    final controller = CameraInferenceController(
      clock: () => now,
      maximumFrameAge: const Duration(milliseconds: 500),
      enableFreshnessWatchdog: false,
    );

    await controller.onStreamingData({
      'frameNumber': 1,
      'timestamp': capturedAt.millisecondsSinceEpoch,
      'detections': [_trafficLightDetectionMap('red_light_circle')],
    });

    expect(controller.detectionCount, 0);
    expect(controller.pipelineSnapshot.staleFrameCount, 1);
    expect(controller.confirmedTrafficLightClassName, isNull);
    controller.dispose();
  });

  test('duplicate stream frame numbers are rejected', () async {
    final now = DateTime(2026, 8, 3, 12);
    final controller = CameraInferenceController(
      clock: () => now,
      enableFreshnessWatchdog: false,
    );

    Future<void> send(int frameNumber) => controller.onStreamingData({
      'frameNumber': frameNumber,
      'timestamp': now.millisecondsSinceEpoch,
      'detections': [_trafficLightDetectionMap('red_light_circle')],
    });

    await send(2);
    await send(2);

    expect(controller.pipelineSnapshot.processedFrameCount, 1);
    expect(controller.pipelineSnapshot.outOfOrderFrameCount, 1);
    controller.dispose();
  });

  test('freshness watchdog clears an expired visual result', () async {
    var now = DateTime(2026, 8, 3, 12);
    final controller = CameraInferenceController(
      clock: () => now,
      maximumFrameAge: const Duration(milliseconds: 500),
      enableFreshnessWatchdog: false,
    );

    for (var frame = 1; frame <= 4; frame++) {
      await controller.onStreamingData({
        'frameNumber': frame,
        'timestamp': now.millisecondsSinceEpoch,
        'detections': [_trafficLightDetectionMap('red_light_circle')],
      });
      now = now.add(const Duration(milliseconds: 50));
    }
    expect(controller.confirmedTrafficLightClassName, 'red_light_circle');

    now = now.add(const Duration(milliseconds: 501));
    controller.expireStaleResults(now: now);

    expect(controller.confirmedTrafficLightClassName, isNull);
    expect(controller.detectionCount, 0);
    expect(controller.detectedFormalNames, isEmpty);
    expect(controller.isRealtimePipelineStale, isTrue);
    controller.dispose();
  });

  test('records end-to-end latency for accepted stream frames', () async {
    final capturedAt = DateTime(2026, 8, 3, 12);
    final now = capturedAt.add(const Duration(milliseconds: 120));
    final controller = CameraInferenceController(
      clock: () => now,
      enableFreshnessWatchdog: false,
    );

    await controller.onStreamingData({
      'frameNumber': 1,
      'timestamp': capturedAt.millisecondsSinceEpoch,
      'inferenceMs': 30,
      'detections': <Map<String, dynamic>>[],
    });

    expect(controller.pipelineSnapshot.processedFrameCount, 1);
    expect(controller.pipelineSnapshot.endToEndLatencyP95.inMilliseconds, 120);
    expect(controller.pipelineSnapshot.inferenceLatencyP95.inMilliseconds, 30);
    expect(controller.isRealtimePipelineStale, isFalse);
    controller.dispose();
  });

  test(
    'reopening the camera accepts a restarted native frame sequence',
    () async {
      final now = DateTime(2026, 8, 15, 10);
      final controller = CameraInferenceController(
        clock: () => now,
        enableFreshnessWatchdog: false,
        modelManager: FakeModelManager(),
      );
      await controller.initialize();
      expect(controller.modelPath, isNotNull);

      Future<void> feed(int frameNumber) => controller.onStreamingData({
        'frameNumber': frameNumber,
        'timestamp': now.millisecondsSinceEpoch,
        'detections': [_trafficLightDetectionMap('red_light_circle')],
      });

      await feed(101);
      await feed(102);
      expect(controller.isRealtimePipelineStale, isFalse);

      await controller.toggleCamera();
      expect(controller.isCameraEnabled, isFalse);
      await controller.toggleCamera();
      expect(controller.isCameraEnabled, isTrue);

      // กล้อง native เริ่มนับ frameNumber ใหม่หลัง resume
      await feed(1);
      await feed(2);

      expect(
        controller.isRealtimePipelineStale,
        isFalse,
        reason:
            'เฟรมชุดใหม่หลังเปิดกล้องต้องถูกยอมรับ ไม่ใช่ถูกตัดเป็น outOfOrder',
      );
      controller.dispose();
    },
  );

  test('expiring stale results also clears the displayed confidence', () async {
    var now = DateTime(2026, 8, 15, 10);
    final controller = CameraInferenceController(
      clock: () => now,
      enableFreshnessWatchdog: false,
    );

    for (var frameNumber = 1; frameNumber <= 5; frameNumber++) {
      await controller.onStreamingData({
        'frameNumber': frameNumber,
        'timestamp': now.millisecondsSinceEpoch,
        'detections': [_trafficLightDetectionMap('red_light_circle')],
      });
    }
    expect(controller.detectedFormalNames, isNotEmpty);
    expect(controller.lastDetectionConfidence, isNotNull);

    now = now.add(const Duration(seconds: 5));
    controller.expireStaleResults();

    expect(controller.isRealtimePipelineStale, isTrue);
    expect(controller.detectedFormalNames, isEmpty);
    expect(
      controller.lastDetectionConfidence,
      isNull,
      reason: 'ผลล้าสมัยแล้ว ชิป CONF ต้องไม่ค้างค่าเดิมไว้บนแผงที่ว่าง',
    );
    controller.dispose();
  });

  test(
    'stable red light produces the stop banner from SignalInterpreter',
    () async {
      final now = DateTime(2026, 8, 15, 10);
      final controller = CameraInferenceController(
        clock: () => now,
        enableFreshnessWatchdog: false,
      );

      for (var frameNumber = 1; frameNumber <= 5; frameNumber++) {
        await controller.onStreamingData({
          'frameNumber': frameNumber,
          'timestamp': now.millisecondsSinceEpoch,
          'detections': [_trafficLightDetectionMap('red_light_circle')],
        });
      }

      expect(controller.driverSignalResult.action, SignalAction.stop);
      expect(controller.driverSignalResult.message, 'ไฟแดง - หยุดรอ');
      controller.dispose();
    },
  );

  test('expiring stale results also clears the driver signal banner', () async {
    var now = DateTime(2026, 8, 15, 10);
    final controller = CameraInferenceController(
      clock: () => now,
      enableFreshnessWatchdog: false,
    );

    for (var frameNumber = 1; frameNumber <= 5; frameNumber++) {
      await controller.onStreamingData({
        'frameNumber': frameNumber,
        'timestamp': now.millisecondsSinceEpoch,
        'detections': [_trafficLightDetectionMap('red_light_circle')],
      });
    }
    expect(controller.driverSignalResult.action, SignalAction.stop);

    now = now.add(const Duration(seconds: 5));
    controller.expireStaleResults();

    expect(controller.isRealtimePipelineStale, isTrue);
    expect(
      controller.driverSignalResult.message,
      isEmpty,
      reason: 'เฟรมหยุดมาแล้ว แบนเนอร์ต้องไม่ค้างคำสั่ง "หยุดรอ" ไว้',
    );
    expect(controller.driverSignalResult.action, SignalAction.none);
    controller.dispose();
  });
}
