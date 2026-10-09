import 'dart:math';

/// A bounded detail pass alongside the full image. Four overlapping crops
/// retain canopy context without letting phone inference grow without limit.
class InferenceTile {
  final int x, y, width, height;
  const InferenceTile(this.x, this.y, this.width, this.height);

  static List<InferenceTile> plan(int width, int height, int inputSize) {
    if (width <= 0 || height <= 0 || inputSize <= 0) {
      throw ArgumentError('Image and model dimensions must be positive');
    }
    if (max(width, height) <= inputSize) return [];
    final tileWidth = min(width, max(inputSize, (width * 0.6).ceil()));
    final tileHeight = min(height, max(inputSize, (height * 0.6).ceil()));
    final xs = {0, width - tileWidth};
    final ys = {0, height - tileHeight};
    return [
      for (final y in ys)
        for (final x in xs) InferenceTile(x, y, tileWidth, tileHeight),
    ];
  }
}
