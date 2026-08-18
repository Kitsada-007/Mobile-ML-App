import 'dart:collection';
import 'dart:math' as math;

import 'package:trffic_ilght_app/features/camera_detection/data/models/realtime_inference.dart';

/// อายุสูงสุดของเฟรม (default) ที่ยังถือว่า "สด" (ไม่เก่าเกินไป)
/// ถ้าเฟรมแก่กว่านี้จะถูกตัดเป็น stale
const Duration defaultRealtimeMaximumFrameAge = Duration(milliseconds: 1500);

/// ผลการตัดสินใจของเฟรมว่าจะให้ผ่านหรือไม่
enum RealtimeFrameDecision { accept, stale, outOfOrder }

/// ตัวกรองความสดของเฟรม (Freshness Guard)
/// ใช้ตรวจว่าเซ็นต์มาจากกล้อง "ใหม่พอ" และ "เรียงลำดับถูกต้อง" ก่อนนำไปประมวลผล
/// - stale: เฟรมเก่าเกินไป (มาโพสต์เกินกำหนด -> ข้อมูลล้าสมัย)
/// - outOfOrder: เฟรมเลขน้อยกว่าเฟรมที่ยอมรับแล้วก่อนหน้า (มาไม่เรียง)
class RealtimeFrameFreshnessGuard {
  RealtimeFrameFreshnessGuard({
    this.maximumFrameAge = defaultRealtimeMaximumFrameAge,
  });

  final Duration maximumFrameAge;
  int? _lastAcceptedFrameNumber;

  int? get lastAcceptedFrameNumber => _lastAcceptedFrameNumber;

  /// ประเมินเฟรม: ตัดสินใจว่า accept / stale / outOfOrder
  RealtimeFrameDecision evaluate(
    RealtimeFramePacket packet, {
    required DateTime now,
  }) {
    if (packet.ageAt(now) > maximumFrameAge) {
      return RealtimeFrameDecision.stale;
    }

    final lastAcceptedFrameNumber = _lastAcceptedFrameNumber;
    if (lastAcceptedFrameNumber != null &&
        packet.frameNumber <= lastAcceptedFrameNumber) {
      return RealtimeFrameDecision.outOfOrder;
    }

    _lastAcceptedFrameNumber = packet.frameNumber;
    return RealtimeFrameDecision.accept;
  }

  void reset() => _lastAcceptedFrameNumber = null;
}

/// สแนปช็อตรวมของข้อมูล/สถิติของ pipeline ณ เวลาหนึ่ง
/// ใช้แสดงผลและ debug สภาพของการประมวลผลเรียลไทม์
class RealtimePipelineSnapshot {
  const RealtimePipelineSnapshot({
    required this.processedFrameCount,
    required this.staleFrameCount,
    required this.outOfOrderFrameCount,
    required this.droppedFrameCount,
    required this.endToEndLatencyP50,
    required this.endToEndLatencyP95,
    required this.endToEndLatencyP99,
    required this.inferenceLatencyP95,
    required this.queueLatencyP95,
    required this.latestFrameAge,
  });

  /// สแนปช็อตตอนยังไม่มีข้อมูล (ค่าเริ่มต้นทั้งหมดเป็น 0 / zero)
  const RealtimePipelineSnapshot.empty()
    : processedFrameCount = 0,
      staleFrameCount = 0,
      outOfOrderFrameCount = 0,
      droppedFrameCount = 0,
      endToEndLatencyP50 = Duration.zero,
      endToEndLatencyP95 = Duration.zero,
      endToEndLatencyP99 = Duration.zero,
      inferenceLatencyP95 = Duration.zero,
      queueLatencyP95 = Duration.zero,
      latestFrameAge = Duration.zero;

  /// latency ทั้งหมดวัดจาก "เวลาที่คาดว่าจับภาพ" ถึง "เวลาที่ประมวลผลเสร็จ"
  final int processedFrameCount;
  final int staleFrameCount;
  final int outOfOrderFrameCount;
  final int droppedFrameCount;
  final Duration endToEndLatencyP50;
  final Duration endToEndLatencyP95;
  final Duration endToEndLatencyP99;
  final Duration inferenceLatencyP95;
  final Duration queueLatencyP95;
  final Duration latestFrameAge;

  /// อัตราส่วนของเฟรมที่ถูก drop (0-1) เทียบกับที่ประมวลผลสำเร็จทั้งหมด
  double get droppedFrameRatio {
    final total = processedFrameCount + droppedFrameCount;
    if (total == 0) {
      return 0;
    }
    return droppedFrameCount / total;
  }
}

/// ตัวติดตาม (Monitor) สถิติของ pipeline การประมวลผลเรียลไทม์
/// - เก็บบันทึกตัวอย่าง (samples) ของเฟรมที่ประมวลผลไว้ (จำกัดจำนวน)
/// - คำนวณ percentile ของ latency ต่าง ๆ เพื่อดูว่าประมวลผลได้ทันหรือไม่
class RealtimePipelineMonitor {
  RealtimePipelineMonitor({this.maximumSamples = 120}) {
    assert(maximumSamples > 0);
  }

  final int maximumSamples;
  final Queue<_RealtimePipelineSample> _samples = Queue();
  int _processedFrameCount = 0;
  int _staleFrameCount = 0;
  int _outOfOrderFrameCount = 0;

  /// บันทึกว่าเฟรมหนึ่ง ๆ ถูกประมวลผลสำเร็จ พร้อมสถิติเวลา
  void recordProcessed(
    RealtimeFramePacket packet, {
    required DateTime processingStartedAt,
    required DateTime completedAt,
  }) {
    _processedFrameCount += 1;
    _samples.addLast(
      _RealtimePipelineSample(
        capturedAt: packet.estimatedCapturedAt,
        completedAt: completedAt,
        inferenceLatency: _durationFromMilliseconds(
          packet.inferenceMilliseconds,
        ),
        // เวลาที่เฟรมค้างอยู่ในคิว = เวลาที่เริ่มประมวลผล - เวลาที่รับเฟรมมา
        queueLatency: _nonNegativeDifference(
          processingStartedAt,
          packet.receivedAt,
        ),
      ),
    );
    while (_samples.length > maximumSamples) {
      _samples.removeFirst();
    }
  }

  /// บันทึกเฟรมที่ถูกปฏิเสธ (ตาม decision ที่ได้)
  void recordRejected(RealtimeFrameDecision decision) {
    switch (decision) {
      case RealtimeFrameDecision.accept:
        return;
      case RealtimeFrameDecision.stale:
        _staleFrameCount += 1;
        return;
      case RealtimeFrameDecision.outOfOrder:
        _outOfOrderFrameCount += 1;
        return;
    }
  }

  /// สร้างสแนปช็อตสรุปของ pipeline ณ ขณะนี้
  RealtimePipelineSnapshot snapshot({
    required int droppedFrameCount,
    required DateTime now,
  }) {
    if (_samples.isEmpty) {
      return RealtimePipelineSnapshot(
        processedFrameCount: _processedFrameCount,
        staleFrameCount: _staleFrameCount,
        outOfOrderFrameCount: _outOfOrderFrameCount,
        droppedFrameCount: droppedFrameCount,
        endToEndLatencyP50: Duration.zero,
        endToEndLatencyP95: Duration.zero,
        endToEndLatencyP99: Duration.zero,
        inferenceLatencyP95: Duration.zero,
        queueLatencyP95: Duration.zero,
        latestFrameAge: Duration.zero,
      );
    }

    final endToEndLatencies = _samples
        .map(
          (sample) =>
              _nonNegativeDifference(sample.completedAt, sample.capturedAt),
        )
        .toList(growable: false);
    final inferenceLatencies = _samples
        .map((sample) => sample.inferenceLatency)
        .toList(growable: false);
    final queueLatencies = _samples
        .map((sample) => sample.queueLatency)
        .toList(growable: false);

    return RealtimePipelineSnapshot(
      processedFrameCount: _processedFrameCount,
      staleFrameCount: _staleFrameCount,
      outOfOrderFrameCount: _outOfOrderFrameCount,
      droppedFrameCount: droppedFrameCount,
      endToEndLatencyP50: _percentile(endToEndLatencies, 0.50),
      endToEndLatencyP95: _percentile(endToEndLatencies, 0.95),
      endToEndLatencyP99: _percentile(endToEndLatencies, 0.99),
      inferenceLatencyP95: _percentile(inferenceLatencies, 0.95),
      queueLatencyP95: _percentile(queueLatencies, 0.95),
      latestFrameAge: _nonNegativeDifference(now, _samples.last.capturedAt),
    );
  }

  /// รีเซ็ตสถิติทั้งหมด (เช่นสลับกล้องหรือเริ่มรอบใหม่)
  void reset() {
    _samples.clear();
    _processedFrameCount = 0;
    _staleFrameCount = 0;
    _outOfOrderFrameCount = 0;
  }
}

/// ตัวอย่าง 1 จุดข้อมูลของเฟรมที่ประมวลผล (ข้อมูลดิบสำหรับคำนวณสถิติ)
class _RealtimePipelineSample {
  const _RealtimePipelineSample({
    required this.capturedAt,
    required this.completedAt,
    required this.inferenceLatency,
    required this.queueLatency,
  });

  final DateTime capturedAt;
  final DateTime completedAt;
  final Duration inferenceLatency;
  final Duration queueLatency;
}

/// แปลงค่าเป็นมิลลิวินาทีเป็น Duration (กันค่าติดลบ/ลบที่ null)
Duration _durationFromMilliseconds(double? value) {
  if (value == null) {
    return Duration.zero;
  }
  return Duration(microseconds: math.max(0, (value * 1000).round()));
}

/// คำนวณผลต่าง "ไม่เป็นลบ" ระหว่าง 2 เวลา
/// (ถ้า later < earlier เช่นค่านาฬิกาไม่ตรง -> คืน Duration.zero)
Duration _nonNegativeDifference(DateTime later, DateTime earlier) {
  final difference = later.difference(earlier);
  if (difference.isNegative) {
    return Duration.zero;
  }
  return difference;
}

/// คำนวณ percentile ของชุด Duration (เช่น p95, p99)
Duration _percentile(List<Duration> values, double percentile) {
  if (values.isEmpty) return Duration.zero;
  final sorted = values.map((value) => value.inMicroseconds).toList();
  sorted.sort();
  final index = (percentile * sorted.length).ceil().clamp(1, sorted.length) - 1;
  return Duration(microseconds: sorted[index]);
}
