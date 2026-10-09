import 'mango_class.dart';

class Detection {
  /// Original image pixel coordinates
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  
  final MangoClass mangoClass;
  final double confidence;
  final bool userEdited;
  final bool aiVerified;
  final String? aiReason;
  final bool needsReview;

  const Detection({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.mangoClass,
    required this.confidence,
    this.userEdited = false,
    this.aiVerified = false,
    this.aiReason,
    this.needsReview = false,
  });

  Detection copyWith({
    double? x1,
    double? y1,
    double? x2,
    double? y2,
    MangoClass? mangoClass,
    double? confidence,
    bool? userEdited,
    bool? aiVerified,
    String? aiReason,
    bool? needsReview,
  }) {
    return Detection(
      x1: x1 ?? this.x1,
      y1: y1 ?? this.y1,
      x2: x2 ?? this.x2,
      y2: y2 ?? this.y2,
      mangoClass: mangoClass ?? this.mangoClass,
      confidence: confidence ?? this.confidence,
      userEdited: userEdited ?? this.userEdited,
      aiVerified: aiVerified ?? this.aiVerified,
      aiReason: aiReason ?? this.aiReason,
      needsReview: needsReview ?? this.needsReview,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'x1': x1,
      'y1': y1,
      'x2': x2,
      'y2': y2,
      'classIndex': mangoClass.index,
      'confidence': confidence,
      'userEdited': userEdited,
      'aiVerified': aiVerified,
      'aiReason': aiReason,
      'needsReview': needsReview,
    };
  }

  factory Detection.fromJson(Map<String, dynamic> json) {
    return Detection(
      x1: json['x1'],
      y1: json['y1'],
      x2: json['x2'],
      y2: json['y2'],
      mangoClass: MangoClass.fromIndex(json['classIndex']),
      confidence: json['confidence'],
      userEdited: json['userEdited'] ?? false,
      aiVerified: json['aiVerified'] ?? false,
      aiReason: json['aiReason'],
      needsReview: json['needsReview'] ?? false,
    );
  }
}
