import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mangocounter/features/detection/data/gemini_assistant_service.dart';
import 'package:mangocounter/features/detection/domain/detection.dart';
import 'package:mangocounter/features/detection/domain/mango_class.dart';
import 'package:mangocounter/features/settings/application/settings_controller.dart';

void main() {
  test('CropVerdict instantiates correctly', () {
    const verdict = CropVerdict(
      id: 0,
      isMango: true,
      ripeness: MangoClass.over_ripe,
      rawRipeness: 'overripe',
      reason: 'Golden yellow peel with brownish wrinkles',
    );

    expect(verdict.isMango, isTrue);
    expect(verdict.ripeness, MangoClass.over_ripe);
    expect(verdict.rawRipeness, 'overripe');
    expect(verdict.reason, contains('brownish wrinkles'));
  });

  test('MangoClass maps indices and strings correctly', () {
    expect(MangoClass.fromIndex(0), MangoClass.over_ripe);
    expect(MangoClass.fromIndex(1), MangoClass.ripe);
    expect(MangoClass.fromIndex(2), MangoClass.unripe);

    expect(MangoClass.fromString('over_ripe'), MangoClass.over_ripe);
    expect(MangoClass.fromString('Over ripe'), MangoClass.over_ripe);
    expect(MangoClass.fromString('ripe'), MangoClass.ripe);
    expect(MangoClass.fromString('unripe'), MangoClass.unripe);

    expect(MangoClass.over_ripe.displayName, 'Over-ripe');
    expect(MangoClass.ripe.displayName, 'Ripe');
    expect(MangoClass.unripe.displayName, 'Unripe');
  });

  test(
      'AiAssistedDetectionResult instantiates correctly with Gemini AI provider',
      () {
    final res = AiAssistedDetectionResult(
      reconciledDetections: const [
        Detection(
            x1: 10,
            y1: 10,
            x2: 50,
            y2: 50,
            mangoClass: MangoClass.over_ripe,
            confidence: 0.92),
        Detection(
            x1: 60,
            y1: 60,
            x2: 120,
            y2: 120,
            mangoClass: MangoClass.ripe,
            confidence: 0.95),
        Detection(
            x1: 130,
            y1: 130,
            x2: 200,
            y2: 200,
            mangoClass: MangoClass.unripe,
            confidence: 0.88),
      ],
      providerName: 'Google Gemini (Gemini Flash-Lite)',
      summary: 'Verified 3 mangoes on tree using Gemini AI',
      totalCount: 3,
      overRipeCount: 1,
      ripeCount: 1,
      unripeCount: 1,
      needsReviewCount: 1,
      verifiedCount: 2,
    );

    expect(res.totalCount, 3);
    expect(res.overRipeCount, 1);
    expect(res.ripeCount, 1);
    expect(res.unripeCount, 1);
    expect(res.needsReviewCount, 1);
    expect(res.verifiedCount, 2);
    expect(res.providerName, 'Google Gemini (Gemini Flash-Lite)');
  });

  test('SettingsState defaults to gemini provider and tiled inference', () {
    final state = SettingsState();
    expect(state.aiProvider, 'gemini');
    expect(state.tiledInference, isTrue);
    expect(state.autoConfidence, isTrue);
    expect(state.autoAiAssist, isTrue);
  });

  group('Gemini crop verification request', () {
    test('uses the current structured-output contract and header API key',
        () async {
      late http.Request observedRequest;
      final client = MockClient((request) async {
        observedRequest = request;
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text': jsonEncode({
                        'results': [
                          {
                            'id': 7,
                            'is_mango': true,
                            'ripeness': 'ripe',
                            'reason': 'Golden peel visible',
                          }
                        ]
                      })
                    }
                  ]
                }
              }
            ]
          }),
          200,
        );
      });

      final verdicts = await GeminiAssistantService.verifyCropsBatch(
        crops: [
          (id: 7, jpegBytes: Uint8List.fromList([1, 2, 3]))
        ],
        apiKey: 'test-key',
        client: client,
      );

      final body = jsonDecode(observedRequest.body) as Map<String, dynamic>;
      final generationConfig = body['generationConfig'] as Map<String, dynamic>;
      final parts = ((body['contents'] as List).single
          as Map<String, dynamic>)['parts'] as List;
      final inlineData = (parts.last as Map<String, dynamic>)['inlineData']
          as Map<String, dynamic>;

      expect(observedRequest.url.queryParameters.containsKey('key'), isFalse);
      expect(observedRequest.headers['x-goog-api-key'], 'test-key');
      expect(generationConfig, contains('responseFormat'));
      expect(generationConfig, isNot(contains('temperature')));
      expect(inlineData['mimeType'], 'image/jpeg');
      expect(inlineData, isNot(contains('mime_type')));
      expect(verdicts[7]?.ripeness, MangoClass.ripe);
    });

    test('converts invalid API requests into a safe user-facing error',
        () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({
              'error': {'message': 'Unknown name "temperature"'},
            }),
            400,
          ));

      await expectLater(
        GeminiAssistantService.verifyCropsBatch(
          crops: [
            (id: 0, jpegBytes: Uint8List.fromList([1]))
          ],
          apiKey: 'test-key',
          client: client,
        ),
        throwsA(
          isA<GeminiApiException>()
              .having((error) => error.statusCode, 'status code', 400)
              .having(
                (error) => error.message,
                'message',
                'Gemini rejected this request. Update the app or try again.',
              ),
        ),
      );
    });
  });
}
