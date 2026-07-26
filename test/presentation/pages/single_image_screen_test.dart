import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/presentation/pages/single_image_screen.dart';

void main() {
  test(
    'single-image traffic and number models use separate native instances',
    () {
      final traffic = createSingleImageYolo('traffic.tflite');
      final number = createSingleImageYolo('number.tflite');

      expect(traffic.instanceId, isNot('default'));
      expect(number.instanceId, isNot('default'));
      expect(traffic.instanceId, isNot(number.instanceId));
    },
  );
}
