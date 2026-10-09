import 'dart:typed_data';
import 'detection_result.dart';

abstract class Detector {
  Future<void> init();
  Future<DetectionResult> detect(
    Uint8List imageBytes, {
    double confThreshold = 0.40,
    double iouThreshold = 0.45,
    bool enableTiling = true,
  });
  void dispose();
}
