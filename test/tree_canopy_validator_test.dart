import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:mangocounter/features/video_scan/data/tree_canopy_validator.dart';

void main() {
  group('TreeCanopyValidator Offline Heuristics', () {
    test('Rejects solid white blank ceiling image', () {
      final image = img.Image(width: 100, height: 100);
      for (int y = 0; y < 100; y++) {
        for (int x = 0; x < 100; x++) {
          image.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
      final bytes = Uint8List.fromList(img.encodeJpg(image));

      final result = TreeCanopyValidator.validateOfflineFoliage(bytes);
      expect(result.isMangoTree, isFalse);
      expect(result.detectedSubject, contains('Blank'));
    });

    test('Rejects pitch black / covered lens image', () {
      final image = img.Image(width: 100, height: 100);
      for (int y = 0; y < 100; y++) {
        for (int x = 0; x < 100; x++) {
          image.setPixelRgba(x, y, 0, 0, 0, 255);
        }
      }
      final bytes = Uint8List.fromList(img.encodeJpg(image));

      final result = TreeCanopyValidator.validateOfflineFoliage(bytes);
      expect(result.isMangoTree, isFalse);
    });

    test('Rejects indoor gray desk / neutral floor image with no foliage', () {
      final image = img.Image(width: 100, height: 100);
      for (int y = 0; y < 100; y++) {
        for (int x = 0; x < 100; x++) {
          // Gray desk tones with wood/surface grain variance (R=140, G=135, B=130 +/- grain)
          final grain = (x % 15) * 2;
          image.setPixelRgba(x, y, 140 + grain, 135 + grain, 130 + grain, 255);
        }
      }
      final bytes = Uint8List.fromList(img.encodeJpg(image));

      final result = TreeCanopyValidator.validateOfflineFoliage(bytes);
      expect(result.isMangoTree, isFalse);
      expect(result.detectedSubject, contains('Non-Canopy'));
    });

    test('Accepts foliage canopy image with chlorophyll-dominant green tones',
        () {
      final image = img.Image(width: 100, height: 100);
      for (int y = 0; y < 100; y++) {
        for (int x = 0; x < 100; x++) {
          // Lush canopy green tones (R=45, G=130, B=40)
          image.setPixelRgba(x, y, 45, 130, 40, 255);
        }
      }
      final bytes = Uint8List.fromList(img.encodeJpg(image));

      final result = TreeCanopyValidator.validateOfflineFoliage(bytes);
      expect(result.isMangoTree, isTrue);
      expect(result.foliageRatio, greaterThan(0.50));
      expect(result.detectedSubject, contains('Foliage Canopy'));
    });
  });

  group('TreeCanopyValidator Online Gemini AI Gatekeeper', () {
    test(
        'calls Gemini when DNS preflight reports offline but an API key exists',
        () async {
      var called = false;
      final mockClient = MockClient((_) async {
        called = true;
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text': jsonEncode({
                        'is_mango_tree': true,
                        'detected_subject': 'Mango Canopy',
                        'reason': 'Mango foliage detected',
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
      final validator = TreeCanopyValidator(
        client: mockClient,
        internetCheckOverride: () async => false,
      );
      final bytes =
          Uint8List.fromList(img.encodeJpg(img.Image(width: 50, height: 50)));

      final result = await validator.validateCanopy(bytes, apiKey: 'test-key');

      expect(called, isTrue);
      expect(result.isOnline, isTrue);
    });

    test('Online Gemini rejects indoor office nonsense video', () async {
      late http.Request observedRequest;
      final mockClient = MockClient((request) async {
        observedRequest = request;
        final mockJsonResponse = {
          "candidates": [
            {
              "content": {
                "parts": [
                  {
                    "text": jsonEncode({
                      "is_mango_tree": false,
                      "confidence": 0.98,
                      "detected_subject": "Indoor Office Desk",
                      "reason":
                          "Subject is a computer keyboard and indoor office desk."
                    })
                  }
                ]
              }
            }
          ]
        };

        return http.Response(jsonEncode(mockJsonResponse), 200, headers: {
          'content-type': 'application/json',
        });
      });

      final validator = TreeCanopyValidator(
        client: mockClient,
        internetCheckOverride: () async => true,
      );

      final image = img.Image(width: 50, height: 50);
      final bytes = Uint8List.fromList(img.encodeJpg(image));

      final result = await validator.validateCanopy(bytes, apiKey: 'test-key');
      expect(result.isMangoTree, isFalse);
      expect(result.isOnline, isTrue);
      expect(result.detectedSubject, equals('Indoor Office Desk'));
      expect(result.reason, contains('office desk'));
      final requestBody =
          jsonDecode(observedRequest.body) as Map<String, dynamic>;
      expect(observedRequest.url.queryParameters.containsKey('key'), isFalse);
      expect(observedRequest.headers['x-goog-api-key'], 'test-key');
      expect(requestBody['generationConfig'], contains('responseFormat'));
      expect(requestBody['generationConfig'], isNot(contains('temperature')));
    });

    test('Online Gemini accepts mango tree canopy video', () async {
      final mockClient = MockClient((request) async {
        final mockJsonResponse = {
          "candidates": [
            {
              "content": {
                "parts": [
                  {
                    "text": jsonEncode({
                      "is_mango_tree": true,
                      "confidence": 0.96,
                      "detected_subject": "Mango Tree Canopy",
                      "reason":
                          "Confirmed outdoor mango tree branches and foliage canopy."
                    })
                  }
                ]
              }
            }
          ]
        };

        return http.Response(jsonEncode(mockJsonResponse), 200, headers: {
          'content-type': 'application/json',
        });
      });

      final validator = TreeCanopyValidator(
        client: mockClient,
        internetCheckOverride: () async => true,
      );

      final image = img.Image(width: 50, height: 50);
      final bytes = Uint8List.fromList(img.encodeJpg(image));

      final result = await validator.validateCanopy(bytes, apiKey: 'test-key');
      expect(result.isMangoTree, isTrue);
      expect(result.isOnline, isTrue);
      expect(result.detectedSubject, equals('Mango Tree Canopy'));
      expect(result.confidence, equals(0.96));
    });

    test('Online Gemini network failure falls back gracefully to offline check',
        () async {
      final mockClient = MockClient((request) async {
        return http.Response('Server error', 500);
      });

      final validator = TreeCanopyValidator(
        client: mockClient,
        internetCheckOverride: () async => true,
      );

      // Create green canopy image to verify offline fallback accepts it
      final image = img.Image(width: 50, height: 50);
      for (int y = 0; y < 50; y++) {
        for (int x = 0; x < 50; x++) {
          image.setPixelRgba(x, y, 40, 125, 35, 255);
        }
      }
      final bytes = Uint8List.fromList(img.encodeJpg(image));

      final result = await validator.validateCanopy(bytes, apiKey: 'test-key');
      // Graceful fallback to offline heuristic
      expect(result.isMangoTree, isTrue);
      expect(result.isOnline, isFalse);
      expect(result.detectedSubject, contains('Foliage Canopy'));
    });
  });

  group('InvalidTreeVideoException & Canopy Edge Cases', () {
    test('Throws InvalidTreeVideoException with proper metadata', () {
      const exception = InvalidTreeVideoException(
        reason: 'Indoor living room detected',
        detectedSubject: 'Living Room',
        isOnline: true,
      );

      expect(exception.toString(), equals('Indoor living room detected'));
      expect(exception.detectedSubject, equals('Living Room'));
      expect(exception.isOnline, isTrue);
    });

    test('Empty image bytes returns non-mango tree validation result',
        () async {
      const validator = TreeCanopyValidator();
      final result = await validator.validateCanopy(Uint8List(0));
      expect(result.isMangoTree, isFalse);
      expect(result.detectedSubject, equals('Empty Frame'));
    });
  });
}
