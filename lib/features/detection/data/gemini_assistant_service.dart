import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../domain/detection.dart';
import '../domain/mango_class.dart';

class CropVerdict {
  final int id;
  final bool isMango;
  final MangoClass? ripeness; // null if unknown
  final String rawRipeness; // 'unripe', 'ripe', 'overripe', 'unknown'
  final String reason;

  const CropVerdict({
    required this.id,
    required this.isMango,
    this.ripeness,
    required this.rawRipeness,
    required this.reason,
  });

  factory CropVerdict.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as num?)?.toInt() ?? -1;
    final isMango = json['is_mango'] == true || json['is_mango'] == 'true';
    final rawRipeness = (json['ripeness'] as String?)?.toLowerCase().trim() ?? 'unknown';

    MangoClass? ripeness;
    if (rawRipeness == 'unripe') {
      ripeness = MangoClass.unripe;
    } else if (rawRipeness == 'ripe') {
      ripeness = MangoClass.ripe;
    } else if (rawRipeness == 'overripe' || rawRipeness == 'over_ripe') {
      ripeness = MangoClass.over_ripe;
    }

    final reason = (json['reason'] as String?)?.trim() ?? '';

    return CropVerdict(
      id: id,
      isMango: isMango,
      ripeness: ripeness,
      rawRipeness: rawRipeness,
      reason: reason,
    );
  }
}

class AiAssistedDetectionResult {
  final List<Detection> reconciledDetections;
  final String providerName;
  final String summary;
  final int totalCount;
  final int overRipeCount;
  final int ripeCount;
  final int unripeCount;
  final int verifiedCount;
  final int rejectedCount;
  final int needsReviewCount;
  final bool success;
  final String? errorMessage;

  AiAssistedDetectionResult({
    required this.reconciledDetections,
    required this.providerName,
    required this.summary,
    required this.totalCount,
    required this.overRipeCount,
    required this.ripeCount,
    required this.unripeCount,
    this.verifiedCount = 0,
    this.rejectedCount = 0,
    this.needsReviewCount = 0,
    this.success = true,
    this.errorMessage,
  });
}

class GeminiAssistantService {
  /// Default and configurable constants
  static const String geminiModel = 'gemini-3.5-flash-lite';
  static const double candidateMinConfDefault = 0.15;
  static const double highConfKeepDefault = 0.50;
  static const double yoloClassKeepConfDefault = 0.60;
  static const int maxCropsPerBatch = 8;
  static const Duration apiTimeout = Duration(seconds: 8);
  static const double cropPaddingRatio = 0.15;

  static const String defaultApiKey =
      String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  static String formatModelName(String model) {
    if (model.contains('3.5-flash-lite')) return 'Gemini 3.5 Flash Lite';
    if (model.contains('3.5-flash')) return 'Gemini 3.5 Flash';
    if (model.contains('3.6-flash')) return 'Gemini 3.6 Flash';
    if (model.contains('3.7-flash')) return 'Gemini 3.7 Flash';
    if (model.contains('3.8-flash')) return 'Gemini 3.8 Flash';
    if (model.contains('flash-latest')) return 'Gemini Flash Latest';
    return model;
  }

  /// Probes whether active internet connectivity is available quickly.
  static Future<bool> hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('generativelanguage.googleapis.com')
          .timeout(const Duration(milliseconds: 2500));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      try {
        final result = await InternetAddress.lookup('google.com')
            .timeout(const Duration(milliseconds: 2500));
        return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      } catch (_) {
        return false;
      }
    }
  }

  /// Pure, unit-testable merge function.
  /// Central authority on merging YOLO detections with Gemini crop verdicts.
  static List<Detection> reconcileCropVerdicts({
    required List<Detection> yoloDetections,
    required Map<int, CropVerdict> cropVerdicts,
    double highConfKeep = highConfKeepDefault,
    double yoloClassKeepConf = yoloClassKeepConfDefault,
  }) {
    final List<Detection> result = [];

    for (int i = 0; i < yoloDetections.length; i++) {
      final yoloDet = yoloDetections[i];
      final verdict = cropVerdicts[i];

      // Always preserve user-edited boxes
      if (yoloDet.userEdited) {
        result.add(yoloDet);
        continue;
      }

      // If no verdict returned for this ID (missing, timeout, or malformed):
      // YOLO result is UNCHANGED.
      if (verdict == null) {
        result.add(yoloDet);
        continue;
      }

      // Rule C1 & C2:
      // Gemini can NEVER delete a YOLO box whose confidence >= highConfKeep.
      // For boxes below that, Gemini may remove ONLY if is_mango == false.
      if (!verdict.isMango && yoloDet.confidence < highConfKeep) {
        if (kDebugMode) {
          debugPrint('[Detection #$i] YOLO: ${yoloDet.mangoClass.label} (${yoloDet.confidence.toStringAsFixed(2)}) | '
              'Gemini: is_mango=${verdict.isMango}, ripeness=${verdict.rawRipeness}, reason="${verdict.reason}" | '
              'Decision: kept=false (removed false alarm), needsReview=false');
        }
        continue;
      }

      // Box is kept. Reconcile ripeness:
      // Rule C4:
      // - Keep YOLO's class when YOLO class confidence >= yoloClassKeepConf.
      // - When lower, use Gemini's ripeness if not "unknown".
      // - When both are confident and DISAGREE, keep YOLO's label and mark needsReview = true.
      MangoClass finalClass = yoloDet.mangoClass;
      bool needsReview = false;
      final bool geminiHasClass = verdict.ripeness != null;

      if (yoloDet.confidence >= yoloClassKeepConf) {
        if (geminiHasClass && verdict.ripeness != yoloDet.mangoClass) {
          finalClass = yoloDet.mangoClass;
          needsReview = true;
        } else {
          finalClass = yoloDet.mangoClass;
          needsReview = false;
        }
      } else {
        if (geminiHasClass) {
          finalClass = verdict.ripeness!;
          needsReview = false;
        } else {
          finalClass = yoloDet.mangoClass;
          needsReview = false;
        }
      }

      if (kDebugMode) {
        debugPrint('[Detection #$i] YOLO: ${yoloDet.mangoClass.label} (${yoloDet.confidence.toStringAsFixed(2)}) | '
            'Gemini: is_mango=${verdict.isMango}, ripeness=${verdict.rawRipeness}, reason="${verdict.reason}" | '
            'Decision: class=${finalClass.label}, kept=true, needsReview=$needsReview');
      }

      // Rule C5: Never display a numeric confidence for anything Gemini decided.
      // Show the real YOLO score; mark Gemini-confirmed boxes with aiVerified = true.
      result.add(yoloDet.copyWith(
        mangoClass: finalClass,
        aiVerified: true,
        aiReason: verdict.reason,
        needsReview: needsReview,
      ));
    }

    return result;
  }

  /// Crops candidate bounding boxes from the full-resolution image with ~15% padding,
  /// clamped strictly to the original image bounds.
  static List<({int id, Uint8List jpegBytes})> extractCrops({
    required Uint8List fullImageBytes,
    required List<Detection> detections,
    double candidateMinConf = candidateMinConfDefault,
    double paddingRatio = cropPaddingRatio,
  }) {
    final decoded = img.decodeImage(fullImageBytes);
    if (decoded == null) return [];
    final oriented = img.bakeOrientation(decoded);
    final int origW = oriented.width;
    final int origH = oriented.height;

    final List<({int id, Uint8List jpegBytes})> crops = [];

    for (int i = 0; i < detections.length; i++) {
      final d = detections[i];
      if (d.userEdited) continue;
      if (d.confidence < candidateMinConf) continue;

      final double bw = d.x2 - d.x1;
      final double bh = d.y2 - d.y1;
      // Cap absolute padding to 3% of image dimension so large boxes do not bleed into neighboring fruits
      final double maxPadX = origW * 0.03;
      final double maxPadY = origH * 0.03;
      final double padX = min(bw * paddingRatio, maxPadX);
      final double padY = min(bh * paddingRatio, maxPadY);

      final int x1 = (d.x1 - padX).clamp(0.0, origW.toDouble()).toInt();
      final int y1 = (d.y1 - padY).clamp(0.0, origH.toDouble()).toInt();
      final int x2 = (d.x2 + padX).clamp(0.0, origW.toDouble()).toInt();
      final int y2 = (d.y2 + padY).clamp(0.0, origH.toDouble()).toInt();

      final int cropW = max(1, x2 - x1);
      final int cropH = max(1, y2 - y1);

      final crop = img.copyCrop(oriented, x: x1, y: y1, width: cropW, height: cropH);
      // Downscale crop to max 256px for minimal payload & quick latency
      img.Image toSend = crop;
      if (max(cropW, cropH) > 256) {
        if (cropW >= cropH) {
          toSend = img.copyResize(crop, width: 256, interpolation: img.Interpolation.linear);
        } else {
          toSend = img.copyResize(crop, height: 256, interpolation: img.Interpolation.linear);
        }
      }

      final jpgBytes = Uint8List.fromList(img.encodeJpg(toSend, quality: 80));
      crops.add((id: i, jpegBytes: jpgBytes));
    }

    return crops;
  }

  /// Sends a batch of crops to Google Gemini Vision using structured JSON output.
  static Future<Map<int, CropVerdict>> verifyCropsBatch({
    required List<({int id, Uint8List jpegBytes})> crops,
    required String apiKey,
    String model = geminiModel,
  }) async {
    if (crops.isEmpty) return {};

    final effectiveKey = apiKey.trim().isNotEmpty ? apiKey.trim() : defaultApiKey;
    if (effectiveKey.isEmpty) {
      throw Exception('Gemini API key is empty');
    }

    final List<Map<String, dynamic>> parts = [
      {
        "text": '''
You are an expert mango orchard inspector.
Examine each numbered crop closely.
TASK:
- Judge ONLY the fruit that occupies the CENTER of each crop.
- If the center of the crop is background (grass, lawn, ground, leaves, branch, trunk, sky) and a fruit only touches an outer perimeter edge, return is_mango=false.
- A partially occluded or partial mango still counts as a mango (is_mango=true) ONLY if it is centered in the crop.
- If unsure, return is_mango=true and ripeness="unknown" rather than rejecting.
- Ripeness enum: "unripe" (green peel), "ripe" (yellow/golden/orange), "overripe" (brown rot/decay), "unknown".
- Keep every reason under 6 words.
'''
      }
    ];

    for (final crop in crops) {
      parts.add({"text": "Crop #${crop.id}:"});
      parts.add({
        "inline_data": {
          "mime_type": "image/jpeg",
          "data": base64Encode(crop.jpegBytes),
        }
      });
    }

    final requestBody = jsonEncode({
      "contents": [{"parts": parts}],
      "generationConfig": {
        "response_mime_type": "application/json",
        "response_schema": {
          "type": "OBJECT",
          "properties": {
            "results": {
              "type": "ARRAY",
              "items": {
                "type": "OBJECT",
                "properties": {
                  "id": {"type": "INTEGER"},
                  "is_mango": {"type": "BOOLEAN"},
                  "ripeness": {
                    "type": "STRING",
                    "enum": ["unripe", "ripe", "overripe", "unknown"]
                  },
                  "reason": {"type": "STRING"}
                },
                "required": ["id", "is_mango", "ripeness", "reason"]
              }
            }
          },
          "required": ["results"]
        },
        "temperature": 0.0,
      }
    });

    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$effectiveKey');

    // Request with 8s timeout and 1 single retry
    http.Response? response;
    Exception? lastException;

    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: requestBody,
        ).timeout(apiTimeout);

        if (response.statusCode == 200) break;
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw Exception('Gemini authentication failed (${response.statusCode})');
        }
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        if (attempt == 1) rethrow;
      }
    }

    if (response == null || response.statusCode != 200) {
      throw lastException ?? Exception('Gemini request failed: ${response?.statusCode} ${response?.body}');
    }

    final data = jsonDecode(response.body);
    final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ?? '';
    if (text.isEmpty) return {};

    final Map<int, CropVerdict> verdicts = {};
    try {
      final parsed = jsonDecode(text);
      final results = parsed['results'];
      if (results is List) {
        for (final item in results) {
          if (item is Map<String, dynamic>) {
            final verdict = CropVerdict.fromJson(item);
            if (verdict.id >= 0) {
              verdicts[verdict.id] = verdict;
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Gemini JSON Parse Error]: $e');
    }

    return verdicts;
  }

  /// High-level method: extracts crops, batches them, queries Gemini, and reconciles verdicts.
  /// Fully defensive: on any network or parsing failure, falls back to original YOLO detections.
  static Future<AiAssistedDetectionResult> assistDetectionAndCount({
    required Uint8List fullImageBytes,
    required List<Detection> existingYoloDetections,
    required int imageWidth,
    required int imageHeight,
    String geminiApiKey = '',
    String model = geminiModel,
    double candidateMinConf = candidateMinConfDefault,
    double highConfKeep = highConfKeepDefault,
    double yoloClassKeepConf = yoloClassKeepConfDefault,
  }) async {
    if (existingYoloDetections.isEmpty) {
      return buildFallbackResult(
        detections: existingYoloDetections,
        providerName: formatModelName(model),
        summary: 'No detections to verify',
      );
    }

    try {
      // 1. Extract crops in background isolate
      final crops = await Isolate.run(() => extractCrops(
            fullImageBytes: fullImageBytes,
            detections: existingYoloDetections,
            candidateMinConf: candidateMinConf,
          ));

      if (crops.isEmpty) {
        return buildFallbackResult(
          detections: existingYoloDetections,
          providerName: formatModelName(model),
          summary: 'All candidates below confidence threshold ($candidateMinConf)',
        );
      }

      // 2. Batch crops (max 8 per batch)
      final Map<int, CropVerdict> allVerdicts = {};

      for (int i = 0; i < crops.length; i += maxCropsPerBatch) {
        final end = min(i + maxCropsPerBatch, crops.length);
        final batch = crops.sublist(i, end);
        final batchVerdicts = await verifyCropsBatch(
          crops: batch,
          apiKey: geminiApiKey,
          model: model,
        );
        allVerdicts.addAll(batchVerdicts);
      }

      // 3. Central reconciliation
      final reconciled = reconcileCropVerdicts(
        yoloDetections: existingYoloDetections,
        cropVerdicts: allVerdicts,
        highConfKeep: highConfKeep,
        yoloClassKeepConf: yoloClassKeepConf,
      );

      final verified = reconciled.where((d) => d.aiVerified).length;
      final rejected = existingYoloDetections.length - reconciled.length;
      final needsReview = reconciled.where((d) => d.needsReview).length;

      final overRipe = reconciled.where((d) => d.mangoClass == MangoClass.over_ripe).length;
      final ripe = reconciled.where((d) => d.mangoClass == MangoClass.ripe).length;
      final unripe = reconciled.where((d) => d.mangoClass == MangoClass.unripe).length;

      return AiAssistedDetectionResult(
        reconciledDetections: reconciled,
        providerName: 'Google ${formatModelName(model)}',
        summary: 'Verified $verified fruit${verified == 1 ? '' : 's'}'
            '${rejected > 0 ? ', removed $rejected non-mango${rejected == 1 ? '' : 'es'}' : ''}'
            '${needsReview > 0 ? ', $needsReview need review (?)' : ''}',
        totalCount: reconciled.length,
        overRipeCount: overRipe,
        ripeCount: ripe,
        unripeCount: unripe,
        verifiedCount: verified,
        rejectedCount: rejected,
        needsReviewCount: needsReview,
        success: true,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Gemini AI Verification Error]: $e');
      return buildFallbackResult(
        detections: existingYoloDetections,
        providerName: formatModelName(model),
        summary: 'AI check unavailable',
        errorMessage: e.toString(),
        success: false,
      );
    }
  }

  static AiAssistedDetectionResult buildFallbackResult({
    required List<Detection> detections,
    required String providerName,
    required String summary,
    String? errorMessage,
    bool success = true,
  }) {
    final overRipe = detections.where((d) => d.mangoClass == MangoClass.over_ripe).length;
    final ripe = detections.where((d) => d.mangoClass == MangoClass.ripe).length;
    final unripe = detections.where((d) => d.mangoClass == MangoClass.unripe).length;

    return AiAssistedDetectionResult(
      reconciledDetections: detections,
      providerName: providerName,
      summary: summary,
      totalCount: detections.length,
      overRipeCount: overRipe,
      ripeCount: ripe,
      unripeCount: unripe,
      verifiedCount: 0,
      rejectedCount: 0,
      needsReviewCount: 0,
      success: success,
      errorMessage: errorMessage,
    );
  }
}
