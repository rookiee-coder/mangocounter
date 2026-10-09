// ignore_for_file: constant_identifier_names
enum MangoClass {
  over_ripe,
  ripe,
  unripe;

  String get displayName {
    switch (this) {
      case MangoClass.over_ripe:
        return 'Over-ripe';
      case MangoClass.ripe:
        return 'Ripe';
      case MangoClass.unripe:
        return 'Unripe';
    }
  }

  String get label {
    switch (this) {
      case MangoClass.over_ripe:
        return 'over_ripe';
      case MangoClass.ripe:
        return 'ripe';
      case MangoClass.unripe:
        return 'unripe';
    }
  }

  static MangoClass fromIndex(int index) {
    if (index == 0) return MangoClass.over_ripe; // labels.txt index 0: 'Over ripe'
    if (index == 1) return MangoClass.ripe;      // labels.txt index 1: 'Ripe'
    if (index == 2) return MangoClass.unripe;    // labels.txt index 2: 'Unripe'
    return MangoClass.unripe; // Fallback
  }

  static MangoClass fromString(String str) {
    final lower = str.toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    if (lower.contains('over')) return MangoClass.over_ripe;
    if (lower.contains('unripe')) return MangoClass.unripe;
    if (lower.contains('ripe')) return MangoClass.ripe;
    return MangoClass.unripe;
  }

  /// Backwards compatibility alias
  static const MangoClass half_ripe = MangoClass.over_ripe;
}
