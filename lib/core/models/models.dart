import 'package:ultralytics_yolo/models/yolo_task.dart';

enum ModelType {
  traffic(
    'traffic',
    'assets/models/traffic_model_v1_2_0.tflite',
    YOLOTask.detect,
  ),
  number('number', 'assets/models/number_model_v1_2_1.tflite', YOLOTask.detect);

  final String remoteId;
  final String modelName;
  final YOLOTask task;

  const ModelType(this.remoteId, this.modelName, this.task);
}

enum SliderType { none, numItems, confidence, iou }
