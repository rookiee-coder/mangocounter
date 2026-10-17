import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';

class PreprocessResult {
  final Float32List inputTensor;
  final double scale;
  final int padX;
  final int padY;

  PreprocessResult({
    required this.inputTensor,
    required this.scale,
    required this.padX,
    required this.padY,
  });
}

class ImagePreprocessor {
  /// Letterboxes an image into [targetSize]x[targetSize] with padding color (114,114,114).
  /// Converts to RGB Float32List, scaled to 0-1 if [normalize] is true.
  static Future<PreprocessResult> preprocess(img.Image image, int targetSize,
      {bool normalize = true}) async {
    return await compute(_preprocessTask, {
      'image': image,
      'targetSize': targetSize,
      'normalize': normalize,
    });
  }

  static PreprocessResult _preprocessTask(Map<String, dynamic> args) {
    final img.Image image = args['image'];
    final int targetSize = args['targetSize'];
    final bool normalize = args['normalize'];

    final int width = image.width;
    final int height = image.height;

    // Calculate scale and padding
    final double scale = targetSize / (width > height ? width : height);
    final int newWidth = (width * scale).round();
    final int newHeight = (height * scale).round();

    final int padX = (targetSize - newWidth) ~/ 2;
    final int padY = (targetSize - newHeight) ~/ 2;

    // Resize image
    final img.Image resized =
        img.copyResize(image, width: newWidth, height: newHeight);

    // Create a new target image with padding
    final img.Image padded = img.Image(width: targetSize, height: targetSize);
    img.fill(padded, color: img.ColorInt8.rgb(114, 114, 114));

    // Draw the resized image onto the padded canvas
    img.compositeImage(padded, resized, dstX: padX, dstY: padY);

    // Convert to Float32List
    final Float32List inputTensor =
        Float32List(1 * targetSize * targetSize * 3);
    int bufferIndex = 0;

    // Iterate over pixels. Image is in NHWC format (1, H, W, C)
    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        final img.Pixel pixel = padded.getPixel(x, y);
        if (normalize) {
          inputTensor[bufferIndex++] = pixel.r / 255.0;
          inputTensor[bufferIndex++] = pixel.g / 255.0;
          inputTensor[bufferIndex++] = pixel.b / 255.0;
        } else {
          inputTensor[bufferIndex++] = pixel.r.toDouble();
          inputTensor[bufferIndex++] = pixel.g.toDouble();
          inputTensor[bufferIndex++] = pixel.b.toDouble();
        }
      }
    }

    return PreprocessResult(
      inputTensor: inputTensor,
      scale: scale,
      padX: padX,
      padY: padY,
    );
  }
}
