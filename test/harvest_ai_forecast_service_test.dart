import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mangocounter/features/harvest/data/harvest_ai_forecast_service.dart';
import 'package:mangocounter/features/harvest/domain/harvest_forecast.dart';
import 'package:mangocounter/features/history/domain/scan_record.dart';

void main() {
  final now = DateTime(2026, 10, 14, 9);

  ScanRecord scan({int ripe = 0, int unripe = 0, int overripe = 0}) =>
      ScanRecord(
        id: 'scan-1',
        treeId: 'lane_1_tree_1',
        createdAt: now.millisecondsSinceEpoch,
        imagePath: '',
        imageWidth: 100,
        imageHeight: 100,
        modelHalfRipe: overripe,
        modelRipe: ripe,
        modelUnripe: unripe,
        confThreshold: .25,
        iouThreshold: .45,
        inferenceMs: 1,
        isDemo: false,
        detections: const [],
        modelDetections: const [],
      );

  test('uses Gemini structured output to replace the calendar date', () async {
    late http.Request request;
    final client = MockClient((received) async {
      request = received;
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': jsonEncode({
                      'predictions': [
                        {
                          'tree_id': 'lane_1_tree_1',
                          'days_until_harvest': 4,
                          'confidence': 76,
                          'reason': 'A few ripe fruit; check again in four days.',
                          'needs_rescan': false,
                        }
                      ],
                    }),
                  }
                ],
              },
            }
          ],
        }),
        200,
      );
    });
    final record = scan(ripe: 1, unripe: 5);
    final local = HarvestPredictor.forecastForTree(
      'lane_1_tree_1',
      [record],
      now: now,
    )!;

    final result = await HarvestAiForecastService(client: client).predictAll(
      localForecasts: [local],
      scans: [record],
      apiKey: 'test-key',
      now: now,
    );

    final forecast = result['lane_1_tree_1']!;
    expect(request.headers['x-goog-api-key'], 'test-key');
    expect(jsonDecode(request.body)['generationConfig']['responseMimeType'],
        'application/json');
    expect(forecast.isAiPrediction, isTrue);
    expect(forecast.recommendedHarvestDate, DateTime(2026, 10, 18));
    expect(forecast.confidence, 76);
  });

  test('AI cannot delay a tree with overripe fruit', () async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text': jsonEncode({
                        'predictions': [
                          {
                            'tree_id': 'lane_1_tree_1',
                            'days_until_harvest': 12,
                            'confidence': 90,
                            'reason': 'Test response',
                            'needs_rescan': false,
                          }
                        ],
                      }),
                    }
                  ],
                },
              }
            ],
          }),
          200,
        ));
    final record = scan(overripe: 1, unripe: 3);
    final local = HarvestPredictor.forecastForTree(
      'lane_1_tree_1',
      [record],
      now: now,
    )!;

    final result = await HarvestAiForecastService(client: client).predictAll(
      localForecasts: [local],
      scans: [record],
      apiKey: 'test-key',
      now: now,
    );

    expect(
      result.values.single.recommendedHarvestDate,
      DateTime(2026, 10, 14),
    );
  });
}
