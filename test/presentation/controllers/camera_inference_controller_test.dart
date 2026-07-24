import 'package:flutter_test/flutter_test.dart';
import 'package:trffic_ilght_app/presentation/controllers/camera_inference_controller.dart';

void main() {
  test('accepts the first valid countdown reading immediately', () {
    expect(acceptCountdownReading('12'), '12');
  });

  test('ignores an empty countdown reading', () {
    expect(acceptCountdownReading(''), isNull);
    expect(acceptCountdownReading(null), isNull);
  });
}
