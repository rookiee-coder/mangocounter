class HarvestReminder {
  final String treeId;
  final DateTime harvestDate;

  const HarvestReminder({required this.treeId, required this.harvestDate});

  int get notificationId {
    var hash = 0;
    for (final unit in treeId.codeUnits) {
      hash = ((hash * 31) + unit) & 0x3fffffff;
    }
    return 700000000 + hash;
  }

  Map<String, dynamic> toJson() => {
        'treeId': treeId,
        'harvestDate': harvestDate.millisecondsSinceEpoch,
      };

  factory HarvestReminder.fromJson(Map<String, dynamic> json) {
    return HarvestReminder(
      treeId: json['treeId'] as String,
      harvestDate:
          DateTime.fromMillisecondsSinceEpoch(json['harvestDate'] as int),
    );
  }
}
