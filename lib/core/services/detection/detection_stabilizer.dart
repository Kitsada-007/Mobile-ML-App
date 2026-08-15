import 'dart:collection';
import 'dart:ui';

import 'package:trffic_ilght_app/core/services/detection/detection_alert_config.dart';
import 'package:ultralytics_yolo/yolo.dart';

/// ประเภทของเหตุการณ์เกี่ยวกับการตรวจจับวัตถุ (Detection Event Type)
enum DetectionEventType {
  /// ตรวจพบวัตถุเสถียรชิ้นใหม่ (New Detection)
  detected,

  /// สถานะ/ชนิดของวัตถุเดิมเปลี่ยนไป (Class Changed) เช่น ไฟเขียวเปลี่ยนเป็นไฟเหลือง
  changed,

  /// วัตถุหลุดออกจากเฟรม/หายไปเกินระยะเวลาผ่อนผัน (Detection Lost)
  lost,
}

/// คลาสเก็บข้อมูลวัตถุที่ผ่านการกรองความเสถียรแล้ว (Stable Detection)
final class StableDetection {
  const StableDetection({
    required this.trackId,
    required this.className,
    required this.confidence,
    required this.boundingBox,
    required this.normalizedBox,
    this.classIndex = 0,
  });

  /// รหัสติดตามวัตถุแบบไม่ซ้ำกัน (Track ID)
  final int trackId;

  /// ดัชนีคลาส
  final int classIndex;

  /// ชื่อคลาสของวัตถุที่เสถียรแล้ว
  final String className;

  /// ค่าความเชื่อมั่นเฉลี่ยจากการโหวต
  final double confidence;

  /// พิกัดกรอบวัตถุแบบพิกเซลจริง (Pixel Bounding Box)
  final Rect boundingBox;

  /// พิกัดกรอบวัตถุแบบนอร์มัลไลซ์ 0.0 - 1.0 (Normalized Bounding Box)
  final Rect normalizedBox;

  /// แปลงเป็นวัตถุ YOLOResult สำหรับนำไปใช้วาดกรอบ overlay หรือประมวลผลต่อ
  YOLOResult toYoloResult() => YOLOResult(
    classIndex: classIndex,
    className: className,
    confidence: confidence,
    boundingBox: boundingBox,
    normalizedBox: normalizedBox,
  );
}

/// เหตุการณ์การตรวจจับที่เกิดขึ้นในแต่ละเฟรม (Detection Event)
final class DetectionEvent {
  const DetectionEvent({
    required this.type,
    required this.detection,
    required this.timestamp,
  });

  /// ประเภทเหตุการณ์ (detected, changed, lost)
  final DetectionEventType type;

  /// ข้อมูลวัตถุเสถียรที่เกี่ยวข้อง
  final StableDetection detection;

  /// เวลาที่เกิดเหตุการณ์
  final DateTime timestamp;
}

/// ผลลัพธ์จากการประมวลผลความเสถียรในเฟรมล่าสุด
final class DetectionStabilizerUpdate {
  const DetectionStabilizerUpdate({
    required this.stableDetections,
    required this.events,
  });

  /// รายการวัตถุที่เสถียรทั้งหมดในปัจจุบัน
  final List<StableDetection> stableDetections;

  /// รายการเหตุการณ์ที่เกิดขึ้นใหม่ในเฟรมนี้ (เช่น ตรวจเจอใหม่, เปลี่ยนคลาส, หายไป)
  final List<DetectionEvent> events;
}

/// บันทึกการสังเกตวัตถุในแต่ละเฟรม (Single Detection Observation)
final class DetectionObservation {
  const DetectionObservation({
    required this.className,
    required this.confidence,
    required this.timestamp,
  });

  /// ชื่อคลาสที่ตรวจพบในเฟรมนั้น
  final String className;

  /// ค่าความเชื่อมั่นในเฟรมนั้น
  final double confidence;

  /// เวลาที่ตรวจพบ
  final DateTime timestamp;
}

/// คลาสเก็บสถานะการติดตามวัตถุ 1 ชิ้นย้อนหลังหลายๆ เฟรม (Tracked Object State)
final class TrackedDetectionState {
  TrackedDetectionState._({
    required this.trackId,
    required this.group,
    required YOLOResult initialDetection,
    required DateTime timestamp,
  }) : _lastDetection = initialDetection,
       _lastSeenAt = timestamp;

  /// รหัสติดตามวัตถุ
  final int trackId;

  /// กลุ่มประเภทวัตถุ (DetectionGroup)
  final DetectionGroup group;

  /// บัฟเฟอร์ประวัติการสังเกตย้อนหลัง (Queue)
  final Queue<DetectionObservation> _history = Queue();

  /// ข้อมูลการตรวจพบดิบครั้งล่าสุด
  YOLOResult _lastDetection;

  /// เวลาล่าสุดที่พบวัตถุชิ้นนี้
  DateTime _lastSeenAt;

  /// ชื่อคลาสที่ได้รับการยืนยันว่าเสถียรแล้ว (null หากยังไม่ผ่านเกณฑ์โหวต)
  String? _stableClassName;

  /// รายการประวัติการสังเกตวัตถุย้อนหลังแบบ Read-only
  List<DetectionObservation> get history => List.unmodifiable(_history);

  /// เวลาล่าสุดที่พบวัตถุ
  DateTime get lastSeenAt => _lastSeenAt;

  /// ชื่อคลาสที่เสถียร
  String? get stableClassName => _stableClassName;
}

/// ระบบจัดการความเสถียรของผลการตรวจจับ (Detection Stabilizer)
/// 
/// ทำหน้าที่:
/// 1. ติดตามวัตถุระหว่างเฟรมโดยใช้พิกัดตำแหน่ง (IoU - Intersection over Union Tracking)
/// 2. กรองสัญญาณรบกวน (Flickering/Noise) โดยใช้ระบบโหวตประวัติย้อนหลัง (Majority Voting)
/// 3. จัดการระยะเวลาผ่อนผันเมื่อวัตถุหายไปชั่วคราว (Grace Period Expiration)
/// 4. ส่งออกเหตุการณ์ (DetectionEvent) เมื่อตรวจพบใหม่, เปลี่ยนคลาส หรือวัตถุหลุดจากจอ
final class DetectionStabilizer {
  DetectionStabilizer({this.config = const DetectionAlertConfig()});

  /// คอนฟิกสำหรับการกรองและติดตามวัตถุ
  final DetectionAlertConfig config;

  /// ตารางเก็บรายการวัตถุที่กำลังติดตามอยู่ (Key: trackId)
  final Map<int, TrackedDetectionState> _tracks = {};

  /// ตัวสร้างรหัสติดตามถัดไป
  int _nextTrackId = 1;

  /// ดึงรายการวัตถุที่กำลังติดตามอยู่ทั้งหมด
  List<TrackedDetectionState> get tracks => List.unmodifiable(_tracks.values);

  /// ดึงรายการวัตถุที่ผ่านเกณฑ์ความเสถียรทั้งหมดในปัจจุบัน
  List<StableDetection> get stableDetections => _tracks.values
      .where((track) => track._stableClassName != null)
      .map(_stableDetectionFor)
      .toList(growable: false);

  /// อัปเดตผลการตรวจจับดิบจากเฟรมใหม่ และประมวลผลความเสถียร
  DetectionStabilizerUpdate update(
    Iterable<YOLOResult> rawDetections, {
    required DateTime timestamp,
  }) {
    final events = <DetectionEvent>[];

    // 1. ตรวจสอบและตัดวัตถุที่หายไปนานเกินระยะเวลาผ่อนผัน (Grace Period Expiration)
    _expireTracks(timestamp, events);

    // 2. กรองเฉพาะวัตถุที่ตรงตามเงื่อนไข (ความเชื่อมั่นผานเกณฑ์ และขนาดกรอบสมบูรณ์)
    final detections =
        rawDetections
            .where(
              (detection) =>
                  config.participatesInStableDetection(detection.className) &&
                  detection.confidence.isFinite &&
                  detection.confidence >= config.minimumConfidence &&
                  _trackingBox(detection).width > 0 &&
                  _trackingBox(detection).height > 0,
            )
            .toList()
          ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final matchedTrackIds = <int>{};

    // 3. จับคู่วัตถุใหม่เข้ากับ Track เดิม (IoU Matching) หรือสร้าง Track ใหม่
    for (final detection in detections) {
      final group = config.groupFor(detection.className);
      final track = _bestTrackFor(
        detection,
        group: group,
        excludedTrackIds: matchedTrackIds,
      );
      final selectedTrack =
          track ?? _createTrack(detection, group: group, timestamp: timestamp);
      matchedTrackIds.add(selectedTrack.trackId);

      // บันทึกประวัติการสังเกตลงใน Track
      _addObservation(selectedTrack, detection, timestamp);

      // ประมวลผลโหวตตัดสินคลาสที่เสถียร
      final event = _evaluateStableClass(selectedTrack, timestamp);
      if (event != null) events.add(event);
    }

    return DetectionStabilizerUpdate(
      stableDetections: stableDetections,
      events: List.unmodifiable(events),
    );
  }

  /// ตรวจสอบว่ามีวัตถุคลาสนี้ที่เสถียรอยู่ในเฟรมหรือไม่
  bool hasStableClass(String className) =>
      stableDetections.any((detection) => detection.className == className);

  /// ล้างข้อมูลการติดตามทั้งหมด (Reset State)
  void reset() {
    _tracks.clear();
    _nextTrackId = 1;
  }

  /// สร้าง Track ใหม่สำหรับวัตถุชิ้นใหม่
  TrackedDetectionState _createTrack(
    YOLOResult detection, {
    required DetectionGroup group,
    required DateTime timestamp,
  }) {
    final track = TrackedDetectionState._(
      trackId: _nextTrackId++,
      group: group,
      initialDetection: detection,
      timestamp: timestamp,
    );
    _tracks[track.trackId] = track;
    return track;
  }

  /// หา Track เดิมที่ตรงกับตำแหน่งวัตถุในเฟรมนี้มากที่สุด (อิงตามค่า IoU สูงสุด)
  TrackedDetectionState? _bestTrackFor(
    YOLOResult detection, {
    required DetectionGroup group,
    required Set<int> excludedTrackIds,
  }) {
    TrackedDetectionState? bestTrack;
    var bestIou = config.minimumTrackingIou;
    for (final track in _tracks.values) {
      if (track.group != group || excludedTrackIds.contains(track.trackId)) {
        continue;
      }
      final iou = _intersectionOverUnion(
        _trackingBox(track._lastDetection),
        _trackingBox(detection),
      );
      if (iou >= bestIou) {
        bestIou = iou;
        bestTrack = track;
      }
    }
    return bestTrack;
  }

  /// เพิ่มข้อมูลสังเกตวัตถุใหม่ลงในคิวประวัติย้อนหลังของ Track นั้นๆ
  void _addObservation(
    TrackedDetectionState track,
    YOLOResult detection,
    DateTime timestamp,
  ) {
    track._lastDetection = detection;
    track._lastSeenAt = timestamp;
    track._history.addLast(
      DetectionObservation(
        className: detection.className,
        confidence: detection.confidence,
        timestamp: timestamp,
      ),
    );
    final maximumHistorySize = config.maximumHistorySizeFor(track.group);
    while (track._history.length > maximumHistorySize) {
      track._history.removeFirst();
    }
  }

  /// ประมวลผลตัดสินคลาสที่เสถียรสำหรับ Track และสร้างเหตุการณ์ (DetectionEvent) หากมีการเปลี่ยนแปลง
  DetectionEvent? _evaluateStableClass(
    TrackedDetectionState track,
    DateTime timestamp,
  ) {
    final candidate = _winningClass(track);
    if (candidate == null || candidate == track._stableClassName) return null;

    final previousClass = track._stableClassName;
    track._stableClassName = candidate;
    return DetectionEvent(
      type: previousClass == null
          ? DetectionEventType.detected
          : DetectionEventType.changed,
      detection: _stableDetectionFor(track),
      timestamp: timestamp,
    );
  }

  /// คำนวณหาคลาสที่ชนะการโหวตจากประวัติย้อนหลัง (Majority Voting)
  String? _winningClass(TrackedDetectionState track) {
    if (track._history.isEmpty) return null;
    final latestClass = track._history.last.className;
    final rule = config.ruleFor(latestClass);

    // ดึงประวัติย้อนหลังตามจำนวน historySize ของคลาส
    final recent = track._history.length <= rule.historySize
        ? track._history.toList(growable: false)
        : track._history
              .skip(track._history.length - rule.historySize)
              .toList(growable: false);

    final voteCounts = <String, int>{};
    final confidenceScores = <String, double>{};
    for (final observation in recent) {
      voteCounts.update(
        observation.className,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      confidenceScores.update(
        observation.className,
        (score) => score + observation.confidence,
        ifAbsent: () => observation.confidence,
      );
    }

    // เรียงลำดับคลาสตามจำนวนโหวต (และตามคะแนนความเชื่อมั่นรวมในกรณีโหวตเท่ากัน)
    final ranked = voteCounts.keys.toList()
      ..sort((first, second) {
        final countOrder = voteCounts[second]!.compareTo(voteCounts[first]!);
        if (countOrder != 0) return countOrder;
        return confidenceScores[second]!.compareTo(confidenceScores[first]!);
      });
    final candidate = ranked.first;
    final candidateRule = config.ruleFor(candidate);

    // ตรวจสอบว่าโหวตถึงเกณฑ์ขั้นต่ำ (requiredVotes) หรือไม่
    if (voteCounts[candidate]! < candidateRule.requiredVotes) return null;

    // ตรวจสอบเกณฑ์การตรวจพบต่อเนื่อง (กรณีพิเศษ เช่น off_light)
    if (!_passesContinuousConfirmation(track, candidate, candidateRule)) {
      return null;
    }
    return candidate;
  }

  /// ตรวจสอบว่าคลาสผู้สมัครผ่านเกณฑ์การตรวจพบต่อเนื่องย้อนหลัง (Continuous Confirmation) หรือไม่
  bool _passesContinuousConfirmation(
    TrackedDetectionState track,
    String candidate,
    DetectionRule rule,
  ) {
    final requiredFrames = rule.minimumConsecutiveFrames;
    final requiredDuration = rule.minimumContinuousDuration;
    if (requiredFrames == null && requiredDuration == null) return true;

    // กัน flicker: ถ้าภายใน N เฟรมล่าสุดของตำแหน่งนี้ (Track เดิมตาม IoU) เคยเห็น
    // คลาสอื่น (= ไฟติด) แม้แต่เฟรมเดียว แปลว่าไฟกะพริบจากกล้อง ไม่ใช่ไฟดับจริง
    // เกตนี้คุมทั้งเกณฑ์นับเฟรมและเกณฑ์ระยะเวลา (สำคัญกับเฟรมห่างๆ ที่เกณฑ์
    // ระยะเวลาเคยผ่านทั้งที่เพิ่งเห็นไฟติดก่อนหน้าช่วงสั้นๆ)
    if (_sawOtherClassWithinLookback(track, candidate, rule)) return false;

    final consecutive = <DetectionObservation>[];
    for (final observation in track._history.toList().reversed) {
      if (observation.className != candidate) break;
      consecutive.add(observation);
    }
    final frameRequirementPassed =
        requiredFrames != null && consecutive.length >= requiredFrames;
    final durationRequirementPassed =
        requiredDuration != null &&
        consecutive.isNotEmpty &&
        consecutive.first.timestamp.difference(consecutive.last.timestamp) >=
            requiredDuration;
    return frameRequirementPassed || durationRequirementPassed;
  }

  /// ตรวจว่าใน [DetectionRule.flickerLookbackFrames] เฟรมล่าสุดของ Track นี้
  /// เคยพบคลาสอื่นนอกจากผู้สมัครหรือไม่ (ใช้เฉพาะคลาสที่กำหนด lookback เช่น off_light)
  bool _sawOtherClassWithinLookback(
    TrackedDetectionState track,
    String candidate,
    DetectionRule rule,
  ) {
    final lookback = rule.flickerLookbackFrames;
    if (lookback == null) return false;

    final history = track._history;
    final window = history.length <= lookback
        ? history
        : history.skip(history.length - lookback);
    return window.any((observation) => observation.className != candidate);
  }

  /// ตรวจสอบ Track ที่หมดอายุ (ไม่พบวัตถุเกินระยะเวลาผ่อนผัน missingGracePeriod) และส่งออกเหตุการณ์ lost
  void _expireTracks(DateTime timestamp, List<DetectionEvent> events) {
    final expiredIds = <int>[];
    for (final track in _tracks.values) {
      final referenceClass =
          track._stableClassName ?? track._lastDetection.className;
      final gracePeriod = config.ruleFor(referenceClass).missingGracePeriod;
      if (timestamp.difference(track._lastSeenAt) <= gracePeriod) continue;

      final stableClass = track._stableClassName;
      if (stableClass != null) {
        events.add(
          DetectionEvent(
            type: DetectionEventType.lost,
            detection: _stableDetectionFor(track),
            timestamp: timestamp,
          ),
        );
      }
      expiredIds.add(track.trackId);
    }
    for (final trackId in expiredIds) {
      _tracks.remove(trackId);
    }
  }

  /// สร้างวัตถุ StableDetection จาก TrackedDetectionState ที่กำหนด
  StableDetection _stableDetectionFor(TrackedDetectionState track) {
    final stableClass = track._stableClassName!;
    final observations = track._history
        .where((observation) => observation.className == stableClass)
        .toList(growable: false);
    final confidence = observations.isEmpty
        ? track._lastDetection.confidence
        : observations
                  .map((observation) => observation.confidence)
                  .reduce((first, second) => first + second) /
              observations.length;
    return StableDetection(
      trackId: track.trackId,
      classIndex: track._lastDetection.classIndex,
      className: stableClass,
      confidence: confidence,
      boundingBox: track._lastDetection.boundingBox,
      normalizedBox: track._lastDetection.normalizedBox,
    );
  }
}

/// ดึงพิกัดกรอบสำหรับใช้คำนวณการติดตามวัตถุ (เลือก normalizedBox ก่อน หากไม่มีใช้ boundingBox)
Rect _trackingBox(YOLOResult detection) {
  final normalized = detection.normalizedBox;
  return normalized.width > 0 && normalized.height > 0
      ? normalized
      : detection.boundingBox;
}

/// คำนวณค่า Intersection over Union (IoU) ระหว่างสองกรอบสี่เหลี่ยม
double _intersectionOverUnion(Rect first, Rect second) {
  final intersection = first.intersect(second);
  if (intersection.width <= 0 || intersection.height <= 0) return 0;
  final intersectionArea = intersection.width * intersection.height;
  final unionArea =
      first.width * first.height +
      second.width * second.height -
      intersectionArea;
  return unionArea <= 0 ? 0 : intersectionArea / unionArea;
}

