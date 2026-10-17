import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../domain/detection.dart';
import '../domain/detection_result.dart';
import '../domain/detector.dart';
import '../domain/mango_class.dart';

class DemoDetector implements Detector {
  @override
  Future<void> init() async {}

  @override
  Future<DetectionResult> detect(
    Uint8List imageBytes, {
    double confThreshold = 0.40,
    double iouThreshold = 0.45,
    bool enableTiling = true,
  }) async {
    return await compute(_demoDetect, {
      'imageBytes': imageBytes,
      'confThreshold': confThreshold,
    });
  }

  static DetectionResult _demoDetect(Map<String, dynamic> args) {
    final Uint8List bytes = args['imageBytes'];
    final double confThreshold = args['confThreshold'];

    img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Decode failed');
    decoded = img.bakeOrientation(decoded);

    final w = decoded.width;
    final h = decoded.height;

    final List<Detection> fakeDetections = [];

    // Add some fake boxes if threshold allows
    if (0.85 >= confThreshold) {
      fakeDetections.add(Detection(
        x1: w * 0.2,
        y1: h * 0.2,
        x2: w * 0.4,
        y2: h * 0.4,
        mangoClass: MangoClass.ripe,
        confidence: 0.85,
      ));
    }
    if (0.65 >= confThreshold) {
      fakeDetections.add(Detection(
        x1: w * 0.5,
        y1: h * 0.5,
        x2: w * 0.7,
        y2: h * 0.7,
        mangoClass: MangoClass.unripe,
        confidence: 0.65,
      ));
    }
    if (0.45 >= confThreshold) {
      fakeDetections.add(Detection(
        x1: w * 0.6,
        y1: h * 0.1,
        x2: w * 0.8,
        y2: h * 0.3,
        mangoClass: MangoClass.ripe,
        confidence: 0.45,
      ));
    }

    return DetectionResult(
      detections: fakeDetections,
      imageWidth: w,
      imageHeight: h,
      inferenceTimeMs: 15,
      preprocessTimeMs: 10,
      postprocessTimeMs: 5,
      confThreshold: confThreshold,
      iouThreshold: 0.45,
      modelInputSize: 640,
    );
  }

  @override
  void dispose() {}
}
