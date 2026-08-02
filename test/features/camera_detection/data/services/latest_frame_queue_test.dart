import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/features/camera_detection/data/services/latest_frame_queue.dart';

void main() {
  test(
    'processes the active item and keeps only the latest pending item',
    () async {
      final firstItemStarted = Completer<void>();
      final releaseFirstItem = Completer<void>();
      final processedItems = <int>[];

      final queue = LatestFrameQueue<int>(
        processor: (item) async {
          if (item == 1) {
            firstItemStarted.complete();
            await releaseFirstItem.future;
          }
          processedItems.add(item);
        },
      );

      final drain = queue.submit(1);
      await firstItemStarted.future;
      unawaited(queue.submit(2));
      unawaited(queue.submit(3));
      releaseFirstItem.complete();
      await drain;

      expect(processedItems, [1, 3]);
      expect(queue.droppedCount, 1);
    },
  );

  test('dispose clears the pending item and rejects new items', () async {
    final firstItemStarted = Completer<void>();
    final releaseFirstItem = Completer<void>();
    final processedItems = <int>[];

    final queue = LatestFrameQueue<int>(
      processor: (item) async {
        if (item == 1) {
          firstItemStarted.complete();
          await releaseFirstItem.future;
        }
        processedItems.add(item);
      },
    );

    final drain = queue.submit(1);
    await firstItemStarted.future;
    unawaited(queue.submit(2));
    queue.dispose();
    await queue.submit(3);
    releaseFirstItem.complete();
    await drain;

    expect(processedItems, [1]);
  });
}
