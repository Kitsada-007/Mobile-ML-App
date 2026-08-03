import 'dart:collection';
import 'dart:math' as math;

import 'package:trffic_ilght_app/features/camera_detection/data/models/realtime_inference.dart';

const Duration defaultRealtimeMaximumFrameAge = Duration(milliseconds: 1500);

enum RealtimeFrameDecision { accept, stale, outOfOrder }

class RealtimeFrameFreshnessGuard {
  RealtimeFrameFreshnessGuard({
    this.maximumFrameAge = defaultRealtimeMaximumFrameAge,
  });

  final Duration maximumFrameAge;
  int? _lastAcceptedFrameNumber;

  int? get lastAcceptedFrameNumber => _lastAcceptedFrameNumber;

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

  double get droppedFrameRatio {
    final total = processedFrameCount + droppedFrameCount;
    return total == 0 ? 0 : droppedFrameCount / total;
  }
}

class RealtimePipelineMonitor {
  RealtimePipelineMonitor({this.maximumSamples = 120})
    : assert(maximumSamples > 0);

  final int maximumSamples;
  final Queue<_RealtimePipelineSample> _samples = Queue();
  int _processedFrameCount = 0;
  int _staleFrameCount = 0;
  int _outOfOrderFrameCount = 0;

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

  void reset() {
    _samples.clear();
    _processedFrameCount = 0;
    _staleFrameCount = 0;
    _outOfOrderFrameCount = 0;
  }
}

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

Duration _durationFromMilliseconds(double? value) => Duration(
  microseconds: value == null ? 0 : math.max(0, (value * 1000).round()),
);

Duration _nonNegativeDifference(DateTime later, DateTime earlier) {
  final difference = later.difference(earlier);
  return difference.isNegative ? Duration.zero : difference;
}

Duration _percentile(List<Duration> values, double percentile) {
  if (values.isEmpty) return Duration.zero;
  final sorted = values.map((value) => value.inMicroseconds).toList()..sort();
  final index = (percentile * sorted.length).ceil().clamp(1, sorted.length) - 1;
  return Duration(microseconds: sorted[index]);
}
