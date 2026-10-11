import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../../detection/data/gemini_assistant_service.dart';

/// Result of canopy pre-validation check before running multi-frame video inference.
class CanopyValidationResult {
  final bool isMangoTree;
  final bool isOnline;
  final double confidence;
  final String detectedSubject;
  final String reason;
  final double foliageRatio;

  const CanopyValidationResult({
    required this.isMangoTree,
    required this.isOnline,
    this.confidence = 1.0,
    required this.detectedSubject,
    required this.reason,
    this.foliageRatio = 0.0,
  });

  @override
  String toString() =>
      'CanopyValidationResult(isMangoTree: $isMangoTree, isOnline: $isOnline, '
      'subject: "$detectedSubject", confidence: $confidence, reason: "$reason", '
      'foliageRatio: ${(foliageRatio * 100).toStringAsFixed(1)}%)';
}

/// Thrown when a video does not depict a mango tree canopy, saving processing time.
class InvalidTreeVideoException implements Exception {
  final String reason;
  final String detectedSubject;
  final bool isOnline;

  const InvalidTreeVideoException({
    required this.reason,
    this.detectedSubject = 'Non-tree scene',
    this.isOnline = false,
  });

  @override
  String toString() => reason;
}

/// Validates whether the first keyframe of a video depicts a mango tree canopy.
///
/// If an internet connection is available, queries Google Gemini Vision (`gemini-3.8-flash` /
/// `gemini-3.5-flash-lite`) to verify mango tree semantics and reject nonsense subjects
/// (indoor rooms, cars, furniture, human selfies, screens).
///
/// If offline, executes a zero-latency on-device foliage chlorophyll analysis to reject
/// blank, indoor, or non-vegetation frames while allowing tree canopies through to YOLO.
class TreeCanopyValidator {
  final http.Client? _client;
  final Future<bool> Function()? _internetCheckOverride;
  final String primaryModel;
  final String fallbackModel;

  static const Duration apiTimeout = Duration(seconds: 6);

  const TreeCanopyValidator({
    http.Client? client,
    Future<bool> Function()? internetCheckOverride,
    this.primaryModel = 'gemini-3.8-flash',
    this.fallbackModel = 'gemini-3.5-flash-lite',
  })  : _client = client,
        _internetCheckOverride = internetCheckOverride;

  /// Checks if active internet is available.
  Future<bool> checkInternet() async {
    if (_internetCheckOverride != null) {
      return await _internetCheckOverride();
    }
    return await GeminiAssistantService.hasInternetConnection();
  }

  /// Main validation entry point.
  Future<CanopyValidationResult> validateCanopy(
    Uint8List frameBytes, {
    String apiKey = '',
  }) async {
    if (frameBytes.isEmpty) {
      return const CanopyValidationResult(
        isMangoTree: false,
        isOnline: false,
        detectedSubject: 'Empty Frame',
        reason: 'Unable to extract initial video keyframe.',
      );
    }

    final effectiveKey = apiKey.trim().isNotEmpty
        ? apiKey.trim()
        : GeminiAssistantService.defaultApiKey;
    // Do not use DNS as a gate for the actual API request. Mobile networks,
    // private DNS, and captive portals can resolve differently from the HTTP
    // client, which produced false "offline" results on connected devices.
    // The Gemini request itself is the authoritative connectivity check.
    final hasNet = effectiveKey.isNotEmpty;

    // 1. Online AI Verification via Gemini Vision
    if (hasNet) {
      if (effectiveKey.isNotEmpty) {
        try {
          final onlineResult = await _validateWithGemini(
            frameBytes: frameBytes,
            apiKey: effectiveKey,
            model: primaryModel,
          );
          if (onlineResult != null) {
            return onlineResult;
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
                '[TreeCanopyValidator] Primary model ($primaryModel) error: $e');
          }
          // Attempt fallback model
          if (primaryModel != fallbackModel) {
            try {
              final fallbackResult = await _validateWithGemini(
                frameBytes: frameBytes,
                apiKey: effectiveKey,
                model: fallbackModel,
              );
              if (fallbackResult != null) {
                return fallbackResult;
              }
            } catch (fallbackError) {
              if (kDebugMode) {
                debugPrint(
                    '[TreeCanopyValidator] Fallback model error: $fallbackError');
              }
            }
          }
        }
      }
    }

    // 2. Offline / Network-Fallback Local Foliage Analysis
    return validateOfflineFoliage(frameBytes);
  }

  /// Sends downscaled frame to Gemini Vision for semantic canopy verification.
  Future<CanopyValidationResult?> _validateWithGemini({
    required Uint8List frameBytes,
    required String apiKey,
    required String model,
  }) async {
    // Downscale frame to max 400px width for fast upload (~25KB payload)
    Uint8List optimizedJpgBytes = frameBytes;
    try {
      final decoded = img.decodeImage(frameBytes);
      if (decoded != null) {
        final oriented = img.bakeOrientation(decoded);
        final resized = oriented.width > 400 || oriented.height > 400
            ? img.copyResize(oriented,
                width: 400, interpolation: img.Interpolation.linear)
            : oriented;
        optimizedJpgBytes =
            Uint8List.fromList(img.encodeJpg(resized, quality: 75));
      }
    } catch (_) {}

    final List<Map<String, dynamic>> parts = [
      {
        "text": '''
You are an expert tropical agricultural optical inspector for the MangoCount orchard system.
Analyze this camera frame captured at the start of a whole-tree video scan.
Determine whether this video frame depicts a mango tree, orchard canopy, mango branches, foliage, or mango fruit clusters.

CRITICAL RULES:
1. NON-TREE REJECTION:
   If the image depicts an indoor scene (office, bedroom, living room, ceiling, walls, floor, keyboard, computer monitor, paperwork, desk, household furniture), a vehicle/car (dashboard, windshield, interior), human faces/selfies, pets/animals, city streets, pavements, or any non-agricultural / non-tree scene:
   You MUST return "is_mango_tree": false.

2. TREE ACCEPTANCE:
   If the image shows a mango tree canopy, orchard branches, tropical tree foliage, green leaves, or mango fruit clusters:
   Return "is_mango_tree": true.
   (If it is an outdoor foliage canopy or fruit tree in an orchard environment, return "is_mango_tree": true).

3. REASON:
   Keep "reason" under 15 words explaining what was detected.
   For example: "Indoor office desk and monitor detected." or "Mango tree canopy with green foliage verified."

4. DETECTED SUBJECT:
   A short 2-5 word label of the primary subject (e.g. "Indoor Office", "Car Dashboard", "Mango Canopy", "Tree Foliage", "Human Selfie", "Blank Wall").
'''
      },
      {
        "inlineData": {
          "mimeType": "image/jpeg",
          "data": base64Encode(optimizedJpgBytes),
        }
      }
    ];

    final requestBody = jsonEncode({
      "contents": [
        {"parts": parts}
      ],
      "generationConfig": {
        "responseFormat": {
          "text": {
            "mimeType": "application/json",
            "schema": {
              "type": "object",
              "properties": {
                "is_mango_tree": {"type": "boolean"},
                "confidence": {"type": "number"},
                "detected_subject": {"type": "string"},
                "reason": {"type": "string"}
              },
              "required": ["is_mango_tree", "detected_subject", "reason"]
            }
          }
        }
      }
    });

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
    );

    final client = _client ?? http.Client();
    try {
      final response = await client
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
            body: requestBody,
          )
          .timeout(apiTimeout);

      if (response.statusCode != 200) {
        throw GeminiApiException.fromResponse(response);
      }

      final data = jsonDecode(response.body);
      final text = data['candidates']?[0]?['content']?['parts']?[0]?['text']
              as String? ??
          '';
      if (text.isEmpty) return null;

      final parsed = jsonDecode(text) as Map<String, dynamic>;
      final isMangoTree =
          parsed['is_mango_tree'] == true || parsed['is_mango_tree'] == 'true';
      final detectedSubject =
          (parsed['detected_subject'] as String?)?.trim() ?? 'Unknown scene';
      final reason = (parsed['reason'] as String?)?.trim() ??
          (isMangoTree
              ? 'Mango tree canopy verified by AI.'
              : 'Non-tree scene detected.');
      final confidence = (parsed['confidence'] as num?)?.toDouble() ??
          (isMangoTree ? 0.95 : 0.90);

      return CanopyValidationResult(
        isMangoTree: isMangoTree,
        isOnline: true,
        confidence: confidence,
        detectedSubject: detectedSubject,
        reason: reason,
      );
    } finally {
      if (_client == null) client.close();
    }
  }

  /// On-device pixel chlorophyll and color distribution analysis for offline orchard use.
  static CanopyValidationResult validateOfflineFoliage(Uint8List frameBytes) {
    final stats = analyzeFoliageColor(frameBytes);

    if (stats.isMonotoneBlank) {
      return CanopyValidationResult(
        isMangoTree: false,
        isOnline: false,
        confidence: 0.95,
        detectedSubject: 'Blank or Obstructed Frame',
        reason:
            'Camera view appears completely blank or obstructed (offline check).',
        foliageRatio: stats.foliageRatio,
      );
    }

    // A mango tree canopy in orchard lighting typically occupies >= 6% of the frame.
    // Indoor rooms, cars, desks, walls, and boots typically have < 3% green chlorophyll tones.
    const double minimumFoliageRatio = 0.06;

    if (stats.foliageRatio < minimumFoliageRatio) {
      final percentage = (stats.foliageRatio * 100).toStringAsFixed(1);
      return CanopyValidationResult(
        isMangoTree: false,
        isOnline: false,
        confidence: 0.88,
        detectedSubject: 'Non-Canopy Subject',
        reason:
            'No tree foliage detected in camera view (only $percentage% vegetation found).',
        foliageRatio: stats.foliageRatio,
      );
    }

    final percentage = (stats.foliageRatio * 100).toStringAsFixed(1);
    return CanopyValidationResult(
      isMangoTree: true,
      isOnline: false,
      confidence: 0.80,
      detectedSubject: 'Outdoor Foliage Canopy',
      reason:
          'Foliage canopy confirmed ($percentage% green chlorophyll tones).',
      foliageRatio: stats.foliageRatio,
    );
  }

  /// Computes green vegetation / chlorophyll ratio and detects monotone frames.
  static ({double foliageRatio, bool isMonotoneBlank}) analyzeFoliageColor(
      Uint8List frameBytes) {
    final decoded = img.decodeImage(frameBytes);
    if (decoded == null) {
      return (foliageRatio: 0.0, isMonotoneBlank: true);
    }

    final oriented = img.bakeOrientation(decoded);
    // Downsample to max 128x128 grid for ultra-fast <5ms execution
    final sampleW = min(128, oriented.width);
    final sampleH = min(128, oriented.height);
    final sampled = img.copyResize(
      oriented,
      width: sampleW,
      height: sampleH,
      interpolation: img.Interpolation.nearest,
    );

    final int totalPixels = sampleW * sampleH;
    int greenCanopyPixels = 0;
    double sumLuminance = 0.0;
    double sumLuminanceSq = 0.0;

    for (int y = 0; y < sampleH; y++) {
      for (int x = 0; x < sampleW; x++) {
        final pixel = sampled.getPixel(x, y);
        final num r = pixel.r;
        final num g = pixel.g;
        final num b = pixel.b;

        // Luminance calculation: standard ITU-R BT.601
        final double lum = 0.299 * r + 0.587 * g + 0.114 * b;
        sumLuminance += lum;
        sumLuminanceSq += lum * lum;

        // 1. Direct RGB dominance: Green is significantly higher than red and blue,
        // and above dark shadow floor (g >= 30)
        final bool isGreenDominant =
            g >= 30 && g > (r * 1.05) && g > (b * 1.12);

        // 2. HSV Hue range: Yellow-green to deep forest green leaves (Hue ~45° to ~165°)
        final num maxC = max(r, max(g, b));
        final num minC = min(r, min(g, b));
        final num delta = maxC - minC;

        bool isFoliage = isGreenDominant;
        if (!isFoliage && delta > 15 && maxC == g) {
          final double hue = 60 * (((b - r) / delta) + 2);
          final double sat = delta / maxC;
          if (hue >= 45 && hue <= 165 && sat >= 0.15 && maxC >= 35) {
            isFoliage = true;
          }
        }

        if (isFoliage) {
          greenCanopyPixels++;
        }
      }
    }

    final double meanLum = totalPixels > 0 ? (sumLuminance / totalPixels) : 0.0;
    final double variance = totalPixels > 0
        ? (sumLuminanceSq / totalPixels) - (meanLum * meanLum)
        : 0.0;

    final double foliageRatio =
        totalPixels > 0 ? (greenCanopyPixels / totalPixels) : 0.0;
    // Check if frame is pure monotone (e.g. solid white ceiling, pitch black pocket, or flat blank wall with zero foliage)
    final bool isMonotoneBlank = meanLum > 248.0 ||
        meanLum < 12.0 ||
        (foliageRatio < 0.03 && variance < 12.0);

    return (foliageRatio: foliageRatio, isMonotoneBlank: isMonotoneBlank);
  }
}
