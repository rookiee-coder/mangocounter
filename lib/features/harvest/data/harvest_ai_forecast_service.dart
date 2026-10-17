import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../history/domain/scan_record.dart';
import '../domain/harvest_forecast.dart';

/// Requests calendar estimates in one small Gemini call. It sends detected
/// counts and scan dates only, never orchard photos or API keys to storage.
class HarvestAiForecastService {
  static const _model = 'gemini-3.5-flash-lite';

  final http.Client? _client;

  const HarvestAiForecastService({http.Client? client}) : _client = client;

  Future<Map<String, HarvestForecast>> predictAll({
    required List<HarvestForecast> localForecasts,
    required List<ScanRecord> scans,
    required String apiKey,
    DateTime? now,
  }) async {
    final key = apiKey.trim();
    final eligible = localForecasts.where((forecast) => !forecast.needsRescan);
    if (key.isEmpty || eligible.isEmpty) return {};

    final clock = now ?? DateTime.now();
    final inputTrees = [
      for (final forecast in eligible)
        {
          'tree_id': forecast.treeId,
          'latest_scan': _scanSummary(
            scans.where((scan) => scan.treeId == forecast.treeId).toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
          ),
          'current_detected_counts': {
            'total': forecast.totalFruit,
            'overripe': forecast.overRipeFruit,
            'ripe': forecast.ripeFruit,
            'unripe': forecast.unripeFruit,
          },
        },
    ];

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {
              'text': '''
You are a conservative mango orchard harvest-planning assistant. Estimate the
best calendar day for a FIELD INSPECTION / HARVEST per tree from ONLY the
detected peel-ripeness counts and the dated scan trend supplied below.

Rules:
- This is not a claim about internal fruit maturity. Do not invent cultivar,
  weather, flowering date, or unseen fruit information.
- overripe fruit or a majority of ripe fruit means 0 days (inspect/harvest now).
- Otherwise choose a whole number from 1 to 21 days. Prefer an earlier check
  when ripe fruit is increasing across scans.
- Set needs_rescan=true only if the supplied evidence is inadequate.
- confidence is 0 to 100 and must reflect evidence quality, not certainty.
- Give a specific, concise reason based on the supplied counts/trend only.

Today: ${HarvestPredictor.dateOnly(clock).toIso8601String()}
Tree data: ${jsonEncode(inputTrees)}
'''
            }
          ]
        }
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'responseSchema': {
          'type': 'OBJECT',
          'properties': {
            'predictions': {
              'type': 'ARRAY',
              'items': {
                'type': 'OBJECT',
                'properties': {
                  'tree_id': {'type': 'STRING'},
                  'days_until_harvest': {'type': 'INTEGER'},
                  'confidence': {'type': 'NUMBER'},
                  'reason': {'type': 'STRING'},
                  'needs_rescan': {'type': 'BOOLEAN'},
                },
                'required': [
                  'tree_id',
                  'days_until_harvest',
                  'confidence',
                  'reason',
                  'needs_rescan',
                ],
              },
            },
          },
          'required': ['predictions'],
        },
      },
    });

    final requestClient = _client ?? http.Client();
    try {
      final response = await requestClient
          .post(
            Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent',
            ),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': key,
            },
            body: body,
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return {};
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final rawText = decoded['candidates']?[0]?['content']?['parts']?[0]
          ?['text'] as String?;
      if (rawText == null || rawText.trim().isEmpty) return {};
      final responseJson = jsonDecode(rawText) as Map<String, dynamic>;
      final values = responseJson['predictions'];
      if (values is! List) return {};

      final byId = {for (final forecast in eligible) forecast.treeId: forecast};
      final predictions = <String, HarvestForecast>{};
      for (final value in values.whereType<Map<String, dynamic>>()) {
        final id = value['tree_id'] as String?;
        final base = id == null ? null : byId[id];
        final days = (value['days_until_harvest'] as num?)?.toInt();
        final confidence = (value['confidence'] as num?)?.toDouble();
        final reason = (value['reason'] as String?)?.trim();
        if (base == null || days == null || confidence == null || reason == null) {
          continue;
        }
        if (value['needs_rescan'] == true) continue;
        predictions[id!] = base.withAiPrediction(
          daysUntilHarvest: days,
          confidence: confidence,
          reason: reason,
          now: clock,
        );
      }
      return predictions;
    } catch (_) {
      return {};
    } finally {
      if (_client == null) requestClient.close();
    }
  }

  List<Map<String, dynamic>> _scanSummary(List<ScanRecord> records) {
    return records.take(3).map((scan) {
      return {
        'scanned_at': DateTime.fromMillisecondsSinceEpoch(scan.createdAt)
            .toIso8601String(),
        'total': scan.currentTotal,
        'overripe': scan.currentOverRipe,
        'ripe': scan.currentRipe,
        'unripe': scan.currentUnripe,
      };
    }).toList();
  }
}
