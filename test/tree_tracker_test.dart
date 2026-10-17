import 'package:flutter_test/flutter_test.dart';
import 'package:mangocounter/features/detection/domain/detection.dart';
import 'package:mangocounter/features/detection/domain/mango_class.dart';
import 'package:mangocounter/features/video_scan/data/tree_tracker.dart';

void main() {
  group('TreeTracker Geometry Filtering Tests', () {
    test('Accepts valid mango-proportioned bounding box', () {
      const validMango = Detection(
        x1: 100,
        y1: 100,
        x2: 180,
        y2: 200, // width=80, height=100 -> aspect=0.8
        mangoClass: MangoClass.unripe,
        confidence: 0.85,
      );

      final isValid = TreeTracker.isValidMangoGeometry(validMango, 1080, 1920);
      expect(isValid, isTrue);
    });

    test('Rejects flat leaf or outstretched arm (aspect ratio > 2.2)', () {
      const flatLeafOrHand = Detection(
        x1: 50,
        y1: 200,
        x2: 350,
        y2: 260, // width=300, height=60 -> aspect=5.0
        mangoClass: MangoClass.unripe,
        confidence: 0.60,
      );

      final isValid =
          TreeTracker.isValidMangoGeometry(flatLeafOrHand, 1080, 1920);
      expect(isValid, isFalse);
    });

    test(
        'Rejects elongated vertical branch or trunk strip (aspect ratio < 0.45)',
        () {
      const verticalBranch = Detection(
        x1: 200,
        y1: 50,
        x2: 240,
        y2: 300, // width=40, height=250 -> aspect=0.16
        mangoClass: MangoClass.unripe,
        confidence: 0.55,
      );

      final isValid =
          TreeTracker.isValidMangoGeometry(verticalBranch, 1080, 1920);
      expect(isValid, isFalse);
    });

    test('Rejects bottom ground edge clutter / dirt artifact', () {
      const groundClutter = Detection(
        x1: 100,
        y1: 950,
        x2: 280,
        y2: 1000, // y1=950 is > 92% of 1000, aspect=180/50=3.6
        mangoClass: MangoClass.ripe,
        confidence: 0.45,
      );

      final isValid =
          TreeTracker.isValidMangoGeometry(groundClutter, 1000, 1000);
      expect(isValid, isFalse);
    });

    test('Rejects massive bounding box covering majority of frame (> 65% area)',
        () {
      const giantArtifact = Detection(
        x1: 50,
        y1: 50,
        x2: 950,
        y2: 950, // 900x900 = 810,000 / 1,000,000 = 81%
        mangoClass: MangoClass.unripe,
        confidence: 0.70,
      );

      final isValid =
          TreeTracker.isValidMangoGeometry(giantArtifact, 1000, 1000);
      expect(isValid, isFalse);
    });
  });

  group('TreeTracker IoU Tests', () {
    test('Computes 1.0 for identical boxes', () {
      const boxA = Detection(
          x1: 10,
          y1: 10,
          x2: 50,
          y2: 50,
          mangoClass: MangoClass.ripe,
          confidence: 0.9);
      const boxB = Detection(
          x1: 10,
          y1: 10,
          x2: 50,
          y2: 50,
          mangoClass: MangoClass.unripe,
          confidence: 0.8);

      final iou = TreeTracker.computeIoU(boxA, boxB);
      expect(iou, closeTo(1.0, 0.0001));
    });

    test('Computes 0.0 for disjoint non-overlapping boxes', () {
      const boxA = Detection(
          x1: 0,
          y1: 0,
          x2: 10,
          y2: 10,
          mangoClass: MangoClass.ripe,
          confidence: 0.9);
      const boxB = Detection(
          x1: 20,
          y1: 20,
          x2: 30,
          y2: 30,
          mangoClass: MangoClass.ripe,
          confidence: 0.8);

      final iou = TreeTracker.computeIoU(boxA, boxB);
      expect(iou, 0.0);
    });

    test('Computes correct overlap for 50% shifted boxes', () {
      // Box A: 0..10, 0..10 (area = 100)
      // Box B: 5..15, 0..10 (area = 100)
      // Intersection: 5..10, 0..10 (area = 50)
      // Union = 100 + 100 - 50 = 150 -> IoU = 50 / 150 = 0.3333
      const boxA = Detection(
          x1: 0,
          y1: 0,
          x2: 10,
          y2: 10,
          mangoClass: MangoClass.ripe,
          confidence: 0.9);
      const boxB = Detection(
          x1: 5,
          y1: 0,
          x2: 15,
          y2: 10,
          mangoClass: MangoClass.ripe,
          confidence: 0.8);

      final iou = TreeTracker.computeIoU(boxA, boxB);
      expect(iou, closeTo(0.3333, 0.001));
    });
  });

  group('TreeTracker Multi-Frame Tracking & Deduplication Tests', () {
    test(
        'Deduplicates a single mango observed across 5 consecutive video frames into 1 unique count',
        () {
      final tracker = TreeTracker(minHitsToConfirm: 2, iouThreshold: 0.22);

      // Simulate a camera panning slowly across 1 mango with small camera shifts
      for (int frame = 0; frame < 5; frame++) {
        final shift = frame * 2.0;
        final detection = Detection(
          x1: 100 + shift,
          y1: 100 + shift,
          x2: 160 + shift,
          y2: 180 + shift,
          mangoClass: MangoClass.unripe,
          confidence: 0.70 + (frame * 0.02),
        );

        tracker.updateFrame(
          rawDetections: [detection],
          frameIndex: frame,
          imageWidth: 640,
          imageHeight: 640,
        );
      }

      final confirmed = tracker.finalize(totalFramesProcessed: 5);

      // Only 1 unique mango should be counted despite 5 detections across the video
      expect(confirmed.length, 1);
      expect(confirmed.first.hitCount, 5);
      expect(confirmed.first.mangoClass, MangoClass.unripe);
      expect(confirmed.first.trackId, 1);
    });

    test('Tracks multiple separate mangoes distinctly in the same tree canopy',
        () {
      final tracker = TreeTracker(minHitsToConfirm: 2);

      // Frame 0: Mango 1 at top-left, Mango 2 at bottom-right
      tracker.updateFrame(
        rawDetections: const [
          Detection(
              x1: 50,
              y1: 50,
              x2: 100,
              y2: 110,
              mangoClass: MangoClass.ripe,
              confidence: 0.8),
          Detection(
              x1: 400,
              y1: 400,
              x2: 460,
              y2: 470,
              mangoClass: MangoClass.unripe,
              confidence: 0.75),
        ],
        frameIndex: 0,
        imageWidth: 640,
        imageHeight: 640,
      );

      // Frame 1: Both still visible
      tracker.updateFrame(
        rawDetections: const [
          Detection(
              x1: 52,
              y1: 51,
              x2: 102,
              y2: 112,
              mangoClass: MangoClass.ripe,
              confidence: 0.85),
          Detection(
              x1: 398,
              y1: 402,
              x2: 458,
              y2: 472,
              mangoClass: MangoClass.unripe,
              confidence: 0.77),
        ],
        frameIndex: 1,
        imageWidth: 640,
        imageHeight: 640,
      );

      // Frame 2: Only Mango 2 visible
      tracker.updateFrame(
        rawDetections: const [
          Detection(
              x1: 395,
              y1: 405,
              x2: 455,
              y2: 475,
              mangoClass: MangoClass.unripe,
              confidence: 0.76),
        ],
        frameIndex: 2,
        imageWidth: 640,
        imageHeight: 640,
      );

      final confirmed = tracker.finalize(totalFramesProcessed: 3);
      expect(confirmed.length, 2);

      final ripeCount =
          confirmed.where((m) => m.mangoClass == MangoClass.ripe).length;
      final unripeCount =
          confirmed.where((m) => m.mangoClass == MangoClass.unripe).length;

      expect(ripeCount, 1);
      expect(unripeCount, 1);
    });

    test(
        'Rejects transient false alarm that only flashed in 1 frame during multi-frame video',
        () {
      final tracker = TreeTracker(minHitsToConfirm: 2);

      // Frame 0: Real mango + false flicker glitch
      tracker.updateFrame(
        rawDetections: const [
          Detection(
              x1: 50,
              y1: 50,
              x2: 100,
              y2: 110,
              mangoClass: MangoClass.ripe,
              confidence: 0.85),
          Detection(
              x1: 300,
              y1: 200,
              x2: 340,
              y2: 245,
              mangoClass: MangoClass.unripe,
              confidence: 0.22),
        ],
        frameIndex: 0,
        imageWidth: 640,
        imageHeight: 640,
      );

      // Frame 1: Real mango confirmed, glitch vanished
      tracker.updateFrame(
        rawDetections: const [
          Detection(
              x1: 52,
              y1: 51,
              x2: 102,
              y2: 112,
              mangoClass: MangoClass.ripe,
              confidence: 0.90),
        ],
        frameIndex: 1,
        imageWidth: 640,
        imageHeight: 640,
      );

      // Frame 2: Real mango confirmed again
      tracker.updateFrame(
        rawDetections: const [
          Detection(
              x1: 53,
              y1: 52,
              x2: 103,
              y2: 113,
              mangoClass: MangoClass.ripe,
              confidence: 0.88),
        ],
        frameIndex: 2,
        imageWidth: 640,
        imageHeight: 640,
      );

      final confirmed = tracker.finalize(totalFramesProcessed: 3);

      // The glitch (1 hit) is rejected; only the confirmed mango is reported
      expect(confirmed.length, 1);
      expect(confirmed.first.hitCount, 3);
      expect(confirmed.first.mangoClass, MangoClass.ripe);
    });
  });
}
