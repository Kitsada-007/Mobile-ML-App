import 'dart:developer';

import 'package:trffic_ilght_app/core/services/detection/detection_alert_config.dart';
import 'package:trffic_ilght_app/core/services/detection/detection_stabilizer.dart';

/// พูดสัญญาณที่เป็นจริงพร้อมกันหลายอย่างเป็นข้อความเดียว
/// (ผู้เรียกเป็นคนประกอบประโยค เพราะรู้ชุดคำไทยของตัวเอง)
typedef StableClassSpeaker = Future<void> Function(List<String> classNames);

/// สั่งหยุดเสียงที่กำลังพูดอยู่ (ใช้ตอนต้องแทรกข้อความที่สำคัญกว่า)
typedef SpeechInterrupter = Future<void> Function();

/// แปลง stable events เป็นคำสั่งเสียง โดยพูดครั้งละหนึ่งข้อความเสมอ
///
/// เดิมถ้ากำลังพูดอยู่แล้วมี event ใหม่เข้ามา event นั้นจะถูก "ทิ้ง" ทันที
/// ซึ่งอันตรายมาก เพราะ stabilizer ยิง detected/changed แค่ครั้งเดียวต่อการเปลี่ยนสถานะ
/// ไฟแดงที่โผล่มาระหว่างกำลังพูดประโยคอื่นจึงเงียบหายไปเลย
/// ตอนนี้จึงเก็บ event ที่ยังพูดไม่ได้ไว้ในคิว แล้วพูดต่อทันทีที่ว่าง
/// และถ้า event ที่รออยู่สำคัญกว่าข้อความที่กำลังพูด จะแทรกทันทีโดยไม่รอให้จบ
final class VoiceAlertController {
  VoiceAlertController({
    required StableClassSpeaker speakClassName,
    SpeechInterrupter? interruptSpeech,
    this.config = const DetectionAlertConfig(),
    this.pendingRetention = const Duration(seconds: 5),
    this.combineWindow = const Duration(seconds: 2),
    this.maximumCombinedClasses = 3,
  }) {
    _speakClassName = speakClassName;
    _interruptSpeech = interruptSpeech;
  }

  /// ค่า priority สำหรับข้อความที่ไม่ได้ผูกกับคลาสใด (ยิ่งมากยิ่งสำคัญน้อย)
  static const int lowestPriority = 1 << 20;

  late final StableClassSpeaker _speakClassName;
  late final SpeechInterrupter? _interruptSpeech;
  final DetectionAlertConfig config;

  /// อายุสูงสุดของ event ที่รออยู่ในคิว เกินกว่านี้ถือว่าไม่จริงแล้ว ต้องทิ้ง
  /// (พูดสถานะไฟที่ผ่านไปนานแล้วอันตรายกว่าเงียบ)
  final Duration pendingRetention;

  /// ช่วงเวลาที่ถือว่าสัญญาณ "เกิดพร้อมกัน" จนควรพูดรวมเป็นประโยคเดียว
  final Duration combineWindow;

  /// จำนวนสัญญาณสูงสุดที่รวมได้ในหนึ่งประโยค (ยาวกว่านี้ไฟเปลี่ยนก่อนพูดจบ)
  final int maximumCombinedClasses;

  final Map<String, DateTime> _lastSpokenAtByClass = {};

  /// คิวรอพูด เก็บคลาสละหนึ่งรายการ (event ใหม่ของคลาสเดิมทับของเก่าเสมอ)
  final Map<String, DetectionEvent> _pendingByClass = {};

  bool _isSpeaking = false;
  int _speakingPriority = lowestPriority;
  int _sessionGeneration = 0;
  DateTime? _latestEventTime;

  bool get isSpeaking => _isSpeaking;

  /// จำนวน event ที่รอพูดอยู่ (ใช้ตรวจสอบในเทสต์)
  int get pendingCount => _pendingByClass.length;

  Future<DetectionEvent?> handleEvents(
    Iterable<DetectionEvent> events, {
    DateTime? timestamp,
  }) async {
    _ingestEvents(events, timestamp);
    return _drainPending();
  }

  /// เก็บ event เข้าคิว และล้างรายการที่ไม่จริงแล้วออก
  void _ingestEvents(Iterable<DetectionEvent> events, DateTime? timestamp) {
    if (timestamp != null) {
      _advanceClock(timestamp);
    }

    for (final event in events) {
      _advanceClock(event.timestamp);
      final className = event.detection.className;

      if (event.type == DetectionEventType.lost) {
        // วัตถุหลุดจากจอไปแล้ว ประกาศทีหลังก็ไม่ตรงกับความจริง
        _pendingByClass.remove(className);
        continue;
      }
      if (event.type != DetectionEventType.detected &&
          event.type != DetectionEventType.changed) {
        continue;
      }
      if (!config.participatesInVoiceAlerts(className)) continue;

      // สถานะไฟจราจรมีได้ทีละหนึ่งอย่าง ไฟที่เห็นก่อนหน้าจึงถูกแทนที่ด้วยไฟล่าสุด
      // (ไม่งั้นคิวจะเหลือ "ไฟเขียว" ค้างอยู่แล้วพูดออกไปหลังไฟเปลี่ยนเป็นแดงแล้ว)
      if (DetectionAlertConfig.trafficLightClasses.contains(className)) {
        _dropOlderTrafficLights(className, event.timestamp);
      }

      final existing = _pendingByClass[className];
      if (existing == null || !event.timestamp.isBefore(existing.timestamp)) {
        _pendingByClass[className] = event;
      }
    }

    _purgeExpired();
  }

  void _advanceClock(DateTime timestamp) {
    final latest = _latestEventTime;
    if (latest == null || timestamp.isAfter(latest)) {
      _latestEventTime = timestamp;
    }
  }

  /// ทิ้งไฟจราจรคลาสอื่นที่เก่ากว่าออกจากคิว (สถานะไฟเป็นจริงได้ทีละหนึ่ง)
  void _dropOlderTrafficLights(String className, DateTime timestamp) {
    final staleClasses = <String>[];
    _pendingByClass.forEach((pendingClass, pendingEvent) {
      if (pendingClass == className) return;
      if (!DetectionAlertConfig.trafficLightClasses.contains(pendingClass)) {
        return;
      }
      if (pendingEvent.timestamp.isBefore(timestamp)) {
        staleClasses.add(pendingClass);
      }
    });
    for (final staleClass in staleClasses) {
      _pendingByClass.remove(staleClass);
    }
  }

  void _purgeExpired() {
    final now = _latestEventTime;
    if (now == null) return;

    final expiredClasses = <String>[];
    _pendingByClass.forEach((className, event) {
      if (now.difference(event.timestamp) > pendingRetention) {
        expiredClasses.add(className);
      }
    });
    for (final expiredClass in expiredClasses) {
      _pendingByClass.remove(expiredClass);
    }
  }

  /// พูดรายการในคิวไปทีละข้อความจนกว่าจะหมดคิวหรือพูดต่อไม่ได้
  /// คืนค่า event แรกที่ได้พูดจริงในรอบนี้ (null = ไม่ได้พูดอะไรเลย)
  Future<DetectionEvent?> _drainPending() async {
    final spokenEvents = <DetectionEvent>[];

    while (true) {
      final candidate = _selectCandidate();
      if (candidate == null) return _firstOrNull(spokenEvents);

      final className = candidate.detection.className;
      final priority = config.ruleFor(className).priority;

      if (_isSpeaking) {
        // สำคัญไม่พอที่จะแทรก -> รอให้ข้อความปัจจุบันจบก่อน (ยังอยู่ในคิว ไม่ถูกทิ้ง)
        if (priority >= _speakingPriority) return _firstOrNull(spokenEvents);
        final interrupted = await _interruptCurrentSpeech();
        if (!interrupted) return _firstOrNull(spokenEvents);
      }

      // สัญญาณอื่นที่เป็นจริงพร้อมกัน (เช่นไฟแดง + ลูกศรตรงไป) ต้องได้ยินในประโยค
      // เดียวกัน ไม่ใช่ต่อคิวกันทีละประโยคจนไฟเปลี่ยนไปก่อนจะพูดครบ
      final companions = _selectCompanions(candidate);
      final spokenClasses = <String>[className];
      for (final companion in companions) {
        spokenClasses.add(companion.detection.className);
      }
      for (final spokenClass in spokenClasses) {
        _pendingByClass.remove(spokenClass);
      }

      final didSpeak = await speakMessageIfIdle(
        () => _speakClassName(spokenClasses),
        priority: priority,
      );
      if (!didSpeak) return _firstOrNull(spokenEvents);

      _lastSpokenAtByClass[className] = candidate.timestamp;
      for (final companion in companions) {
        _lastSpokenAtByClass[companion.detection.className] =
            companion.timestamp;
      }
      spokenEvents.add(candidate);

      // พูดสถานะไฟไปแล้วหนึ่งอย่าง ไฟดวงอื่นที่เห็นในจังหวะเดียวกันเป็นทางเลือก
      // ที่ขัดกันเอง (เช่นแดงกับเขียวพร้อมกัน) พูดตามไปด้วยมีแต่ทำให้สับสน
      if (DetectionAlertConfig.trafficLightClasses.contains(className)) {
        _dropCompetingTrafficLights(className, candidate.timestamp);
      }

      // ไฟที่สั่งหยุด/ระวัง ต้องทิ้งสัญญาณทิศทางที่เห็นในจังหวะเดียวกันด้วย
      // ไม่งั้นมันจะถูกพูดเป็นประโยคถัดไป กลายเป็นคำสั่งขัดกันอยู่ดี
      if (config.announcesAlone(className)) {
        _dropContradictingSignals(candidate.timestamp);
      }
    }
  }

  /// เลือกสัญญาณอื่นที่ควรพูดรวมกับ [primary] ในประโยคเดียว
  ///
  /// เงื่อนไข: พ้น cooldown ของตัวเอง, เกิดในช่วงเวลาใกล้กัน และไม่ใช่สถานะไฟอีกดวง
  /// (สีไฟเป็นจริงได้ทีละสถานะ พูดรวมกันจะกลายเป็นคำสั่งที่ขัดกันเอง)
  List<DetectionEvent> _selectCompanions(DetectionEvent primary) {
    final primaryClass = primary.detection.className;

    // ไฟแดง/เหลือง/ไฟเสีย ต้องพูดเดี่ยว ๆ ไม่งั้นจะได้ยิน "ไฟแดง หยุดรถ ตรงไปได้"
    // ซึ่งเป็นคำสั่งที่ขัดกันเอง (ไฟเขียวรวมกับลูกศรได้ เพราะไปในทางเดียวกัน)
    if (config.announcesAlone(primaryClass)) {
      return const <DetectionEvent>[];
    }

    final companions = <DetectionEvent>[];

    final candidates = _pendingByClass.values.toList();
    candidates.sort((first, second) {
      final firstPriority = config.ruleFor(first.detection.className).priority;
      final secondPriority = config
          .ruleFor(second.detection.className)
          .priority;
      return firstPriority.compareTo(secondPriority);
    });

    for (final candidate in candidates) {
      if (companions.length >= maximumCombinedClasses - 1) break;

      final className = candidate.detection.className;
      if (className == primaryClass) continue;
      final isTrafficLight = DetectionAlertConfig.trafficLightClasses.contains(
        className,
      );
      if (isTrafficLight) continue;

      final gap = candidate.timestamp.difference(primary.timestamp).abs();
      if (gap > combineWindow) continue;

      final cooldown = config.ruleFor(className).voiceCooldown;
      final lastSpokenAt = _lastSpokenAtByClass[className];
      if (lastSpokenAt != null &&
          candidate.timestamp.difference(lastSpokenAt) < cooldown) {
        continue;
      }
      companions.add(candidate);
    }
    return companions;
  }

  /// ทิ้งสัญญาณที่เป็นจริงในจังหวะเดียวกับคำสั่งหยุด (ไม่ใช่ของรอบถัดไป)
  void _dropContradictingSignals(DateTime timestamp) {
    final contradictingClasses = <String>[];
    _pendingByClass.forEach((pendingClass, pendingEvent) {
      final gap = pendingEvent.timestamp.difference(timestamp).abs();
      if (gap <= combineWindow) {
        contradictingClasses.add(pendingClass);
      }
    });
    for (final contradictingClass in contradictingClasses) {
      _pendingByClass.remove(contradictingClass);
    }
  }

  DetectionEvent? _firstOrNull(List<DetectionEvent> events) {
    if (events.isEmpty) return null;
    return events.first;
  }

  void _dropCompetingTrafficLights(String className, DateTime timestamp) {
    final competingClasses = <String>[];
    _pendingByClass.forEach((pendingClass, pendingEvent) {
      if (pendingClass == className) return;
      if (!DetectionAlertConfig.trafficLightClasses.contains(pendingClass)) {
        return;
      }
      if (!pendingEvent.timestamp.isAfter(timestamp)) {
        competingClasses.add(pendingClass);
      }
    });
    for (final competingClass in competingClasses) {
      _pendingByClass.remove(competingClass);
    }
  }

  /// เลือกรายการที่สำคัญที่สุดในคิวที่พ้น cooldown แล้ว
  DetectionEvent? _selectCandidate() {
    if (_pendingByClass.isEmpty) return null;

    final candidates = _pendingByClass.values.toList();
    candidates.sort((first, second) {
      final firstPriority = config.ruleFor(first.detection.className).priority;
      final secondPriority = config
          .ruleFor(second.detection.className)
          .priority;
      return firstPriority.compareTo(secondPriority);
    });

    for (final candidate in candidates) {
      final className = candidate.detection.className;
      final cooldown = config.ruleFor(className).voiceCooldown;
      final lastSpokenAt = _lastSpokenAtByClass[className];
      if (lastSpokenAt == null ||
          candidate.timestamp.difference(lastSpokenAt) >= cooldown) {
        return candidate;
      }
    }
    return null;
  }

  /// ตัดข้อความที่กำลังพูดอยู่ทิ้ง เพื่อเปิดทางให้ข้อความที่สำคัญกว่า
  /// ยังเป็นการพูดแบบทีละข้อความเหมือนเดิม ไม่ได้เปิดช่องพูดซ้อนกัน
  Future<bool> _interruptCurrentSpeech() async {
    final interrupter = _interruptSpeech;
    if (interrupter == null) return false;

    // ขยับ generation เพื่อให้ speakMessageIfIdle รอบเดิมรู้ว่าถูกยกเลิกไปแล้ว
    _sessionGeneration += 1;
    _isSpeaking = false;
    _speakingPriority = lowestPriority;
    try {
      await interrupter();
    } catch (error, stackTrace) {
      log(
        'หยุดเสียงเพื่อแทรกข้อความสำคัญไม่สำเร็จ: $error',
        stackTrace: stackTrace,
      );
    }
    return true;
  }

  /// [priority] ใช้ตัดสินว่าข้อความนี้จะถูกแทรกด้วยข้อความอื่นได้หรือไม่
  /// (ค่ายิ่งน้อยยิ่งสำคัญ ตรงกับ DetectionRule.priority)
  Future<bool> speakMessageIfIdle(
    Future<void> Function() speaker, {
    int priority = lowestPriority,
  }) async {
    if (_isSpeaking) return false;

    final generation = _sessionGeneration;
    _isSpeaking = true;
    _speakingPriority = priority;
    try {
      await speaker();
      return generation == _sessionGeneration;
    } finally {
      if (generation == _sessionGeneration) {
        _isSpeaking = false;
        _speakingPriority = lowestPriority;
      }
    }
  }

  void reset() {
    _sessionGeneration += 1;
    _lastSpokenAtByClass.clear();
    _pendingByClass.clear();
    _latestEventTime = null;
    _isSpeaking = false;
    _speakingPriority = lowestPriority;
  }
}
