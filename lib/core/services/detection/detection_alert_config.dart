/// กลุ่มของประเภทวัตถุที่ตรวจจับได้ (แยกตามลักษณะการทำงานและการควบคุมเสียงแจ้งเตือน)
enum DetectionGroup {
  /// สัญญาณไฟจราจรหลัก (ไฟแดง, ไฟเหลือง, ไฟเขียว, ไฟดับ)
  trafficLight,

  /// สัญญาณไฟเลี้ยว (เลี้ยวซ้าย, เลี้ยวขวา)
  turnSignal,

  /// ป้ายจราจรและป้ายบังคับต่างๆ
  sign,

  /// วัตถุประเภทอื่นๆ
  other,
}

/// กฎและเงื่อนไขการกรองความเสถียร (Stabilization Rule) สำหรับวัตถุแต่ละประเภท
final class DetectionRule {
  const DetectionRule({
    required this.historySize,
    required this.requiredVotes,
    required this.missingGracePeriod,
    required this.voiceCooldown,
    required this.priority,
    this.minimumConsecutiveFrames,
    this.minimumContinuousDuration,
    this.flickerLookbackFrames,
    this.flickerLookbackDuration,
  });

  /// จำนวนเฟรมย้อนหลังที่ใช้สะสมประวัติผลการตรวจจับ
  final int historySize;

  /// จำนวนโหวตขั้นต่ำที่ต้องได้รับเพื่อให้ถือว่าวัตถุเสถียร (Stable)
  final int requiredVotes;

  /// ระยะเวลาผ่อนผันเมื่อวัตถุหายไปจากเฟรม ก่อนที่จะตัดสินว่าวัตถุหลุดจากจอ (Lost)
  final Duration missingGracePeriod;

  /// ระยะเวลาหน่วง (Cooldown) สำหรับการส่งเสียงแจ้งเตือนซ้ำ
  final Duration voiceCooldown;

  /// ลำดับความสำคัญของวัตถุ (ตัวเลขน้อย = ความสำคัญสูงกว่า)
  final int priority;

  /// จำนวนเฟรมต่อเนื่องขั้นต่ำที่ต้องตรวจเจอ (ใช้สำหรับกรณีพิเศษ เช่น สัญญาณไฟดับ off_light)
  final int? minimumConsecutiveFrames;

  /// ระยะเวลาต่อเนื่องขั้นต่ำที่ต้องตรวจเจอ (ใช้สำหรับกรณีพิเศษ เช่น สัญญาณไฟดับ off_light)
  final Duration? minimumContinuousDuration;

  /// จำนวนเฟรมย้อนหลังที่ต้อง "ไม่เคยเห็นคลาสอื่นเลย" ที่ตำแหน่งเดิม (กัน flicker)
  /// ใช้เฉพาะ off_light: ถ้าเห็นไฟติด (แดง/เหลือง/เขียว) ที่ IoU เดิมภายในหน้าต่างนี้
  /// = ไฟกะพริบจากกล้อง ไม่ใช่ไฟดับจริง (null = ไม่ตรวจ)
  final int? flickerLookbackFrames;

  /// หน้าต่างกัน flicker แบบ "ระยะเวลา" (fps-independent): หน้าต่างเฟรมอย่างเดียว
  /// สั้น/ยาวไม่เท่ากันตามอัตราเฟรมของแต่ละท่อ (video 4fps = 3 วิ, camera 30fps
  /// = 0.4 วิ) จึงต้องมีหน้าต่างเวลาคุมอีกชั้น (null = ไม่ตรวจ)
  final Duration? flickerLookbackDuration;
}

/// คลาสการตั้งค่าคอนฟิกสำหรับการกรองความเสถียร (Stabilization), การติดตามวัตถุ (Tracking) และเสียงแจ้งเตือน (Voice Alerts)
final class DetectionAlertConfig {
  const DetectionAlertConfig({
    this.minimumTrackingIou = 0.2,
    this.minimumConfidence = 0.25,
    this.trafficHistorySize = 5,
    this.trafficRequiredVotes = 4,
    this.trafficMissingGracePeriod = const Duration(seconds: 1),
    this.trafficVoiceCooldown = const Duration(seconds: 3),
    this.offLightMinimumFrames = 12,
    this.offLightMinimumDuration = const Duration(seconds: 6),
    int? flickerLookbackFrames,
    Duration? flickerLookbackDuration,
    this.turnHistorySize = 3,
    this.turnRequiredVotes = 3,
    this.turnMissingGracePeriod = const Duration(seconds: 1),
    this.turnVoiceCooldown = const Duration(seconds: 5),
    this.signHistorySize = 3,
    this.signRequiredVotes = 3,
    this.signMissingGracePeriod = const Duration(milliseconds: 1500),
    this.signVoiceCooldown = const Duration(seconds: 8),
  }) : _flickerLookbackFrames = flickerLookbackFrames,
       _flickerLookbackDuration = flickerLookbackDuration;

  /// คลาสวัตถุประเภทสัญญาณไฟจราจรหลัก
  static Set<String> get trafficLightClasses => {
    'red_light_circle',
    'red_light',
    'yellow_light',
    'yellow_light_circle',
    'green_light_circle',
    'green_light',
    'off_light',
  };

  /// คลาสวัตถุประเภทสัญญาณไฟเลี้ยว
  static const turnSignalClasses = <String>{'turn_left', 'turn_right'};

  /// คลาสวัตถุประเภทป้ายจราจรบังคับ
  static const signClasses = <String>{
    'dont_go_straight_arrow',
    'dont_turn_left',
    'dont_turn_right',
    'go_straight_arrow',
  };

  /// คลาสวัตถุพิเศษที่ใช้สำหรับตัดซูมอ่านตัวเลขเท่านั้น (ROI - Region of Interest) โดยไม่ต้องเข้ากระบวนการโหวตความเสถียร
  static const roiOnlyClasses = <String>{'sign_number'};

  /// คลาสที่พลาดแล้วอันตรายถึงชีวิต (สัญญาณให้หยุด/ระวัง และป้ายห้าม)
  static const safetyCriticalClasses = <String>{
    'red_light_circle',
    'red_light',
    'yellow_light',
    'yellow_light_circle',
    'off_light',
    'dont_go_straight_arrow',
    'dont_turn_left',
    'dont_turn_right',
  };

  /// เพดาน confidence threshold ของคลาสตาม [safetyCriticalClasses]
  ///
  /// ผู้ใช้ปรับ threshold ในหน้า Settings ได้ถึง 0.9 ซึ่งถ้าใช้กับทุกคลาสเท่ากันหมด
  /// จะเท่ากับปิดการเตือนไฟแดงไปเงียบ ๆ โดยที่ผู้ใช้ไม่รู้ตัว
  /// จึงยอมให้ปรับ "ให้ไวขึ้น" ได้ แต่ปรับให้หูหนวกกับสัญญาณอันตรายไม่ได้
  static const double safetyCriticalConfidenceCeiling = 0.5;

  /// ค่า IoU ขั้นต่ำสำหรับจับคู่วัตถุระหว่างเฟรม (Object Tracking)
  final double minimumTrackingIou;

  /// ค่าความเชื่อมั่นขั้นต่ำ (Confidence Score Threshold) ของการตรวจจับ
  final double minimumConfidence;

  // --- คอนฟิกสัญญาณไฟจราจร (Traffic Light) ---
  final int trafficHistorySize;
  final int trafficRequiredVotes;
  final Duration trafficMissingGracePeriod;
  final Duration trafficVoiceCooldown;
  final int offLightMinimumFrames;
  final Duration offLightMinimumDuration;

  /// ค่าที่ผู้ใช้ตั้งเอง (null = ใช้ค่า default ผูกกับ offLightMinimumFrames)
  final int? _flickerLookbackFrames;

  /// จำนวนเฟรมย้อนหลังที่ off_light ต้องไม่เคยเห็นไฟติดที่ตำแหน่งเดิมเลย (กัน flicker)
  /// (const constructor อ้างค่า field อื่นเป็น default ไม่ได้ จึง default ผ่าน getter)
  int get flickerLookbackFrames {
    final configured = _flickerLookbackFrames;
    if (configured == null) {
      return offLightMinimumFrames;
    }
    return configured;
  }

  /// ค่าที่ผู้ใช้ตั้งเอง (null = ใช้ค่า default ผูกกับ offLightMinimumDuration)
  final Duration? _flickerLookbackDuration;

  /// หน้าต่างเวลาที่ off_light ต้องไม่เคยเห็นไฟติดที่ตำแหน่งเดิมเลย (กัน flicker
  /// แบบ fps-independent) — default ผูกกับ offLightMinimumDuration ตามหลัก
  /// "ไฟดับจริงต้องดับสนิทตลอดหน้าต่างยืนยัน"
  Duration get flickerLookbackDuration {
    final configured = _flickerLookbackDuration;
    if (configured == null) {
      return offLightMinimumDuration;
    }
    return configured;
  }

  /// ระยะเวลาขั้นต่ำที่ต้องเก็บประวัติของกลุ่มไว้ (ให้หน้าต่างกัน flicker
  /// มองย้อนได้ครบ ไม่โดน evict ตามจำนวนเฟรมไปก่อน)
  /// — กลุ่มอื่นไม่ต้องเก็บตามเวลา
  Duration historyRetentionFor(DetectionGroup group) {
    if (group == DetectionGroup.trafficLight) return flickerLookbackDuration;
    return Duration.zero;
  }

  // --- คอนฟิกสัญญาณไฟเลี้ยว (Turn Signal) ---
  final int turnHistorySize;
  final int turnRequiredVotes;
  final Duration turnMissingGracePeriod;
  final Duration turnVoiceCooldown;

  // --- คอนฟิกป้ายจราจร (Traffic Sign) ---
  final int signHistorySize;
  final int signRequiredVotes;
  final Duration signMissingGracePeriod;
  final Duration signVoiceCooldown;

  /// หาหมวดหมู่ (DetectionGroup) ของวัตถุตามชื่อคลาส
  DetectionGroup groupFor(String className) {
    if (trafficLightClasses.contains(className)) {
      return DetectionGroup.trafficLight;
    }
    if (turnSignalClasses.contains(className)) {
      return DetectionGroup.turnSignal;
    }
    if (signClasses.contains(className)) return DetectionGroup.sign;
    return DetectionGroup.other;
  }

  /// ตรวจสอบว่าคลาสนี้เข้าร่วมการประมวลผลความเสถียร (Stable Detection) หรือไม่
  bool participatesInStableDetection(String className) =>
      !roiOnlyClasses.contains(className);

  /// ตรวจสอบว่าคลาสนี้ส่งเสียงแจ้งเตือนได้หรือไม่
  bool participatesInVoiceAlerts(String className) =>
      participatesInStableDetection(className);

  /// threshold ที่ใช้จริงกับคลาสนี้ หลังบังคับเพดานของคลาสที่เกี่ยวกับความปลอดภัย
  double effectiveConfidenceThreshold(
    String className,
    double selectedThreshold,
  ) {
    if (!safetyCriticalClasses.contains(className)) {
      return selectedThreshold;
    }
    if (selectedThreshold < safetyCriticalConfidenceCeiling) {
      return selectedThreshold;
    }
    return safetyCriticalConfidenceCeiling;
  }

  /// ดึงกฎการประมวลผล (DetectionRule) สำหรับชื่อคลาสที่ระบุ
  DetectionRule ruleFor(String className) {
    // เกณฑ์ยืนยันต่อเนื่องและหน้าต่างกัน flicker ใช้กับ off_light เท่านั้น
    // คลาสอื่นต้องเป็น null (= ไม่ตรวจ) ตามสัญญาของ DetectionRule
    int? offLightFrames;
    Duration? offLightDuration;
    int? offLightFlickerFrames;
    Duration? offLightFlickerDuration;
    if (className == 'off_light') {
      offLightFrames = offLightMinimumFrames;
      offLightDuration = offLightMinimumDuration;
      offLightFlickerFrames = flickerLookbackFrames;
      offLightFlickerDuration = flickerLookbackDuration;
    } else {
      offLightFrames = null;
      offLightDuration = null;
      offLightFlickerFrames = null;
      offLightFlickerDuration = null;
    }

    return switch (groupFor(className)) {
      DetectionGroup.trafficLight => DetectionRule(
        historySize: trafficHistorySize,
        requiredVotes: trafficRequiredVotes,
        missingGracePeriod: trafficMissingGracePeriod,
        voiceCooldown: trafficVoiceCooldown,
        priority: _priorityFor(className),
        minimumConsecutiveFrames: offLightFrames,
        minimumContinuousDuration: offLightDuration,
        flickerLookbackFrames: offLightFlickerFrames,
        flickerLookbackDuration: offLightFlickerDuration,
      ),
      DetectionGroup.turnSignal => DetectionRule(
        historySize: turnHistorySize,
        requiredVotes: turnRequiredVotes,
        missingGracePeriod: turnMissingGracePeriod,
        voiceCooldown: turnVoiceCooldown,
        priority: _priorityFor(className),
      ),
      DetectionGroup.sign => DetectionRule(
        historySize: signHistorySize,
        requiredVotes: signRequiredVotes,
        missingGracePeriod: signMissingGracePeriod,
        voiceCooldown: signVoiceCooldown,
        priority: _priorityFor(className),
      ),
      DetectionGroup.other => DetectionRule(
        historySize: signHistorySize,
        requiredVotes: signRequiredVotes,
        missingGracePeriod: signMissingGracePeriod,
        voiceCooldown: signVoiceCooldown,
        priority: _priorityFor(className),
      ),
    };
  }

  /// คำนวณขนาดบัฟเฟอร์ประวัติสูงสุดสำหรับกลุ่มวัตถุนั้นๆ
  int maximumHistorySizeFor(DetectionGroup group) {
    if (group == DetectionGroup.trafficLight) {
      // ต้องเก็บพอให้ lookback กัน flicker มองเห็นเฟรมไฟติดก่อนหน้าได้
      // (ไม่งั้นเฟรมไฟติดถูก evict ออกก่อนพอดี แล้ว off_light ยืนยันผิดๆ)
      var size = trafficHistorySize;
      if (offLightMinimumFrames > size) size = offLightMinimumFrames;
      if (flickerLookbackFrames > size) size = flickerLookbackFrames;
      return size;
    }
    return switch (group) {
      DetectionGroup.turnSignal => turnHistorySize,
      DetectionGroup.sign || DetectionGroup.other => signHistorySize,
      DetectionGroup.trafficLight => trafficHistorySize,
    };
  }

  /// กำหนดลำดับความสำคัญของคลาส (ตัวเลขน้อย = สำคัญมากที่สุด)
  int _priorityFor(String className) {
    return switch (className) {
      'off_light' => 0, // สัญญาณไฟขัดข้อง
      'red_light_circle' || 'red_light' => 1, // สัญญาณไฟแดง
      'yellow_light' || 'yellow_light_circle' => 2, // สัญญาณไฟเหลือง
      'green_light_circle' || 'green_light' => 3, // สัญญาณไฟเขียว
      'turn_left' || 'turn_right' => 4, // ไฟเลี้ยว
      'dont_go_straight_arrow' ||
      'dont_turn_left' ||
      'dont_turn_right' => 5, // ป้ายห้าม
      'go_straight_arrow' => 6, // ป้ายตรงไป
      _ => 7, // อื่นๆ
    };
  }
}
