import '../../history/domain/scan_record.dart';

enum HarvestReadiness { harvestNow, nearlyReady, developing, rescanNeeded }

enum HarvestPredictionSource { onDevice, gemini }

/// A conservative harvest estimate derived from fruit detected in an assigned
/// tree's latest scan. It is a planning aid, not a maturity or quality grade.
class HarvestForecast {
  final String treeId;
  final String treeLabel;
  final DateTime recommendedHarvestDate;
  final DateTime scanDate;
  final HarvestReadiness readiness;
  final int totalFruit;
  final int ripeFruit;
  final int unripeFruit;
  final int overRipeFruit;
  final HarvestPredictionSource source;
  final double? confidence;
  final String? predictionReason;

  const HarvestForecast({
    required this.treeId,
    required this.treeLabel,
    required this.recommendedHarvestDate,
    required this.scanDate,
    required this.readiness,
    required this.totalFruit,
    required this.ripeFruit,
    required this.unripeFruit,
    required this.overRipeFruit,
    this.source = HarvestPredictionSource.onDevice,
    this.confidence,
    this.predictionReason,
  });

  bool get needsRescan => readiness == HarvestReadiness.rescanNeeded;
  bool get isAiPrediction => source == HarvestPredictionSource.gemini;

  HarvestForecast withAiPrediction({
    required int daysUntilHarvest,
    required double confidence,
    required String reason,
    required DateTime now,
  }) {
    // A detected overripe fruit or a majority-ripe tree must never be delayed
    // by a text-model estimate. The calendar remains conservative.
    final protectedDays = readiness == HarvestReadiness.harvestNow
        ? 0
        : daysUntilHarvest.clamp(0, 21);
    final nextReadiness = protectedDays == 0
        ? HarvestReadiness.harvestNow
        : protectedDays <= 2
            ? HarvestReadiness.nearlyReady
            : HarvestReadiness.developing;
    return HarvestForecast(
      treeId: treeId,
      treeLabel: treeLabel,
      recommendedHarvestDate:
          HarvestPredictor.dateOnly(now).add(Duration(days: protectedDays)),
      scanDate: scanDate,
      readiness: nextReadiness,
      totalFruit: totalFruit,
      ripeFruit: ripeFruit,
      unripeFruit: unripeFruit,
      overRipeFruit: overRipeFruit,
      source: HarvestPredictionSource.gemini,
      confidence: confidence.clamp(0, 100).toDouble(),
      predictionReason: reason.trim(),
    );
  }

  String get summary {
    if (predictionReason?.isNotEmpty == true && !needsRescan) {
      return predictionReason!;
    }
    switch (readiness) {
      case HarvestReadiness.harvestNow:
        return overRipeFruit > 0
            ? '$overRipeFruit overripe fruit detected; inspect and harvest now.'
            : 'Most detected fruit is ripe; inspect and harvest now.';
      case HarvestReadiness.nearlyReady:
        return 'Some fruit is ripe. Recheck this tree before the planned harvest.';
      case HarvestReadiness.developing:
        return 'Fruit is mostly unripe. Schedule a field check near this date.';
      case HarvestReadiness.rescanNeeded:
        return 'The latest scan is over 14 days old. Scan this tree again before planning harvest.';
    }
  }
}

class HarvestPredictor {
  static const _staleAfter = Duration(days: 14);

  /// Uses the latest assigned scan only, so an older image cannot override a
  /// more recent field observation. Dates are intentionally broad and should
  /// be verified in the orchard before harvest.
  static HarvestForecast? forecastForTree(
    String treeId,
    List<ScanRecord> scans, {
    DateTime? now,
  }) {
    final matching = scans.where((scan) => scan.treeId == treeId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (matching.isEmpty) return null;

    final latest = matching.first;
    final observedAt = DateTime.fromMillisecondsSinceEpoch(latest.createdAt);
    final clock = now ?? DateTime.now();
    final total = latest.currentTotal;
    if (total == 0 || clock.difference(observedAt) > _staleAfter) {
      return HarvestForecast(
        treeId: treeId,
        treeLabel: treeLabelFor(treeId),
        recommendedHarvestDate: dateOnly(clock),
        scanDate: observedAt,
        readiness: HarvestReadiness.rescanNeeded,
        totalFruit: total,
        ripeFruit: latest.currentRipe,
        unripeFruit: latest.currentUnripe,
        overRipeFruit: latest.currentOverRipe,
      );
    }

    final ripeShare = latest.currentRipe / total;
    final unripeShare = latest.currentUnripe / total;
    late final HarvestReadiness readiness;
    late final int days;
    if (latest.currentOverRipe > 0 || ripeShare >= 0.5) {
      readiness = HarvestReadiness.harvestNow;
      days = 0;
    } else if (ripeShare >= 0.2) {
      readiness = HarvestReadiness.nearlyReady;
      days = 2;
    } else {
      readiness = HarvestReadiness.developing;
      // A mixed tree is planned earlier than an entirely unripe tree.
      days = (3 + (unripeShare * 4)).round().clamp(3, 7);
    }
    return HarvestForecast(
      treeId: treeId,
      treeLabel: treeLabelFor(treeId),
      recommendedHarvestDate: dateOnly(clock).add(Duration(days: days)),
      scanDate: observedAt,
      readiness: readiness,
      totalFruit: total,
      ripeFruit: latest.currentRipe,
      unripeFruit: latest.currentUnripe,
      overRipeFruit: latest.currentOverRipe,
    );
  }

  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String treeLabelFor(String treeId) {
    final match = RegExp(r'^lane_(\d+)_tree_(\d+)$').firstMatch(treeId);
    if (match == null) return treeId;
    return 'Lane ${match.group(1)} / Tree ${match.group(2)}';
  }
}
