import 'detection.dart';
import 'mango_class.dart';

class DetectionResult {
  final List<Detection> detections;
  final int imageWidth;
  final int imageHeight;
  final int inferenceTimeMs;
  final int preprocessTimeMs;
  final int postprocessTimeMs;
  final double confThreshold;
  final double iouThreshold;
  final int modelInputSize;
  final String debugString;

  const DetectionResult({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
    required this.inferenceTimeMs,
    required this.preprocessTimeMs,
    required this.postprocessTimeMs,
    required this.confThreshold,
    required this.iouThreshold,
    required this.modelInputSize,
    this.debugString = '',
  });

  int get overRipeCount => detections.where((d) => d.mangoClass == MangoClass.over_ripe).length;
  int get halfRipeCount => overRipeCount;
  int get ripeCount => detections.where((d) => d.mangoClass == MangoClass.ripe).length;
  int get unripeCount => detections.where((d) => d.mangoClass == MangoClass.unripe).length;
  int get totalCount => detections.length;
}
