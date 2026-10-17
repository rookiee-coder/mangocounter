import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangocounter/features/detection/data/gemini_assistant_service.dart';
import 'package:mangocounter/features/detection/domain/detection.dart';
import 'package:mangocounter/features/detection/domain/mango_class.dart';

void main() {
  group('Gemini crop reconciliation unit tests (Requirement C & G)', () {
    const highConfBox = Detection(
      x1: 100,
      y1: 100,
      x2: 300,
      y2: 350,
      mangoClass: MangoClass.ripe,
      confidence: 0.70, // >= highConfKeep (0.50)
    );

    const lowConfBox = Detection(
      x1: 400,
      y1: 400,
      x2: 500,
      y2: 550,
      mangoClass: MangoClass.unripe,
      confidence: 0.30, // < highConfKeep (0.50)
    );

    test('1. High-conf YOLO box + Gemini says is_mango=false -> box is kept',
        () {
      final verdicts = {
        0: const CropVerdict(
          id: 0,
          isMango: false,
          ripeness: null,
          rawRipeness: 'unknown',
          reason: 'looks like a leaf cluster',
        ),
      };

      final result = GeminiAssistantService.reconcileCropVerdicts(
        yoloDetections: [highConfBox],
        cropVerdicts: verdicts,
        highConfKeep: 0.50,
        yoloClassKeepConf: 0.60,
      );

      expect(result.length, 1);
      expect(result.first.confidence, 0.70); // Preserves real YOLO score
      expect(result.first.mangoClass, MangoClass.ripe);
      expect(result.first.aiVerified, isTrue);
    });

    test('2. Gemini suspected non-mango stays counted for manual review', () {
      final verdicts = {
        0: const CropVerdict(
          id: 0,
          isMango: false,
          ripeness: null,
          rawRipeness: 'unknown',
          reason: 'branch background',
        ),
      };

      final result = GeminiAssistantService.reconcileCropVerdicts(
        yoloDetections: [lowConfBox],
        cropVerdicts: verdicts,
        highConfKeep: 0.50,
        yoloClassKeepConf: 0.60,
      );

      expect(result.length, 1);
      expect(result.single.x1, lowConfBox.x1);
      expect(result.single.mangoClass, lowConfBox.mangoClass);
      expect(result.single.aiVerified, isTrue);
      expect(result.single.aiFlaggedNonMango, isTrue);
      expect(result.single.needsReview, isTrue);
    });

    test(
        '3. Gemini returns unknown/malformed/missing id -> YOLO result unchanged',
        () {
      // CropVerdicts does not contain verdict for index 0 (e.g. missing id, parse error, timeout)
      final verdicts = <int, CropVerdict>{
        1: const CropVerdict(
          id: 1,
          isMango: true,
          ripeness: MangoClass.ripe,
          rawRipeness: 'ripe',
          reason: 'confirmed',
        ),
      };

      final result = GeminiAssistantService.reconcileCropVerdicts(
        yoloDetections: [highConfBox, lowConfBox],
        cropVerdicts: verdicts,
        highConfKeep: 0.50,
        yoloClassKeepConf: 0.60,
      );

      // Candidate 0 (highConfBox) was missing from verdicts -> kept exactly as-is
      expect(result.length, 2);
      expect(result[0].x1, highConfBox.x1);
      expect(result[0].confidence, highConfBox.confidence);
      expect(result[0].aiVerified, isFalse); // untouched
    });

    test(
        '4. YOLO ripe 0.9 vs Gemini unripe -> label stays ripe, needsReview=true',
        () {
      const veryConfidentRipe = Detection(
        x1: 50,
        y1: 50,
        x2: 200,
        y2: 250,
        mangoClass: MangoClass.ripe,
        confidence: 0.90, // >= yoloClassKeepConf (0.60)
      );

      final verdicts = {
        0: const CropVerdict(
          id: 0,
          isMango: true,
          ripeness: MangoClass.unripe, // Disagrees with YOLO
          rawRipeness: 'unripe',
          reason: 'mostly green tint',
        ),
      };

      final result = GeminiAssistantService.reconcileCropVerdicts(
        yoloDetections: [veryConfidentRipe],
        cropVerdicts: verdicts,
        highConfKeep: 0.50,
        yoloClassKeepConf: 0.60,
      );

      expect(result.length, 1);
      expect(result.first.mangoClass, MangoClass.ripe); // Keeps YOLO label
      expect(result.first.needsReview, isTrue); // Flagged for review
      expect(result.first.confidence, 0.90); // Real YOLO confidence preserved
      expect(result.first.aiVerified, isTrue);
    });

    test(
        '5. Gemini ripeness disagreement is shown as a suggestion, not applied',
        () {
      const lowConfRipe = Detection(
        x1: 50,
        y1: 50,
        x2: 200,
        y2: 250,
        mangoClass: MangoClass.ripe,
        confidence: 0.30, // < yoloClassKeepConf (0.60)
      );

      final verdicts = {
        0: const CropVerdict(
          id: 0,
          isMango: true,
          ripeness: MangoClass.over_ripe,
          rawRipeness: 'overripe',
          reason: 'visible brown rot',
        ),
      };

      final result = GeminiAssistantService.reconcileCropVerdicts(
        yoloDetections: [lowConfRipe],
        cropVerdicts: verdicts,
        highConfKeep: 0.50,
        yoloClassKeepConf: 0.60,
      );

      expect(result.length, 1);
      expect(
          result.first.mangoClass, MangoClass.ripe); // YOLO stays authoritative
      expect(result.first.aiSuggestedClass, MangoClass.over_ripe);
      expect(result.first.needsReview, isTrue);
      expect(result.first.confidence, 0.30); // Real YOLO score unchanged
    });

    test('6. Gemini request fails -> YOLO-only result returned', () {
      final fallback = GeminiAssistantService.buildFallbackResult(
        detections: [highConfBox, lowConfBox],
        providerName: 'Google Gemini Flash-Lite',
        summary: 'Network timeout',
        errorMessage: 'Connection failed',
        success: false,
      );

      expect(fallback.success, isFalse);
      expect(fallback.reconciledDetections.length, 2);
      expect(fallback.totalCount, 2);
      expect(
          fallback.reconciledDetections[0].confidence, highConfBox.confidence);
      expect(
          fallback.reconciledDetections[1].confidence, lowConfBox.confidence);
      expect(fallback.verifiedCount, 0);
      expect(fallback.rejectedCount, 0);
    });
  });

  group('Coordinate conversion & clamping tests (Requirement D & E)', () {
    test('Letterbox and un-letterbox roundtrip preservation', () {
      const origW = 3000;
      const origH = 4000;
      const targetSize = 640;

      // Scale factor = 640 / 4000 = 0.16
      const scale = targetSize / 4000.0;
      final newW = (origW * scale).round();
      final newH = (origH * scale).round();
      final padX = (targetSize - newW) ~/ 2;
      final padY = (targetSize - newH) ~/ 2;

      // A test box in original image space
      const origX1 = 500.0;
      const origY1 = 800.0;
      const origX2 = 1200.0;
      const origY2 = 1600.0;

      // Forward to model space
      final modelX1 = origX1 * scale + padX;
      final modelY1 = origY1 * scale + padY;
      final modelX2 = origX2 * scale + padX;
      final modelY2 = origY2 * scale + padY;

      // Inverse (un-letterbox) back to original space
      final unletterboxedX1 = (modelX1 - padX) / scale;
      final unletterboxedY1 = (modelY1 - padY) / scale;
      final unletterboxedX2 = (modelX2 - padX) / scale;
      final unletterboxedY2 = (modelY2 - padY) / scale;

      expect(unletterboxedX1, closeTo(origX1, 0.001));
      expect(unletterboxedY1, closeTo(origY1, 0.001));
      expect(unletterboxedX2, closeTo(origX2, 0.001));
      expect(unletterboxedY2, closeTo(origY2, 0.001));
    });

    test('Box and label clamping logic stays within image boundaries', () {
      // Simulate displayed image rect on screen (e.g. 300x500 letterboxed on a 400x600 screen)
      const displayedRect = Rect.fromLTWH(50, 50, 300, 500);

      // Raw un-clamped box touching and exceeding right and top edge
      const rawBoxRect = Rect.fromLTRB(40, 40, 370, 560);

      // Clamping rect
      final clampedBox = Rect.fromLTRB(
        rawBoxRect.left.clamp(displayedRect.left, displayedRect.right),
        rawBoxRect.top.clamp(displayedRect.top, displayedRect.bottom),
        rawBoxRect.right.clamp(displayedRect.left, displayedRect.right),
        rawBoxRect.bottom.clamp(displayedRect.top, displayedRect.bottom),
      );

      expect(clampedBox.left, greaterThanOrEqualTo(displayedRect.left));
      expect(clampedBox.top, greaterThanOrEqualTo(displayedRect.top));
      expect(clampedBox.right, lessThanOrEqualTo(displayedRect.right));
      expect(clampedBox.bottom, lessThanOrEqualTo(displayedRect.bottom));

      // Label clamping test: label above top edge must flip down or clamp inside
      const labelW = 120.0;
      const labelH = 24.0;
      double labelLeft = clampedBox.left;
      double labelTop = clampedBox.top - labelH;

      if (labelTop < displayedRect.top) {
        labelTop = clampedBox.top; // flip inside box
      }
      labelLeft = labelLeft.clamp(
          displayedRect.left,
          (displayedRect.right - labelW)
              .clamp(displayedRect.left, displayedRect.right));
      labelTop = labelTop.clamp(
          displayedRect.top,
          (displayedRect.bottom - labelH)
              .clamp(displayedRect.top, displayedRect.bottom));

      final labelRect = Rect.fromLTWH(labelLeft, labelTop, labelW, labelH);
      expect(labelRect.left, greaterThanOrEqualTo(displayedRect.left));
      expect(labelRect.top, greaterThanOrEqualTo(displayedRect.top));
      expect(labelRect.right, lessThanOrEqualTo(displayedRect.right));
      expect(labelRect.bottom, lessThanOrEqualTo(displayedRect.bottom));
    });
  });
}
