import 'detection.dart';

/// Automatic Dynamic Confidence Calibration for Mango Detection.
///
/// Eliminates manual confidence sliders in the UI.
/// Automatically detects when lower confidence is needed (e.g. shadowed canopy,
/// distant tree branches, occluded fruits) and lowers the threshold down to ~0.12,
/// while maintaining balanced noise rejection (~0.20) in clean foreground scenes.
///
/// Guaranteed: All user-edited and AI-verified detections are always preserved.
class AutoConfidenceCalculator {
  /// Minimum baseline threshold to eliminate leaf/branch texture noise.
  static const double minThreshold = 0.12;

  /// Default threshold for clean, high-contrast foreground fruit scenes.
  static const double defaultThreshold = 0.20;

  /// Automatically computes the optimal confidence threshold for the given detections.
  static double calculate(List<Detection> detections) {
    // Only analyze raw model predictions (ignore user-edited or AI-verified detections)
    final rawDetections =
        detections.where((d) => !d.userEdited && !d.aiVerified).toList();
    if (rawDetections.isEmpty) {
      return 0.15;
    }

    final scores = rawDetections.map((d) => d.confidence).toList()..sort();
    final double maxScore = scores.last;

    // 0. Solitary faint false positive protection:
    // If there is only 1 isolated prediction and its confidence is weak (< 0.35),
    // it is non-fruit clutter or a false alarm (e.g. human hand, skin, wall patch, twig artifact).
    // Set threshold above it (0.35) so solitary false alarms are naturally filtered on-device.
    if (scores.length == 1 && maxScore < 0.35) {
      return 0.35;
    }

    // 1. Difficult / Shadowed / Distant canopy scene:
    // If the maximum confidence is low (< 0.42), the entire tree is dimly lit,
    // occluded by foliage, or distant. Low confidence is automatically applied.
    if (maxScore < 0.42) {
      return minThreshold; // 0.12
    }

    // Categorize scores into operational bands
    final int lowBandCount = scores.where((s) => s >= 0.12 && s < 0.22).length;
    final int midBandCount = scores.where((s) => s >= 0.22 && s < 0.45).length;
    final int highBandCount = scores.where((s) => s >= 0.45).length;

    // 2. Mixed canopy scene:
    // If low-confidence candidates (0.12 - 0.22) exist:
    // When high-confidence detections are few (<= 2) or low-confidence candidates
    // represent a significant proportion of the fruit, low confidence is needed
    // to capture canopy mangoes (e.g. top-left / top-right branch fruits).
    if (lowBandCount > 0) {
      if (highBandCount <= 2 || lowBandCount >= highBandCount) {
        return minThreshold; // 0.12
      }
      if (midBandCount <= 2) {
        return 0.14;
      }
    }

    // 3. Score distribution median evaluation
    final candidatesAbove12 = scores.where((s) => s >= 0.12).toList();
    if (candidatesAbove12.isNotEmpty) {
      final median = candidatesAbove12[candidatesAbove12.length ~/ 2];
      if (median < 0.32) {
        return 0.13;
      } else if (median < 0.45) {
        return 0.16;
      }
    }

    // 4. Clean foreground scene with strong high-confidence fruits
    return defaultThreshold; // 0.20
  }

  /// Filters detections using the calculated threshold.
  /// User-edited and AI-verified detections are always preserved.
  static List<Detection> filterDetections(
      List<Detection> allDetections, double threshold) {
    return allDetections.where((d) {
      if (d.userEdited || d.aiVerified) return true;
      return d.confidence >= threshold;
    }).toList();
  }
}
