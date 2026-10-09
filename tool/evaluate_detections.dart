import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Offline, class-independent localization matching followed by ripeness scoring.
/// Input: {"images":[{"id":"tree-1","truth":[...],"predictions":[...]}]}.
/// Boxes: {"box":[x1,y1,x2,y2],"class":"ripe","confidence":0.8}.
/// Ground-truth boxes omit confidence. Coordinates must share the same scale.
Map<String, Object?> evaluate(Map<String, dynamic> data,
    {double confidence = 0.25, double iouThreshold = 0.5}) {
  if (!confidence.isFinite ||
      confidence < 0 ||
      confidence > 1 ||
      !iouThreshold.isFinite ||
      iouThreshold <= 0 ||
      iouThreshold > 1) {
    throw ArgumentError('Thresholds must be in [0, 1], with IoU > 0');
  }
  final images = data['images'] as List;
  if (images.isEmpty) {
    throw ArgumentError('At least one labeled image is required');
  }
  var tp = 0, fp = 0, fn = 0, correctClass = 0, absoluteError = 0, bias = 0;
  final perImage = <Map<String, Object>>[];
  final seenIds = <String>{};
  final confusion = <String, Map<String, int>>{};
  for (final image in images) {
    final id = image['id'] as String;
    if (!seenIds.add(id)) throw ArgumentError('Duplicate image id: $id');
    final truth = (image['truth'] as List).cast<Map<String, dynamic>>();
    final predictions =
        (image['predictions'] as List).cast<Map<String, dynamic>>();
    for (final entry in [...truth, ...predictions]) {
      final box = (entry['box'] as List).cast<num>();
      if (box.length != 4 ||
          box.any((v) => !v.isFinite) ||
          box[2] <= box[0] ||
          box[3] <= box[1] ||
          !['over_ripe', 'ripe', 'unripe'].contains(entry['class'])) {
        throw ArgumentError('Invalid annotation in $id');
      }
    }
    for (final prediction in predictions) {
      final score = prediction['confidence'] as num;
      if (!score.isFinite || score < 0 || score > 1) {
        throw ArgumentError('Invalid confidence in $id');
      }
    }
    final selected = predictions
        .where((p) => (p['confidence'] as num) >= confidence)
        .toList()
      ..sort(
          (a, b) => (b['confidence'] as num).compareTo(a['confidence'] as num));
    final matched = <int>{};
    for (final prediction in selected) {
      var best = -1;
      var bestIou = iouThreshold;
      for (var i = 0; i < truth.length; i++) {
        if (matched.contains(i)) continue;
        final overlap =
            _iou(prediction['box'] as List, truth[i]['box'] as List);
        if (overlap >= bestIou) {
          best = i;
          bestIou = overlap;
        }
      }
      if (best < 0) {
        fp++;
        continue;
      }
      matched.add(best);
      tp++;
      final actual = truth[best]['class'] as String;
      final predicted = prediction['class'] as String;
      if (actual == predicted) correctClass++;
      final row = confusion.putIfAbsent(actual, () => {});
      row[predicted] = (row[predicted] ?? 0) + 1;
    }
    fn += truth.length - matched.length;
    final error = selected.length - truth.length;
    absoluteError += error.abs();
    bias += error;
    perImage.add({
      'id': id,
      'truth_count': truth.length,
      'predicted_count': selected.length,
      'count_error': error
    });
  }
  return {
    'images': images.length,
    'confidence_threshold': confidence,
    'iou_threshold': iouThreshold,
    'true_positives': tp,
    'false_positives': fp,
    'false_negatives': fn,
    'precision': tp + fp == 0 ? null : tp / (tp + fp),
    'recall': tp + fn == 0 ? null : tp / (tp + fn),
    'f1': 2 * tp + fp + fn == 0 ? null : 2 * tp / (2 * tp + fp + fn),
    'count_mae': absoluteError / images.length,
    'count_bias': bias / images.length,
    'ripeness_accuracy_on_matched_fruit': tp == 0 ? null : correctClass / tp,
    'ripeness_confusion_truth_rows': confusion,
    'per_image': perImage,
  };
}

double _iou(List a, List b) {
  final intersection =
      max(0, min(a[2] as num, b[2] as num) - max(a[0] as num, b[0] as num)) *
          max(0, min(a[3] as num, b[3] as num) - max(a[1] as num, b[1] as num));
  final union = (a[2] - a[0]) * (a[3] - a[1]) +
      (b[2] - b[0]) * (b[3] - b[1]) -
      intersection;
  return intersection / union;
}

void main(List<String> args) {
  if (args.isEmpty || args.length > 3) {
    stderr.writeln(
        'Usage: dart run tool/evaluate_detections.dart input.json [confidence=0.25] [IoU=0.5]');
    exitCode = 64;
    return;
  }
  try {
    final data =
        jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(evaluate(data,
        confidence: args.length > 1 ? double.parse(args[1]) : 0.25,
        iouThreshold: args.length > 2 ? double.parse(args[2]) : 0.5)));
  } catch (error) {
    stderr.writeln('Evaluation failed: $error');
    exitCode = 1;
  }
}
