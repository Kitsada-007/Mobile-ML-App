import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/features/camera_detection/data/models/realtime_inference.dart';
import 'package:trffic_ilght_app/features/camera_detection/data/services/realtime_pipeline_monitor.dart';

void main() {
  group('RealtimeFrameFreshnessGuard', () {
    final capturedAt = DateTime(2026, 8, 3, 12);

    test('accepts a fresh frame with an increasing frame number', () {
      final guard = RealtimeFrameFreshnessGuard(
        maximumFrameAge: const Duration(milliseconds: 500),
      );

      final decision = guard.evaluate(
        _packet(frameNumber: 4, capturedAt: capturedAt),
        now: capturedAt.add(const Duration(milliseconds: 120)),
      );

      expect(decision, RealtimeFrameDecision.accept);
      expect(guard.lastAcceptedFrameNumber, 4);
    });

    test('rejects a frame whose capture estimate is older than the TTL', () {
      final guard = RealtimeFrameFreshnessGuard(
        maximumFrameAge: const Duration(milliseconds: 500),
      );

      final decision = guard.evaluate(
        _packet(frameNumber: 4, capturedAt: capturedAt),
        now: capturedAt.add(const Duration(milliseconds: 501)),
      );

      expect(decision, RealtimeFrameDecision.stale);
      expect(guard.lastAcceptedFrameNumber, isNull);
    });

    test('rejects duplicate and out-of-order frame numbers', () {
      final guard = RealtimeFrameFreshnessGuard();
      final first = _packet(frameNumber: 10, capturedAt: capturedAt);
      final duplicate = _packet(
        frameNumber: 10,
        capturedAt: capturedAt.add(const Duration(milliseconds: 50)),
      );

      expect(
        guard.evaluate(first, now: capturedAt),
        RealtimeFrameDecision.accept,
      );
      expect(
        guard.evaluate(
          duplicate,
          now: capturedAt.add(const Duration(milliseconds: 50)),
        ),
        RealtimeFrameDecision.outOfOrder,
      );
    });
  });

  test('summarizes end-to-end latency percentiles and rejected frames', () {
    final monitor = RealtimePipelineMonitor(maximumSamples: 10);
    final capturedAt = DateTime(2026, 8, 3, 12);

    for (var index = 1; index <= 5; index++) {
      final packet = _packet(
        frameNumber: index,
        capturedAt: capturedAt,
        receivedAt: capturedAt.add(Duration(milliseconds: index * 10)),
        inferenceMilliseconds: index * 2,
      );
      monitor.recordProcessed(
        packet,
        processingStartedAt: packet.receivedAt.add(
          const Duration(milliseconds: 5),
        ),
        completedAt: capturedAt.add(Duration(milliseconds: index * 100)),
      );
    }
    monitor.recordRejected(RealtimeFrameDecision.stale);
    monitor.recordRejected(RealtimeFrameDecision.outOfOrder);

    final snapshot = monitor.snapshot(
      droppedFrameCount: 3,
      now: capturedAt.add(const Duration(milliseconds: 600)),
    );

    expect(snapshot.processedFrameCount, 5);
    expect(snapshot.staleFrameCount, 1);
    expect(snapshot.outOfOrderFrameCount, 1);
    expect(snapshot.droppedFrameCount, 3);
    expect(snapshot.endToEndLatencyP50.inMilliseconds, 300);
    expect(snapshot.endToEndLatencyP95.inMilliseconds, 500);
    expect(snapshot.endToEndLatencyP99.inMilliseconds, 500);
    expect(snapshot.inferenceLatencyP95.inMilliseconds, 10);
    expect(snapshot.latestFrameAge.inMilliseconds, 600);
  });

  test('keeps a cumulative processed count beyond the latency window', () {
    final monitor = RealtimePipelineMonitor(maximumSamples: 2);
    final capturedAt = DateTime(2026, 8, 3, 12);

    for (var index = 1; index <= 3; index++) {
      final packet = _packet(frameNumber: index, capturedAt: capturedAt);
      monitor.recordProcessed(
        packet,
        processingStartedAt: capturedAt,
        completedAt: capturedAt.add(Duration(milliseconds: index * 10)),
      );
    }

    final snapshot = monitor.snapshot(
      droppedFrameCount: 1,
      now: capturedAt.add(const Duration(milliseconds: 40)),
    );

    expect(snapshot.processedFrameCount, 3);
    expect(snapshot.droppedFrameRatio, closeTo(0.25, 0.0001));
    expect(snapshot.endToEndLatencyP50.inMilliseconds, 20);
  });
}

RealtimeFramePacket _packet({
  required int frameNumber,
  required DateTime capturedAt,
  DateTime? receivedAt,
  int inferenceMilliseconds = 0,
}) {
  return RealtimeFramePacket(
    frameNumber: frameNumber,
    resultProducedAt: capturedAt,
    estimatedCapturedAt: capturedAt,
    receivedAt: receivedAt ?? capturedAt,
    detections: const [],
    inferenceMilliseconds: inferenceMilliseconds.toDouble(),
  );
}
