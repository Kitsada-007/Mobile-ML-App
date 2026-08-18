enum CountdownEventType { countdownThresholdReached }

final class CountdownAlertConfig {
  const CountdownAlertConfig({
    this.thresholdSeconds = 5,
    this.redUiAction = 'เตรียมออกตัว',
    this.greenUiAction = 'เตรียมหยุด',
    this.yellowUiAction = 'หยุด',
    this.redVoiceMessage = 'ไฟแดงใกล้หมด เตรียมออกตัว',
    this.greenVoiceMessage = 'ไฟเขียวใกล้หมด เตรียมหยุด',
  });

  final int thresholdSeconds;
  final String redUiAction;
  final String greenUiAction;
  final String yellowUiAction;
  final String redVoiceMessage;
  final String greenVoiceMessage;
}

final class CountdownAlertEvent {
  const CountdownAlertEvent({
    required this.type,
    required this.seconds,
    required this.stableTrafficLightClassName,
    required this.voiceMessage,
  });

  final CountdownEventType type;
  final int seconds;
  final String stableTrafficLightClassName;
  final String voiceMessage;
}

final class CountdownAlertUpdate {
  const CountdownAlertUpdate({this.seconds, this.uiMessage, this.event});

  final int? seconds;
  final String? uiMessage;
  final CountdownAlertEvent? event;
}

/// สร้างเหตุการณ์เสียงเฉพาะตอนตัวเลขเข้าสู่ช่วงใกล้หมด โดยอ้างอิงไฟที่ยืนยันแล้วเท่านั้น
final class CountdownAlertController {
  CountdownAlertController({this.config = const CountdownAlertConfig()}) {
    assert(config.thresholdSeconds >= 0);
  }

  final CountdownAlertConfig config;

  static const supportedTrafficLightClasses = <String>{
    'red_light_circle',
    'green_light_circle',
    'yellow_light',
  };

  String? _lastStableTrafficLightClassName;
  bool _thresholdEventEmitted = false;

  CountdownAlertUpdate update({
    required bool isSignDetected,
    required String? detectedNumber,
    required String? stableTrafficLightClassName,
  }) {
    final stableLight = _supportedStableLight(stableTrafficLightClassName);
    if (stableLight != _lastStableTrafficLightClassName) {
      _lastStableTrafficLightClassName = stableLight;
      _thresholdEventEmitted = false;
    }

    if (!isSignDetected) {
      // ป้ายหายชั่วคราว (LED กะพริบ/PWM) ใช้การล้างแบบอ่อนเท่านั้น —
      // "ห้าม" เรียก reset() เพราะจะล้าง _thresholdEventEmitted ทำให้วงจร
      // เจอ → หาย 1 เฟรม → เจอใหม่ พูดเสียงเตือนซ้ำในการนับถอยหลังรอบเดียว
      // flag จะถูกล้างเฉพาะเมื่อ (1) คลาสไฟที่ยืนยันแล้วเปลี่ยน (เช็คด้านบน)
      // หรือ (2) เลขกลับขึ้นไปสูงกว่า threshold อีกครั้ง = เริ่มรอบใหม่ (เช็คด้านล่าง)
      // ส่วน reset() ตัวเต็มยังใช้ตอนเริ่ม session ใหม่ผ่าน _resetDetectionSession
      return const CountdownAlertUpdate();
    }

    String trimmedNumber;
    if (detectedNumber == null) {
      trimmedNumber = '';
    } else {
      trimmedNumber = detectedNumber.trim();
    }

    final seconds = int.tryParse(trimmedNumber);
    if (seconds == null || seconds < 0) {
      return const CountdownAlertUpdate();
    }

    final baseMessage = 'เหลืออีก $seconds วินาที';
    if (seconds > config.thresholdSeconds) {
      _thresholdEventEmitted = false;
      return CountdownAlertUpdate(seconds: seconds, uiMessage: baseMessage);
    }

    final action = _uiActionFor(stableLight);
    String uiMessage;
    if (action == null) {
      uiMessage = baseMessage;
    } else {
      uiMessage = '$baseMessage · $action';
    }
    final voiceMessage = _voiceMessageFor(stableLight);
    if (voiceMessage == null || _thresholdEventEmitted) {
      return CountdownAlertUpdate(seconds: seconds, uiMessage: uiMessage);
    }

    _thresholdEventEmitted = true;
    return CountdownAlertUpdate(
      seconds: seconds,
      uiMessage: uiMessage,
      event: CountdownAlertEvent(
        type: CountdownEventType.countdownThresholdReached,
        seconds: seconds,
        stableTrafficLightClassName: stableLight!,
        voiceMessage: voiceMessage,
      ),
    );
  }

  /// ล้างสถานะทั้งหมดรวมถึง _thresholdEventEmitted — ใช้เฉพาะตอนเริ่ม
  /// session ใหม่ (เลือกวิดีโอใหม่ / seek ย้อน / pause) เท่านั้น
  /// ห้ามเรียกจากกรณีป้ายหายชั่วคราวระหว่างนับถอยหลัง (ดูคอมเมนต์ใน update)
  void reset() {
    _lastStableTrafficLightClassName = null;
    _thresholdEventEmitted = false;
  }

  String? _supportedStableLight(String? className) {
    if (supportedTrafficLightClasses.contains(className)) {
      return className;
    }
    return null;
  }

  String? _uiActionFor(String? className) {
    return switch (className) {
      'red_light_circle' => config.redUiAction,
      'green_light_circle' => config.greenUiAction,
      'yellow_light' => config.yellowUiAction,
      _ => null,
    };
  }

  String? _voiceMessageFor(String? className) {
    return switch (className) {
      'red_light_circle' => config.redVoiceMessage,
      'green_light_circle' => config.greenVoiceMessage,
      _ => null,
    };
  }
}
