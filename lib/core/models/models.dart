import 'package:ultralytics_yolo/models/yolo_task.dart';

enum ModelType {
  bestFloat16traffic(
    'traffic',
    'assets/models/best_float16New.tflite',
    YOLOTask.detect,
  ),
  bestFloat16number(
    'number',
    'assets/models/best_float16_number.tflite',
    YOLOTask.detect,
  );

  final String remoteId;
  final String modelName;
  final YOLOTask task;

  const ModelType(this.remoteId, this.modelName, this.task);
}

enum SliderType { none, numItems, confidence, iou }
