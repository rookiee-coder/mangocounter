import 'package:flutter_test/flutter_test.dart';
import 'package:mangocounter/features/detection/data/gemini_assistant_service.dart';
import 'package:mangocounter/features/detection/domain/detection.dart';
import 'package:mangocounter/features/detection/domain/mango_class.dart';
import 'package:mangocounter/features/settings/application/settings_controller.dart';

void main() {
  test('CropVerdict instantiates correctly', () {
    const verdict = CropVerdict(
      id: 0,
      isMango: true,
      ripeness: MangoClass.over_ripe,
      rawRipeness: 'overripe',
      reason: 'Golden yellow peel with brownish wrinkles',
    );

    expect(verdict.isMango, isTrue);
    expect(verdict.ripeness, MangoClass.over_ripe);
    expect(verdict.rawRipeness, 'overripe');
    expect(verdict.reason, contains('brownish wrinkles'));
  });

  test('MangoClass maps indices and strings correctly', () {
    expect(MangoClass.fromIndex(0), MangoClass.over_ripe);
    expect(MangoClass.fromIndex(1), MangoClass.ripe);
    expect(MangoClass.fromIndex(2), MangoClass.unripe);

    expect(MangoClass.fromString('over_ripe'), MangoClass.over_ripe);
    expect(MangoClass.fromString('Over ripe'), MangoClass.over_ripe);
    expect(MangoClass.fromString('ripe'), MangoClass.ripe);
    expect(MangoClass.fromString('unripe'), MangoClass.unripe);

    expect(MangoClass.over_ripe.displayName, 'Over-ripe');
    expect(MangoClass.ripe.displayName, 'Ripe');
    expect(MangoClass.unripe.displayName, 'Unripe');
  });

  test('AiAssistedDetectionResult instantiates correctly with Gemini AI provider', () {
    final res = AiAssistedDetectionResult(
      reconciledDetections: const [
        Detection(x1: 10, y1: 10, x2: 50, y2: 50, mangoClass: MangoClass.over_ripe, confidence: 0.92),
        Detection(x1: 60, y1: 60, x2: 120, y2: 120, mangoClass: MangoClass.ripe, confidence: 0.95),
        Detection(x1: 130, y1: 130, x2: 200, y2: 200, mangoClass: MangoClass.unripe, confidence: 0.88),
      ],
      providerName: 'Google Gemini (Gemini Flash-Lite)',
      summary: 'Verified 3 mangoes on tree using Gemini AI',
      totalCount: 3,
      overRipeCount: 1,
      ripeCount: 1,
      unripeCount: 1,
      needsReviewCount: 1,
      verifiedCount: 2,
    );

    expect(res.totalCount, 3);
    expect(res.overRipeCount, 1);
    expect(res.ripeCount, 1);
    expect(res.unripeCount, 1);
    expect(res.needsReviewCount, 1);
    expect(res.verifiedCount, 2);
    expect(res.providerName, 'Google Gemini (Gemini Flash-Lite)');
  });

  test('SettingsState defaults to gemini provider and tiled inference', () {
    final state = SettingsState();
    expect(state.aiProvider, 'gemini');
    expect(state.tiledInference, isTrue);
    expect(state.autoConfidence, isTrue);
    expect(state.autoAiAssist, isTrue);
  });
}
