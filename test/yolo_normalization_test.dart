import 'package:flutter_test/flutter_test.dart';
import 'package:mangocounter/features/detection/domain/detection.dart';
import 'package:mangocounter/features/detection/domain/mango_class.dart';

void main() {
  group('YOLO Normalization Math & Indices', () {
    test('Calculates normalized YOLO box coordinates correctly', () {
      const int imageWidth = 1000;
      const int imageHeight = 500;

      const det = Detection(
        x1: 100,
        y1: 100,
        x2: 300,
        y2: 200,
        mangoClass: MangoClass.ripe,
        confidence: 0.95,
      );

      final double cx = (((det.x1 + det.x2) / 2.0) / imageWidth).clamp(0.0, 1.0);
      final double cy = (((det.y1 + det.y2) / 2.0) / imageHeight).clamp(0.0, 1.0);
      final double w = ((det.x2 - det.x1) / imageWidth).clamp(0.0, 1.0);
      final double h = ((det.y2 - det.y1) / imageHeight).clamp(0.0, 1.0);

      expect(cx, closeTo(0.2, 0.001)); // (100+300)/2 / 1000 = 200/1000 = 0.2
      expect(cy, closeTo(0.3, 0.001)); // (100+200)/2 / 500 = 150/500 = 0.3
      expect(w, closeTo(0.2, 0.001));  // 200/1000 = 0.2
      expect(h, closeTo(0.2, 0.001));  // 100/500 = 0.2
      expect(det.mangoClass.index, 1); // 1 = Ripe
    });

    test('Class indices strictly align to labels.txt (0: Over ripe, 1: Ripe, 2: Unripe)', () {
      expect(MangoClass.over_ripe.index, 0);
      expect(MangoClass.ripe.index, 1);
      expect(MangoClass.unripe.index, 2);
    });
  });
}
