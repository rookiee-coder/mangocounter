import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import '../errors/app_exception.dart';

class ImageUtils {
  /// Loads an image, applies EXIF rotation, and optionally downscales to save memory.
  static Future<img.Image> loadAndPrepareImage(Uint8List bytes, {int maxResolution = 1920}) async {
    return await compute(_processImage, {'bytes': bytes, 'maxResolution': maxResolution});
  }

  static img.Image _processImage(Map<String, dynamic> args) {
    final Uint8List bytes = args['bytes'];
    final int maxResolution = args['maxResolution'];

    // We decode the image. The image package applies EXIF rotation if we use decodeImage.
    
    // We decode the image. The image package applies EXIF rotation if we use decodeImage.
    // Actually, decodeImage handles basic decoding. We should bake orientation explicitly.
    img.Image? decoded = img.decodeImage(bytes);
    
    if (decoded == null) {
      throw AppException('Unsupported or corrupted image format.');
    }

    // Bake orientation
    decoded = img.bakeOrientation(decoded);

    // Downscale if necessary to save memory
    if (decoded.width > maxResolution || decoded.height > maxResolution) {
      final double ratio = maxResolution / (decoded.width > decoded.height ? decoded.width : decoded.height);
      final int newWidth = (decoded.width * ratio).round();
      final int newHeight = (decoded.height * ratio).round();
      decoded = img.copyResize(decoded, width: newWidth, height: newHeight);
    }

    return decoded;
  }
}
