import 'package:flutter_test/flutter_test.dart';
import 'package:mangocounter/features/harvest/domain/harvest_forecast.dart';
import 'package:mangocounter/features/history/domain/scan_record.dart';

void main() {
  const treeId = 'lane_2_tree_4';
  final today = DateTime(2026, 10, 14, 12);

  ScanRecord scan({
    required int createdAt,
    int ripe = 0,
    int unripe = 0,
    int overripe = 0,
  }) =>
      ScanRecord(
        id: '$createdAt',
        treeId: treeId,
        createdAt: createdAt,
        imagePath: '',
        imageWidth: 100,
        imageHeight: 100,
        modelHalfRipe: overripe,
        modelRipe: ripe,
        modelUnripe: unripe,
        confThreshold: .25,
        iouThreshold: .45,
        inferenceMs: 1,
        isDemo: false,
        detections: const [],
        modelDetections: const [],
      );

  test('latest assigned scan decides a tree forecast', () {
    final staleRipe = scan(
      createdAt: today.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      ripe: 8,
    );
    final currentUnripe = scan(
      createdAt: today.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
      unripe: 8,
    );

    final forecast = HarvestPredictor.forecastForTree(
      treeId,
      [staleRipe, currentUnripe],
      now: today,
    )!;

    expect(forecast.readiness, HarvestReadiness.developing);
    expect(forecast.recommendedHarvestDate, DateTime(2026, 10, 21));
    expect(forecast.treeLabel, 'Lane 2 / Tree 4');
  });

  test('overripe fruit calls for harvest now', () {
    final forecast = HarvestPredictor.forecastForTree(
      treeId,
      [
        scan(
          createdAt: today.millisecondsSinceEpoch,
          overripe: 1,
          unripe: 5,
        ),
      ],
      now: today,
    )!;

    expect(forecast.readiness, HarvestReadiness.harvestNow);
    expect(forecast.recommendedHarvestDate, DateTime(2026, 10, 14));
  });

  test('old or empty scans need a fresh field scan', () {
    final old = HarvestPredictor.forecastForTree(
      treeId,
      [
        scan(
          createdAt: today.subtract(const Duration(days: 15)).millisecondsSinceEpoch,
          unripe: 5,
        ),
      ],
      now: today,
    )!;
    final empty = HarvestPredictor.forecastForTree(
      treeId,
      [scan(createdAt: today.millisecondsSinceEpoch)],
      now: today,
    )!;

    expect(old.needsRescan, isTrue);
    expect(empty.needsRescan, isTrue);
  });
}
