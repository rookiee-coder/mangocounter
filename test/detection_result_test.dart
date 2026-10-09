import 'package:flutter_test/flutter_test.dart';
import 'package:mangocounter/features/detection/domain/detection.dart';
import 'package:mangocounter/features/detection/domain/detection_result.dart';
import 'package:mangocounter/features/detection/domain/mango_class.dart';

void main() {
  test('DetectionResult counts correctly', () {
    const result = DetectionResult(
      detections: [
        Detection(x1: 0, y1: 0, x2: 10, y2: 10, mangoClass: MangoClass.ripe, confidence: 0.9),
        Detection(x1: 0, y1: 0, x2: 10, y2: 10, mangoClass: MangoClass.unripe, confidence: 0.9),
        Detection(x1: 0, y1: 0, x2: 10, y2: 10, mangoClass: MangoClass.ripe, confidence: 0.9),
        Detection(x1: 0, y1: 0, x2: 10, y2: 10, mangoClass: MangoClass.over_ripe, confidence: 0.85),
      ],
      imageWidth: 640,
      imageHeight: 640,
      inferenceTimeMs: 10,
      preprocessTimeMs: 5,
      postprocessTimeMs: 2,
      confThreshold: 0.4,
      iouThreshold: 0.45,
      modelInputSize: 640,
    );

    expect(result.ripeCount, 2);
    expect(result.unripeCount, 1);
    expect(result.overRipeCount, 1);
    expect(result.totalCount, 4);
  });
}
