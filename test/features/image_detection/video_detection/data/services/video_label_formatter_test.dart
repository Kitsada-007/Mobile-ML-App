import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/features/video_detection/data/services/video_label_formatter.dart';

void main() {
  test('formats known traffic labels and preserves unknown labels', () {
    expect(videoFormalThaiName('red_light_circle'), 'สัญญาณไฟจราจรสีแดง');
    expect(videoFormalThaiName('unknown_label'), 'unknown_label');
  });
}
