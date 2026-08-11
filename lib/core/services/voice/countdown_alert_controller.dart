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
  CountdownAlertController({this.config = const CountdownAlertConfig()})
    : assert(config.thresholdSeconds >= 0);

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
      reset();
      return const CountdownAlertUpdate();
    }

    final seconds = int.tryParse(detectedNumber?.trim() ?? '');
    if (seconds == null || seconds < 0) {
      return const CountdownAlertUpdate();
    }

    final baseMessage = 'เหลืออีก $seconds วินาที';
    if (seconds > config.thresholdSeconds) {
      _thresholdEventEmitted = false;
      return CountdownAlertUpdate(seconds: seconds, uiMessage: baseMessage);
    }

    final action = _uiActionFor(stableLight);
    final uiMessage = action == null ? baseMessage : '$baseMessage · $action';
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

  void reset() {
    _lastStableTrafficLightClassName = null;
    _thresholdEventEmitted = false;
  }

  String? _supportedStableLight(String? className) {
    return supportedTrafficLightClasses.contains(className) ? className : null;
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
