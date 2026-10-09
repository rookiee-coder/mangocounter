import 'package:flutter_test/flutter_test.dart';
import 'package:mangocounter/features/detection/data/gemini_assistant_service.dart';
import 'package:mangocounter/features/detection/domain/detection.dart';
import 'package:mangocounter/features/detection/domain/mango_class.dart';

void main() {
  group('AI Per-Crop Reconciliation Edge Cases', () {
    const mangoA = Detection(
      x1: 100,
      y1: 100,
      x2: 200,
      y2: 220,
      mangoClass: MangoClass.ripe,
      confidence: 0.80,
    );

    const mangoB = Detection(
      x1: 400,
      y1: 400,
      x2: 500,
      y2: 520,
      mangoClass: MangoClass.unripe,
      confidence: 0.55,
    );

    const lowConfNoise = Detection(
      x1: 600,
      y1: 100,
      x2: 900,
      y2: 500,
      mangoClass: MangoClass.ripe,
      confidence: 0.45,
    );

    test('User manually added box is strictly preserved regardless of AI verdict', () {
      const userBox = Detection(
        x1: 10,
        y1: 10,
        x2: 80,
        y2: 90,
        mangoClass: MangoClass.ripe,
        confidence: 0.95,
        userEdited: true,
      );

      final verdicts = {
        0: const CropVerdict(
          id: 0,
          isMango: false,
          ripeness: null,
          rawRipeness: 'unknown',
          reason: 'leaf cluster',
        ),
      };

      final result = GeminiAssistantService.reconcileCropVerdicts(
        yoloDetections: [userBox],
        cropVerdicts: verdicts,
      );

      expect(result.length, 1);
      expect(result.first.userEdited, isTrue);
      expect(result.first.mangoClass, MangoClass.ripe);
    });

    test('Multiple candidates: low confidence non-mango dropped, high confidence kept', () {
      final verdicts = {
        0: const CropVerdict(
          id: 0,
          isMango: true,
          ripeness: MangoClass.ripe,
          rawRipeness: 'ripe',
          reason: 'healthy yellow mango',
        ),
        1: const CropVerdict(
          id: 1,
          isMango: true,
          ripeness: MangoClass.unripe,
          rawRipeness: 'unripe',
          reason: 'green fruit',
        ),
        2: const CropVerdict(
          id: 2,
          isMango: false,
          ripeness: null,
          rawRipeness: 'unknown',
          reason: 'branch shadow',
        ),
      };

      final result = GeminiAssistantService.reconcileCropVerdicts(
        yoloDetections: [mangoA, mangoB, lowConfNoise],
        cropVerdicts: verdicts,
      );

      // mangoA kept (high-conf, confirmed ripe)
      // mangoB kept (conf 0.55 >= 0.50, confirmed unripe)
      // lowConfNoise dropped (conf 0.45 < 0.50, isMango == false)
      expect(result.length, 2);
      expect(result.any((d) => d.x1 == lowConfNoise.x1), isFalse);
    });

    test('Gemini unknown ripeness keeps original YOLO class', () {
      final verdicts = {
        0: const CropVerdict(
          id: 0,
          isMango: true,
          ripeness: null, // unknown
          rawRipeness: 'unknown',
          reason: 'shadowed view',
        ),
      };

      final result = GeminiAssistantService.reconcileCropVerdicts(
        yoloDetections: [mangoA],
        cropVerdicts: verdicts,
      );

      expect(result.length, 1);
      expect(result.first.mangoClass, MangoClass.ripe); // Kept YOLO class
      expect(result.first.needsReview, isFalse);
    });

    test('Bounding box coordinates are never mutated by Gemini verification', () {
      final verdicts = {
        0: const CropVerdict(
          id: 0,
          isMango: true,
          ripeness: MangoClass.ripe,
          rawRipeness: 'ripe',
          reason: 'perfect mango',
        ),
      };

      final result = GeminiAssistantService.reconcileCropVerdicts(
        yoloDetections: [mangoA],
        cropVerdicts: verdicts,
      );

      expect(result.first.x1, mangoA.x1);
      expect(result.first.y1, mangoA.y1);
      expect(result.first.x2, mangoA.x2);
      expect(result.first.y2, mangoA.y2);
    });
  });
}
