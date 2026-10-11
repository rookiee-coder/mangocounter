import 'dart:convert';
import '../../detection/domain/detection.dart';

class ScanRecord {
  final String id;

  /// Orchard tree associated with this scan, when one was selected.
  final String? treeId;
  final int createdAt;
  final String imagePath;
  final int imageWidth;
  final int imageHeight;

  final int modelHalfRipe;
  final int modelRipe;
  final int modelUnripe;

  final int? editedHalfRipe;
  final int? editedRipe;
  final int? editedUnripe;
  final int? actualCount;

  final double confThreshold;
  final double iouThreshold;
  final int inferenceMs;
  final bool isDemo;

  final List<Detection> detections;
  final List<Detection> modelDetections;

  ScanRecord({
    required this.id,
    this.treeId,
    required this.createdAt,
    required this.imagePath,
    required this.imageWidth,
    required this.imageHeight,
    required this.modelHalfRipe,
    required this.modelRipe,
    required this.modelUnripe,
    this.editedHalfRipe,
    this.editedRipe,
    this.editedUnripe,
    this.actualCount,
    required this.confThreshold,
    required this.iouThreshold,
    required this.inferenceMs,
    required this.isDemo,
    required this.detections,
    required this.modelDetections,
  });

  int get currentOverRipe => editedHalfRipe ?? modelHalfRipe;
  int get currentHalfRipe => currentOverRipe;
  int get modelOverRipe => modelHalfRipe;
  int? get editedOverRipe => editedHalfRipe;
  int get currentRipe => editedRipe ?? modelRipe;
  int get currentUnripe => editedUnripe ?? modelUnripe;
  int get currentTotal => currentOverRipe + currentRipe + currentUnripe;

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id,
      'created_at': createdAt,
      'image_path': imagePath,
      'image_width': imageWidth,
      'image_height': imageHeight,
      'model_half_ripe': modelHalfRipe,
      'model_ripe': modelRipe,
      'model_unripe': modelUnripe,
      'edited_half_ripe': editedHalfRipe,
      'edited_ripe': editedRipe,
      'edited_unripe': editedUnripe,
      'actual_count': actualCount,
      'conf_threshold': confThreshold,
      'iou_threshold': iouThreshold,
      'inference_ms': inferenceMs,
      'is_demo': isDemo ? 1 : 0,
      'detections_json': jsonEncode(detections.map((d) => d.toJson()).toList()),
      'model_detections_json':
          jsonEncode(modelDetections.map((d) => d.toJson()).toList()),
    };
    if (treeId != null) map['tree_id'] = treeId;
    return map;
  }

  factory ScanRecord.fromMap(Map<String, dynamic> map) {
    return ScanRecord(
      id: map['id'],
      treeId: map['tree_id'] as String?,
      createdAt: map['created_at'],
      imagePath: map['image_path'],
      imageWidth: map['image_width'],
      imageHeight: map['image_height'],
      modelHalfRipe: map['model_half_ripe'],
      modelRipe: map['model_ripe'],
      modelUnripe: map['model_unripe'],
      editedHalfRipe: map['edited_half_ripe'],
      editedRipe: map['edited_ripe'],
      editedUnripe: map['edited_unripe'],
      actualCount: map['actual_count'],
      confThreshold: map['conf_threshold'],
      iouThreshold: map['iou_threshold'],
      inferenceMs: map['inference_ms'],
      isDemo: map['is_demo'] == 1,
      detections: (jsonDecode(map['detections_json']) as List)
          .map((d) => Detection.fromJson(d))
          .toList(),
      modelDetections: (jsonDecode(map['model_detections_json']) as List)
          .map((d) => Detection.fromJson(d))
          .toList(),
    );
  }
}
