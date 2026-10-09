import '../../detection/domain/detection.dart';
import '../../detection/domain/mango_class.dart';

class TrackedMango {
  final int trackId;
  final MangoClass mangoClass;
  final double confidence;
  final int hitCount;
  final int firstFrameIndex;
  final int lastFrameIndex;
  final Detection bestDetection;
  final int bestFrameIndex;
  final bool aiVerified;

  const TrackedMango({
    required this.trackId,
    required this.mangoClass,
    required this.confidence,
    required this.hitCount,
    required this.firstFrameIndex,
    required this.lastFrameIndex,
    required this.bestDetection,
    required this.bestFrameIndex,
    this.aiVerified = false,
  });

  TrackedMango copyWith({
    int? trackId,
    MangoClass? mangoClass,
    double? confidence,
    int? hitCount,
    int? firstFrameIndex,
    int? lastFrameIndex,
    Detection? bestDetection,
    int? bestFrameIndex,
    bool? aiVerified,
  }) {
    return TrackedMango(
      trackId: trackId ?? this.trackId,
      mangoClass: mangoClass ?? this.mangoClass,
      confidence: confidence ?? this.confidence,
      hitCount: hitCount ?? this.hitCount,
      firstFrameIndex: firstFrameIndex ?? this.firstFrameIndex,
      lastFrameIndex: lastFrameIndex ?? this.lastFrameIndex,
      bestDetection: bestDetection ?? this.bestDetection,
      bestFrameIndex: bestFrameIndex ?? this.bestFrameIndex,
      aiVerified: aiVerified ?? this.aiVerified,
    );
  }
}
