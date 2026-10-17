import 'package:flutter_test/flutter_test.dart';
import 'package:mangocounter/features/detection/domain/auto_confidence_calculator.dart';
import 'package:mangocounter/features/detection/domain/detection.dart';
import 'package:mangocounter/features/detection/domain/mango_class.dart';

void main() {
  group('AutoConfidenceCalculator Tests', () {
    test('Returns 0.15 fallback when detection list is empty', () {
      final conf = AutoConfidenceCalculator.calculate([]);
      expect(conf, 0.15);
    });

    test(
        'Automatically lowers threshold to 0.12 for difficult/dim/distant canopy scenes (max < 0.42)',
        () {
      final detections = [
        const Detection(
            x1: 10,
            y1: 10,
            x2: 50,
            y2: 50,
            mangoClass: MangoClass.unripe,
            confidence: 0.14),
        const Detection(
            x1: 60,
            y1: 60,
            x2: 100,
            y2: 100,
            mangoClass: MangoClass.unripe,
            confidence: 0.28),
        const Detection(
            x1: 110,
            y1: 110,
            x2: 150,
            y2: 150,
            mangoClass: MangoClass.unripe,
            confidence: 0.35),
      ];

      final conf = AutoConfidenceCalculator.calculate(detections);
      expect(conf, 0.12);

      final filtered =
          AutoConfidenceCalculator.filterDetections(detections, conf);
      expect(filtered.length, 3);
    });

    test(
        'Automatically lowers threshold to 0.12 when low-band canopy fruits outnumber high-band fruits',
        () {
      final detections = [
        // One clear mango
        const Detection(
            x1: 10,
            y1: 10,
            x2: 50,
            y2: 50,
            mangoClass: MangoClass.ripe,
            confidence: 0.65),
        // Three canopy / top-branch mangoes with low confidence
        const Detection(
            x1: 60,
            y1: 60,
            x2: 100,
            y2: 100,
            mangoClass: MangoClass.unripe,
            confidence: 0.13),
        const Detection(
            x1: 110,
            y1: 110,
            x2: 150,
            y2: 150,
            mangoClass: MangoClass.unripe,
            confidence: 0.15),
        const Detection(
            x1: 160,
            y1: 160,
            x2: 200,
            y2: 200,
            mangoClass: MangoClass.unripe,
            confidence: 0.18),
      ];

      final conf = AutoConfidenceCalculator.calculate(detections);
      expect(conf, 0.12);

      final filtered =
          AutoConfidenceCalculator.filterDetections(detections, conf);
      expect(filtered.length, 4);
    });

    test(
        'Adapts to 0.20 for clean foreground scenes with strong detections and filters noise < 0.20',
        () {
      final detections = [
        const Detection(
            x1: 10,
            y1: 10,
            x2: 50,
            y2: 50,
            mangoClass: MangoClass.ripe,
            confidence: 0.85),
        const Detection(
            x1: 60,
            y1: 60,
            x2: 100,
            y2: 100,
            mangoClass: MangoClass.ripe,
            confidence: 0.75),
        const Detection(
            x1: 110,
            y1: 110,
            x2: 150,
            y2: 150,
            mangoClass: MangoClass.unripe,
            confidence: 0.60),
        const Detection(
            x1: 160,
            y1: 160,
            x2: 200,
            y2: 200,
            mangoClass: MangoClass.unripe,
            confidence: 0.55),
        // Background noise artifact
        const Detection(
            x1: 210,
            y1: 210,
            x2: 250,
            y2: 250,
            mangoClass: MangoClass.unripe,
            confidence: 0.08),
      ];

      final conf = AutoConfidenceCalculator.calculate(detections);
      expect(conf, 0.20);

      final filtered =
          AutoConfidenceCalculator.filterDetections(detections, conf);
      expect(filtered.length, 4);
      expect(filtered.any((d) => d.confidence == 0.08), isFalse);
    });

    test(
        'Always preserves user-edited and AI-verified fruits even if their score is below threshold',
        () {
      const userDet = Detection(
        x1: 10,
        y1: 10,
        x2: 50,
        y2: 50,
        mangoClass: MangoClass.unripe,
        confidence: 0.05,
        userEdited: true,
      );
      const aiDet = Detection(
        x1: 60,
        y1: 60,
        x2: 100,
        y2: 100,
        mangoClass: MangoClass.ripe,
        confidence: 0.09,
        aiVerified: true,
      );
      const noiseDet = Detection(
        x1: 110,
        y1: 110,
        x2: 150,
        y2: 150,
        mangoClass: MangoClass.unripe,
        confidence: 0.09,
      );

      final filtered = AutoConfidenceCalculator.filterDetections(
          [userDet, aiDet, noiseDet], 0.20);
      expect(filtered.length, 2);
      expect(filtered.contains(userDet), isTrue);
      expect(filtered.contains(aiDet), isTrue);
      expect(filtered.contains(noiseDet), isFalse);
    });

    test(
        'Filters solitary faint false positive (e.g. human hand / non-orchard object with conf < 0.35)',
        () {
      const solitaryHandFalseAlarm = Detection(
        x1: 100,
        y1: 100,
        x2: 300,
        y2: 400,
        mangoClass: MangoClass.ripe,
        confidence: 0.28,
      );

      final conf = AutoConfidenceCalculator.calculate([solitaryHandFalseAlarm]);
      expect(conf, 0.35);

      final filtered = AutoConfidenceCalculator.filterDetections(
          [solitaryHandFalseAlarm], conf);
      expect(filtered.isEmpty, isTrue);
    });
  });
}
