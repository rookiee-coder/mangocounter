import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangocounter/features/detection/data/inference_tiles.dart';
import 'package:mangocounter/features/detection/data/model_input_encoder.dart';
import 'package:mangocounter/features/detection/data/yolo_postprocessor.dart';
import 'package:mangocounter/features/detection/domain/detection.dart';
import 'package:mangocounter/features/detection/domain/mango_class.dart';
import 'package:mangocounter/features/video_scan/data/tree_tracker.dart';
import 'package:mangocounter/features/video_scan/data/video_sampling.dart';

void main() {
  test('quantized RGB uses scale and signed zero point', () {
    final values = Float32List.fromList([0, 0.5, 1]);
    expect(
        ModelInputEncoder.encode(values,
            type: 'int8', scale: 1 / 255, zeroPoint: -128),
        [-128, 0, 127]);
    expect(ModelInputEncoder.encode(values, type: 'uint8', scale: 1 / 255),
        [0, 128, 255]);
    expect(() => ModelInputEncoder.encode(values, type: 'int8', scale: 0),
        throwsArgumentError);
  });

  for (final size in [(1920, 1920), (1920, 1440), (1080, 1920), (1920, 400)]) {
    test('detail tiles cover ${size.$1} x ${size.$2} with bounded work', () {
      final tiles = InferenceTile.plan(size.$1, size.$2, 640);
      expect(tiles.length, inInclusiveRange(2, 4));
      for (var y = 0; y < size.$2; y += 13) {
        for (var x = 0; x < size.$1; x += 13) {
          expect(
              tiles.any((t) =>
                  x >= t.x &&
                  x < t.x + t.width &&
                  y >= t.y &&
                  y < t.y + t.height),
              isTrue);
        }
      }
      expect(
          tiles.every(
              (t) => t.x + t.width <= size.$1 && t.y + t.height <= size.$2),
          isTrue);
    });
  }
  test('small images skip redundant detail inference', () {
    expect(InferenceTile.plan(640, 480, 640), isEmpty);
  });

  List<Detection> parse(List<dynamic> tensor, {bool normalized = false}) =>
      YoloPostprocessor.processSync([tensor],
          confThreshold: 0.2,
          iouThreshold: 0.45,
          scale: 1,
          padX: 0,
          padY: 0,
          originalWidth: 640,
          originalHeight: 640,
          modelInputSize: 640,
          boxesNormalized: normalized);

  test('channels-first with only one candidate is parsed correctly', () {
    final detections = parse([
      [100.0],
      [100.0],
      [20.0],
      [30.0],
      [0.1],
      [0.8],
      [0.2]
    ]);
    expect(detections.single.mangoClass, MangoClass.ripe);
    expect(detections.single.x1, 90);
  });
  test('six-column raw output is not mistaken for embedded NMS', () {
    final detections = parse([
      [100.0, 100.0, 20.0, 30.0, 0.1, 0.8]
    ]);
    expect(detections.single.x1, 90);
    expect(detections.single.mangoClass, MangoClass.ripe);
  });
  test('pixel boxes near image origin are not inflated', () {
    expect(
        parse([
          [10.0, 10.0, 4.0, 4.0, 0.1, 0.8, 0.1]
        ]).single.x1,
        8);
  });
  test('invalid box coordinates never become clamped fruit detections', () {
    expect(
        parse([
          [double.infinity, 10.0, 4.0, 4.0, 0.1, 0.8, 0.1]
        ]),
        isEmpty);
  });
  test('valid low-confidence close fruit is retained for user filtering', () {
    expect(
        parse([
          [320.0, 320.0, 300.0, 300.0, 0.1, 0.3, 0.1]
        ]),
        hasLength(1));
  });

  test('new track is not retired on its own first observation', () {
    final tracker = TreeTracker(maxConsecutiveMisses: 0);
    const det = Detection(
        x1: 100,
        y1: 100,
        x2: 120,
        y2: 130,
        mangoClass: MangoClass.unripe,
        confidence: 0.8);
    for (var frame = 0; frame < 3; frame++) {
      tracker.updateFrame(
          rawDetections: [det],
          frameIndex: frame,
          imageWidth: 1920,
          imageHeight: 1920);
    }
    expect(tracker.finalize(totalFramesProcessed: 3).single.hitCount, 3);
  });
  test('distant fruit is not removed solely by relative image area', () {
    const det = Detection(
        x1: 100,
        y1: 100,
        x2: 110,
        y2: 115,
        mangoClass: MangoClass.unripe,
        confidence: 0.8);
    expect(TreeTracker.isValidMangoGeometry(det, 1920, 1920), isTrue);
  });
  test('video sampling reaches the end of a 20-second clip', () {
    final timestamps = VideoSampling.timestamps(20000, 650, 32);
    expect(timestamps.first, 0);
    expect(timestamps.last, 19999);
    expect(timestamps.length, lessThanOrEqualTo(32));
    expect(timestamps.toSet().length, timestamps.length);
    expect(() => VideoSampling.timestamps(20000, 0, 32), throwsArgumentError);
  });
}
