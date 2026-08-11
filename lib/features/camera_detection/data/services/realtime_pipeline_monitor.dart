import 'dart:collection'; // ใช้ Queue
import 'dart:math' as math; // ใช้ในการคำนวณ percentile

import 'package:trffic_ilght_app/features/camera_detection/data/models/realtime_inference.dart'; // โครงสร้าง RealtimeFramePacket

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

  final Duration maximumFrameAge; // อายุสูงสุดที่ยอมรับ
  int? _lastAcceptedFrameNumber; // เลขเฟรมล่าสุดที่ผ่าน (ยอมรับ)

  int? get lastAcceptedFrameNumber => _lastAcceptedFrameNumber;

  /// ประเมินเฟรม: ตัดสินใจว่า accept / stale / outOfOrder
  RealtimeFrameDecision evaluate(
    RealtimeFramePacket packet, {
    required DateTime now,
  }) {
    // 1. เช็คอายุ: ถ้าเก่าเกิน -> stale
    if (packet.ageAt(now) > maximumFrameAge) {
      return RealtimeFrameDecision.stale;
    }

    // 2. เช็คลำดับ: ถ้าเลขเฟรมน้อยกว่าหรือเท่ากับเฟรมที่ยอมรับไปแล้ว -> outOfOrder
    final lastAcceptedFrameNumber = _lastAcceptedFrameNumber;
    if (lastAcceptedFrameNumber != null &&
        packet.frameNumber <= lastAcceptedFrameNumber) {
      return RealtimeFrameDecision.outOfOrder;
    }

    // 3. ผ่านทั้งหมด -> ยอมรับ และอัปเดตเลขเฟรมล่าสุด
    _lastAcceptedFrameNumber = packet.frameNumber;
    return RealtimeFrameDecision.accept;
  }

  void reset() => _lastAcceptedFrameNumber = null; // รีเซ็ต (เช่นสลับกล้อง)
}

/// สแนปช็อตรวมของข้อมูล/สถิติของ pipeline ณ เวลาหนึ่ง
/// ใช้แสดงผลและ debug สภาพของการประมวลผลเรียลไทม์
class RealtimePipelineSnapshot {
  const RealtimePipelineSnapshot({
    required this.processedFrameCount, // จำนวนเฟรมที่ประมวลผลสำเร็จ
    required this.staleFrameCount, // จำนวนเฟรมที่ถูกตัดเพราะเก่า
    required this.outOfOrderFrameCount, // จำนวนเฟรมที่ถูกตัดเพราะไม่เรียง
    required this.droppedFrameCount, // จำนวนเฟรมที่ถูก drop จากคิว
    required this.endToEndLatencyP50, // latency จากจับภาพถึงเสร็จ (percentile 50)
    required this.endToEndLatencyP95, // percentile 95
    required this.endToEndLatencyP99, // percentile 99
    required this.inferenceLatencyP95, // latency เฉพาะ inference (p95)
    required this.queueLatencyP95, // latency ที่อยู่ในคิว (p95)
    required this.latestFrameAge, // อายุของเฟรมล่าสุดที่ประมวลผล
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
    return total == 0 ? 0 : droppedFrameCount / total;
  }
}

/// ตัวติดตาม (Monitor) สถิติของ pipeline การประมวลผลเรียลไทม์
/// - เก็บบันทึกตัวอย่าง (samples) ของเฟรมที่ประมวลผลไว้ (จำกัดจำนวน)
/// - คำนวณ percentile ของ latency ต่าง ๆ เพื่อดูว่าประมวลผลได้ทันหรือไม่
class RealtimePipelineMonitor {
  RealtimePipelineMonitor({this.maximumSamples = 120})
    : assert(maximumSamples > 0); // ต้องมีตัวอย่างอย่างน้อย 1

  final int maximumSamples; // จำนวนตัวอย่างสูงสุดที่เก็บ
  final Queue<_RealtimePipelineSample> _samples = Queue(); // คิวเก็บตัวอย่าง
  int _processedFrameCount = 0; // นับเฟรมที่ประมวลผลสำเร็จ
  int _staleFrameCount = 0; // นับเฟรมเก่า
  int _outOfOrderFrameCount = 0; // นับเฟรมไม่เรียง

  /// บันทึกว่าเฟรมหนึ่ง ๆ ถูกประมวลผลสำเร็จ พร้อมสถิติเวลา
  void recordProcessed(
    RealtimeFramePacket packet, {
    required DateTime processingStartedAt, // เวลาเริ่มประมวลผลเฟรมนี้
    required DateTime completedAt, // เวลาเสร็จสิ้น
  }) {
    _processedFrameCount += 1;
    _samples.addLast(
      _RealtimePipelineSample(
        capturedAt: packet.estimatedCapturedAt, // เวลาจับภาพของเฟรม
        completedAt: completedAt,
        inferenceLatency: _durationFromMilliseconds(
          packet.inferenceMilliseconds, // latency จากโมเดล
        ),
        queueLatency: _nonNegativeDifference(
          processingStartedAt, // เวลาที่อยู่ในคิว = เริ่มประมวลผล - เวลาที่รับมา
          packet.receivedAt,
        ),
      ),
    );
    // ลบตัวอย่างเก่าออกถ้าเกินจำนวนสูงสุด (จำกัดหน่วยความจำ)
    while (_samples.length > maximumSamples) {
      _samples.removeFirst();
    }
  }

  /// บันทึกเฟรมที่ถูกปฏิเสธ (ตาม decision ที่ได้)
  void recordRejected(RealtimeFrameDecision decision) {
    switch (decision) {
      case RealtimeFrameDecision.accept:
        return; // ไม่ใช่การปฏิเสธ
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
    required int droppedFrameCount, // จำนวน drop (มาจากคิว)
    required DateTime now,
  }) {
    // ไม่มีตัวอย่าง -> คืนสแนปช็อตเริ่มต้น
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

    // รวบรวม latency แต่ละแบบจากตัวอย่างทั้งหมด
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
    required this.capturedAt, // เวลาที่เฟรมถูกจับภาพ
    required this.completedAt, // เวลาที่ประมวลผลเสร็จ
    required this.inferenceLatency, // เวลาที่ใช้ใน inference (โมเดล)
    required this.queueLatency, // เวลาที่อยู่ในคิวรอ
  });

  final DateTime capturedAt;
  final DateTime completedAt;
  final Duration inferenceLatency;
  final Duration queueLatency;
}

/// แปลงค่าเป็นมิลลิวินาทีเป็น Duration (กันค่าติดลบ/ลบที่ null)
Duration _durationFromMilliseconds(double? value) => Duration(
  microseconds: value == null ? 0 : math.max(0, (value * 1000).round()),
);

/// คำนวณผลต่าง "ไม่เป็นลบ" ระหว่าง 2 เวลา
/// (ถ้า later < earlier เช่นค่านาฬิกาไม่ตรง -> คืน Duration.zero)
Duration _nonNegativeDifference(DateTime later, DateTime earlier) {
  final difference = later.difference(earlier);
  return difference.isNegative ? Duration.zero : difference;
}

/// คำนวณ percentile ของชุด Duration (เช่น p95, p99)
Duration _percentile(List<Duration> values, double percentile) {
  if (values.isEmpty) return Duration.zero;
  final sorted = values.map((value) => value.inMicroseconds).toList()
    ..sort(); // เรียงจากน้อยไปมาก
  final index =
      (percentile * sorted.length).ceil().clamp(1, sorted.length) -
      1; // หา index เป้าหมาย
  return Duration(microseconds: sorted[index]);
}
