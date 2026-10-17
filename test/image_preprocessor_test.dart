import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mangocounter/features/detection/data/image_preprocessor.dart';

void main() {
  test('ImagePreprocessor letterbox math', () async {
    // 4000x3000 image -> 640x640
    // scale = 640 / 4000 = 0.16
    // new width = 640, new height = 480
    // padX = 0, padY = (640 - 480) / 2 = 80

    final image = img.Image(width: 4000, height: 3000);
    final result =
        await ImagePreprocessor.preprocess(image, 640, normalize: true);

    expect(result.scale, closeTo(0.16, 0.001));
    expect(result.padX, 0);
    expect(result.padY, 80);

    // Check tensor size: 1 * 640 * 640 * 3
    expect(result.inputTensor.length, 640 * 640 * 3);
  });
}
