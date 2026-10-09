import 'package:flutter_test/flutter_test.dart';
import '../tool/evaluate_detections.dart';

void main() {
  test('duplicates count as false positives, ripeness is scored separately',
      () {
    final result = evaluate({
      'images': [
        {
          'id': 'tree-1',
          'truth': [
            {
              'box': [0, 0, 10, 10],
              'class': 'ripe'
            },
            {
              'box': [20, 20, 30, 30],
              'class': 'unripe'
            },
          ],
          'predictions': [
            {
              'box': [0, 0, 10, 10],
              'class': 'unripe',
              'confidence': 0.9
            },
            {
              'box': [0, 0, 10, 10],
              'class': 'ripe',
              'confidence': 0.8
            },
          ]
        },
        {
          'id': 'negative',
          'truth': [],
          'predictions': [
            {
              'box': [0, 0, 10, 10],
              'class': 'ripe',
              'confidence': 0.6
            },
          ]
        },
      ]
    });
    expect(result['true_positives'], 1);
    expect(result['false_positives'], 2);
    expect(result['false_negatives'], 1);
    expect(result['count_mae'], 0.5);
    expect(result['ripeness_accuracy_on_matched_fruit'], 0);
  });
  test('empty evaluation data cannot imply perfect accuracy', () {
    expect(() => evaluate({'images': []}), throwsArgumentError);
    final result = evaluate({
      'images': [
        {'id': 'negative', 'truth': [], 'predictions': []},
      ]
    });
    expect(result['precision'], isNull);
    expect(result['recall'], isNull);
  });
}
