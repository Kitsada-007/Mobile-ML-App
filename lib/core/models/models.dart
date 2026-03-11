import 'package:ultralytics_yolo/models/yolo_task.dart';

enum ModelType {
  bestFloat16traffic(
    'assets/models/best_float16_traffic.tflite',
    YOLOTask.detect,
  ),
  bestFloat16number(
    'assets/models/best_float16_traffic.tflite',
    YOLOTask.detect,
  );

  final String modelName;
  final YOLOTask task;

  const ModelType(this.modelName, this.task);
}

enum SliderType { none, numItems, confidence, iou }
