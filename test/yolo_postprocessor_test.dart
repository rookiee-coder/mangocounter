import 'package:flutter_test/flutter_test.dart';
import 'package:mangocounter/features/detection/data/yolo_postprocessor.dart';
import 'package:mangocounter/features/detection/domain/mango_class.dart';

void main() {
  test('NMS suppresses overlapping boxes of same class', () {
    // We can test this by passing synthetic model output
    // Format [1, 6, 8400]
    
    // Let's craft a synthetic tensor.
    // Two highly overlapping boxes for ripe mango.
    // cx, cy, w, h, class0, class1
    // Box 1: (cx=320, cy=320, w=100, h=100, c0=0.9, c1=0.1) -> x1=270, x2=370, y1=270, y2=370
    // Box 2: (cx=322, cy=322, w=100, h=100, c0=0.8, c1=0.1) -> overlapping, should be suppressed.
    // Box 3: (cx=500, cy=500, w=50, h=50, c0=0.1, c1=0.8) -> unripe mango, keep.

    List<dynamic> outputTensor = [
      [
        [320.0, 322.0, 500.0, 0.0, 0.0, 0.0, 0.0], // cx
        [320.0, 322.0, 500.0, 0.0, 0.0, 0.0, 0.0], // cy
        [100.0, 100.0, 50.0,  0.0, 0.0, 0.0, 0.0],  // w
        [100.0, 100.0, 50.0,  0.0, 0.0, 0.0, 0.0],  // h
        [0.9, 0.8, 0.1,       0.0, 0.0, 0.0, 0.0],       // class0
        [0.1, 0.1, 0.8,       0.0, 0.0, 0.0, 0.0],       // class1
      ]
    ];

    final result = YoloPostprocessor.processSync(
      outputTensor,
      confThreshold: 0.40,
      iouThreshold: 0.45,
      scale: 1.0,
      padX: 0,
      padY: 0,
      originalWidth: 640,
      originalHeight: 640,
      modelInputSize: 640,
    );

    expect(result.length, 2);
    
    // First should be the high confidence over_ripe/half_ripe mango (class0)
    expect(result[0].mangoClass, MangoClass.half_ripe);
    expect(result[0].confidence, 0.9);
    
    // Second should be ripe mango (class1)
    expect(result[1].mangoClass, MangoClass.ripe);
    expect(result[1].confidence, 0.8);
  });
}
