import 'package:ultralytics_yolo/models/yolo_task.dart';

enum ModelType {
  // detect('yolo11n', YOLOTask.detect),
  // segment('yolo11n-seg', YOLOTask.segment),
  // classify('yolo11n-cls', YOLOTask.classify),
  // pose('yolo11n-pose', YOLOTask.pose),
  // obb('yolo11n-obb', YOLOTask.obb),
  // bestFloat16(
  //   'assets/models/weights/best_saved_model/best_float16.tflite',
  //   YOLOTask.detect,
  // ),
  bestFloat16traffic(
    'assets/models/weights/best_float16_traffic.tflite',
    YOLOTask.detect,
  ),
  bestFloat16number(
    "assets/models/weights/best_float16_number.tflite",
    YOLOTask.detect,
  );

  final String modelName;
  final YOLOTask task;

  const ModelType(this.modelName, this.task);
}

enum SliderType { none, numItems, confidence, iou }
