import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/presentation/pages/video_inference_screen.dart';

void main() {
  test('video traffic and number models use separate native instances', () {
    final traffic = createVideoYolo('traffic.tflite');
    final number = createVideoYolo('number.tflite');

    expect(traffic.instanceId, isNot('default'));
    expect(number.instanceId, isNot('default'));
    expect(traffic.instanceId, isNot(number.instanceId));
  });
}
