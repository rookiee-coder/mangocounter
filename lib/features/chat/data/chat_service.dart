import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../domain/chat_message.dart';
import '../domain/scan_chat_context.dart';
import '../../detection/data/gemini_assistant_service.dart';

class ChatService {
  static const String defaultModel = 'gemini-3.8-flash';
  static const String fallbackModel = 'gemini-3.5-flash-lite';
  static const Duration timeoutDuration = Duration(seconds: 14);

  static const String systemInstruction = '''
You are "MangoCount AI Agronomist", a specialized tropical pomologist, agricultural researcher, and mango orchard management consultant.

════════════════════════════════════════════════════════════════
STRICT DOMAIN SCOPE & BOUNDARY RULES
════════════════════════════════════════════════════════════════
You MUST strictly adhere to the following domain boundaries at all times:

1. IN-SCOPE TOPICS (ONLY answer inquiries in these areas):
   • Mango tree pomology, biology, flowering induction (potassium nitrate KNO3, paclobutrazol safety), vegetative flushing, and pruning techniques.
   • Mango fruit varieties (e.g. Carabao/Manila, Tommy Atkins, Kensington Pride, Kent, Keitt, Alphonso, Nam Dok Mai, Haden, Apple Mango).
   • Canopy scan telemetry, yield counts, fruit density estimation, and ripeness stages (unripe/green, ripe/harvest-ready, over-ripe/senescent).
   • Harvest maturity indicators (shoulder development, pit depression, lenticel color, brix sweetness, specific gravity / flotation testing).
   • Pre-harvest care (irrigation cutoff 10-14 days prior to harvest, calcium foliar sprays, fruit bagging).
   • Post-harvest handling (pedicel clipping leaving 2-3cm stem, desapping racks to prevent sap burn, hot water immersion treatment 48°C for 15 minutes, ripening storage, cold chain 12-13°C).
   • Mango pests and disease identification & integrated pest management (oriental fruit fly Bactrocera dorsalis, anthracnose Colletotrichum gloeosporioides, stem-end rot, mango leafhopper, twig borer, powdery mildew, blossom blight, sooty mold).
   • MangoCount app features, optical reticle guidance, and calibration.

2. IDENTITY & GREETINGS:
   • If the user greets you (e.g. "hi", "hello", "good morning") or asks who you are / to tell about yourself (e.g. "tell me about yourself", "who are you", "what can you do"):
     - Warmly introduce yourself as the **MangoCount AI Agronomist**.
     - Clearly state your role: a dedicated AI pomology specialist developed to assist mango farmers, orchard managers, and field researchers in analyzing canopy scans, scheduling harvest timing, identifying pests/diseases, and maximizing fruit yield.
     - Outline the specific topics you can help with.
     - Invite the user to ask any question regarding their mango trees, fruit scans, or orchard health.

3. OUT-OF-SCOPE ENFORCEMENT (CRITICAL GUARDRAIL):
   • If the user asks ANY question outside of mango cultivation, fruit pomology, orchard management, agriculture, or the scan results (for example: coding, general software, computer science, math, world history, politics, entertainment, sports, medical advice for humans, general philosophy, unrelated food recipes, general chit-chat, etc.):
   • You MUST POLITELY DECLINE and refuse to answer the off-topic query.
   • Do NOT answer the off-topic question, not even partially.
   • Respond with the following exact structure:
     "🌾 **Domain Boundary Notice**
     I am specialized exclusively as the **MangoCount AI Agronomist**. I cannot provide assistance on topics outside of mango cultivation, fruit orchard management, or canopy scan analysis.

     Please feel free to ask about your mango yield, harvest windows, fruit ripeness stages, tree health, or pest and disease prevention!"
   • Always output 3 mango-related follow-up suggestions to guide the user back on track.

4. FORMATTING & SUGGESTIONS:
   • Format agronomic advice with clear markdown headings (###), bullet points (•), and bold keywords (**).
   • When scan telemetry is present, reference the actual detected counts and ripeness ratios.
   • At the very end of every reply, always output exactly one line starting with "SUGGESTIONS:" followed by 3 relevant in-scope follow-up questions separated by " | ".
   Example:
   SUGGESTIONS: When should I harvest the ripe fruit? | How can I prevent fruit drop on green mangoes? | How to protect fruits from oriental fruit fly?
''';

  /// Sends a multi-turn conversation to Google Gemini API or falls back to local knowledge.
  static Future<ChatMessage> sendMessage({
    required List<ChatMessage> conversationHistory,
    required String userPrompt,
    ScanChatContext? scanContext,
    String apiKey = '',
    String model = defaultModel,
  }) async {
    final effectiveKey = apiKey.trim().isNotEmpty
        ? apiKey.trim()
        : GeminiAssistantService.defaultApiKey;

    // If an API key is available, attempt Gemini API
    if (effectiveKey.isNotEmpty) {
      try {
        final responseText = await _callGeminiApi(
          conversationHistory: conversationHistory,
          userPrompt: userPrompt,
          scanContext: scanContext,
          apiKey: effectiveKey,
          model: model,
        );

        final parsed = _parseResponseWithSuggestions(responseText);

        return ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          role: ChatRole.assistant,
          text: parsed.text,
          timestamp: DateTime.now(),
          suggestedPrompts: parsed.suggestions,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[ChatService Primary Model Error]: $e. Attempting fallback model.');
        }

        // Try fallback model once if primary model failed
        if (model != fallbackModel) {
          try {
            final fallbackText = await _callGeminiApi(
              conversationHistory: conversationHistory,
              userPrompt: userPrompt,
              scanContext: scanContext,
              apiKey: effectiveKey,
              model: fallbackModel,
            );
            final parsed = _parseResponseWithSuggestions(fallbackText);
            return ChatMessage(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              role: ChatRole.assistant,
              text: parsed.text,
              timestamp: DateTime.now(),
              suggestedPrompts: parsed.suggestions,
            );
          } catch (e2) {
            if (kDebugMode) {
              debugPrint('[ChatService Fallback Model Error]: $e2.');
            }
          }
        }
      }
    }

    // Local rule-based & domain-guardrailed fallback engine
    return _generateOfflineFallback(
      userPrompt: userPrompt,
      scanContext: scanContext,
      isOffline: effectiveKey.isEmpty,
    );
  }

  static Future<String> _callGeminiApi({
    required List<ChatMessage> conversationHistory,
    required String userPrompt,
    ScanChatContext? scanContext,
    required String apiKey,
    required String model,
  }) async {
    final List<Map<String, dynamic>> contents = [];

    // Include scan telemetry context in initial exchange
    final bool isFirstTurn = conversationHistory.isEmpty;

    // Add prior conversation turns
    for (int i = 0; i < conversationHistory.length; i++) {
      final msg = conversationHistory[i];
      if (msg.isSystem) continue;

      final role = msg.isUser ? 'user' : 'model';
      final List<Map<String, dynamic>> parts = [];

      // If it's the first message and has an image, include it
      if (i == 0 && msg.imageBytes != null && msg.imageBytes!.isNotEmpty) {
        final compressed = _compressForApi(msg.imageBytes!);
        if (compressed != null) {
          parts.add({
            'inline_data': {
              'mime_type': 'image/jpeg',
              'data': base64Encode(compressed),
            }
          });
        }
      }

      parts.add({'text': msg.text});
      contents.add({'role': role, 'parts': parts});
    }

    // Add current user prompt
    final List<Map<String, dynamic>> currentParts = [];

    // If first turn and scanContext has image, attach it
    if (isFirstTurn && scanContext?.imageBytes != null) {
      final compressed = _compressForApi(scanContext!.imageBytes!);
      if (compressed != null) {
        currentParts.add({
          'inline_data': {
            'mime_type': 'image/jpeg',
            'data': base64Encode(compressed),
          }
        });
      }
    }

    // Inject scan telemetry preamble if present
    String promptWithContext = userPrompt;
    if (isFirstTurn && scanContext != null) {
      promptWithContext = '''
${scanContext.toSummaryPrompt()}

Field User Inquiry:
$userPrompt
''';
    }

    currentParts.add({'text': promptWithContext});
    contents.add({'role': 'user', 'parts': currentParts});

    final requestBody = jsonEncode({
      'system_instruction': {
        'parts': [
          {'text': systemInstruction}
        ]
      },
      'contents': contents,
      'generationConfig': {
        'temperature': 0.2,
        'maxOutputTokens': 1200,
      }
    });

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
    );

    final response = await http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: requestBody,
        )
        .timeout(timeoutDuration);

    if (response.statusCode != 200) {
      throw Exception('Gemini API HTTP ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body);
    final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
    if (text == null || text.trim().isEmpty) {
      throw Exception('Empty content returned by Gemini API');
    }

    return text.trim();
  }

  static Uint8List? _compressForApi(Uint8List original) {
    try {
      final decoded = img.decodeImage(original);
      if (decoded == null) return original;

      img.Image resized = decoded;
      if (decoded.width > 960 || decoded.height > 960) {
        resized = img.copyResize(
          decoded,
          width: decoded.width > decoded.height ? 960 : null,
          height: decoded.height >= decoded.width ? 960 : null,
        );
      }
      return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
    } catch (_) {
      return original;
    }
  }

  static ({String text, List<String> suggestions}) _parseResponseWithSuggestions(String raw) {
    final lines = raw.split('\n');
    final List<String> bodyLines = [];
    final List<String> suggestions = [];

    for (final line in lines) {
      if (line.trim().startsWith('SUGGESTIONS:')) {
        final rawSuggestions = line.trim().substring('SUGGESTIONS:'.length).trim();
        final parts = rawSuggestions.split('|');
        for (final p in parts) {
          final trimmed = p.trim();
          if (trimmed.isNotEmpty) {
            suggestions.add(trimmed);
          }
        }
      } else {
        bodyLines.add(line);
      }
    }

    // Default suggestions if none were parsed
    if (suggestions.isEmpty) {
      suggestions.addAll([
        'When is the optimal harvest window?',
        'How can I prevent fruit fly infestation?',
        'What fertilizer helps fruit sizing right now?',
      ]);
    }

    return (text: bodyLines.join('\n').trim(), suggestions: suggestions);
  }

  /// Intelligent domain-specific agronomist fallback with strict boundary enforcement
  static ChatMessage _generateOfflineFallback({
    required String userPrompt,
    ScanChatContext? scanContext,
    required bool isOffline,
  }) {
    final lower = userPrompt.toLowerCase().trim();
    final buffer = StringBuffer();
    List<String> suggestions = [];

    final total = scanContext?.totalCount ?? 0;
    final ripe = scanContext?.ripeCount ?? 0;
    final unripe = scanContext?.unripeCount ?? 0;
    final overRipe = scanContext?.overRipeCount ?? 0;

    // 1. Identity & Greeting Inquiries
    final bool isGreetingOrIdentity = lower.contains('who are you') ||
        lower.contains('tell me about yourself') ||
        lower.contains('about yourself') ||
        lower.contains('what are you') ||
        lower.contains('what can you do') ||
        lower.contains('introduce yourself') ||
        lower.contains('what do you do') ||
        lower.contains('help me') ||
        lower == 'hi' ||
        lower == 'hello' ||
        lower == 'hey' ||
        lower.startsWith('hi ') ||
        lower.startsWith('hello ') ||
        lower.startsWith('hey ');

    if (isGreetingOrIdentity) {
      buffer.writeln('### 👋 Hello! I am your MangoCount AI Agronomist');
      buffer.writeln('');
      buffer.writeln('I am a specialized **AI Pomology & Orchard Management Consultant** designed specifically for mango farmers, field agronomists, and orchard researchers.');
      buffer.writeln('');
      buffer.writeln('**What I am trained to assist you with:**');
      buffer.writeln('• **Canopy Scan Analysis:** Review fruit counts, yield density, and ripeness stages (Ripe, Unripe, Over-ripe).');
      buffer.writeln('• **Harvest Scheduling:** Optimal picking windows and maturity indicators (shoulder fullness, brix sweetness, lenticels).');
      buffer.writeln('• **Pest & Disease Control:** Integrated pest management for oriental fruit flies (*Bactrocera dorsalis*), anthracnose, and stem-end rot.');
      buffer.writeln('• **Tree Nutrition & Pruning:** Fertilizer schedules (potassium nitrate KNO3, calcium), irrigation cutoff, and canopy aeration.');
      buffer.writeln('• **Post-Harvest Handling:** Proper desapping racks, sap burn prevention, and hot water immersion treatment.');
      buffer.writeln('');
      buffer.writeln('Ask me any question regarding your mango trees, fruit maturity, or orchard health!');

      suggestions = [
        'When is the optimal harvest window?',
        'How to protect fruit from oriental fruit flies?',
        'What fertilizer boosts mango sweetness?',
      ];

      return ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: ChatRole.assistant,
        text: buffer.toString().trim(),
        timestamp: DateTime.now(),
        suggestedPrompts: suggestions,
      );
    }

    // 2. Clear Out-of-Scope Flags (CS / coding, math, general trivia, politics, sports)
    const outOfScopeFlags = [
      'python', 'java', 'javascript', 'c++', 'code', 'coding', 'binary',
      'algorithm', 'program', 'html', 'css', 'sql', 'database', 'math',
      'president', 'championship', 'world cup', 'movie', 'actor', 'song',
      'music', 'bitcoin', 'crypto', 'stock market', 'quantum', 'physics',
      'calculate', 'recipe for pizza', 'translate', 'essay',
    ];

    final bool hasExplicitOutFlag = outOfScopeFlags.any((flag) => lower.contains(flag));

    // 3. Specific In-Scope Agronomy Keywords
    const specificAgronomyKeywords = [
      'mango', 'fruit', 'harvest', 'pick', 'ripe', 'unripe', 'overripe',
      'orchard', 'canopy', 'pest', 'disease', 'fly', 'flies', 'bactrocera',
      'insect', 'anthracnose', 'rot', 'spot', 'fertiliz', 'water', 'irrigat',
      'potassium', 'calcium', 'kno3', 'prun', 'flower', 'flush', 'carabao',
      'yield', 'scan', 'reticle', 'post-harvest', 'desap', 'sap', 'soil',
      'sunburn', 'brix', 'variety', 'pomology', 'agronomy', 'seed', 'peel',
      'fungicide', 'pesticide', 'bagging', 'hopper', 'borer', 'mildew',
      'foliage', 'crop', 'plant', 'nitrogen', 'phosphorus', 'root', 'tommy',
      'kensington', 'keitt', 'kent', 'alphonso', 'nam dok', 'haden',
      'mango tree', 'fruit tree',
    ];

    final bool hasSpecificAgronomyKeyword = specificAgronomyKeywords.any((kw) => lower.contains(kw));

    final bool isQueryInScope = (scanContext != null || hasSpecificAgronomyKeyword) && !hasExplicitOutFlag;

    // 4. Out-Of-Scope Guardrail Response
    if (!isQueryInScope) {
      buffer.writeln('### 🌾 Domain Boundary Notice');
      buffer.writeln('');
      buffer.writeln('I am specialized exclusively as the **MangoCount AI Agronomist**. I cannot provide assistance on topics outside of mango cultivation, fruit orchard management, or canopy scan analysis.');
      buffer.writeln('');
      buffer.writeln('**Please feel free to ask about:**');
      buffer.writeln('• When to harvest your current mango crop');
      buffer.writeln('• Days until green mangoes reach harvest maturity');
      buffer.writeln('• Protecting fruit from oriental fruit flies and anthracnose');
      buffer.writeln('• Pre-harvest irrigation cutoff and fertilizer schedules');
      buffer.writeln('• Post-harvest desapping and hot water treatment');

      suggestions = [
        'When should I harvest ripe mangoes?',
        'How do I protect green fruit from pests?',
        'What fertilizer improves fruit sizing?',
      ];

      return ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: ChatRole.assistant,
        text: buffer.toString().trim(),
        timestamp: DateTime.now(),
        suggestedPrompts: suggestions,
      );
    }

    // 5. In-Scope Agronomy Guidance Generation
    buffer.writeln('### 🌾 AI Agronomist Field Analysis');
    if (isOffline) {
      buffer.writeln('> *Running in Offline Field Mode. Telemetry-based recommendations are active.*');
      buffer.writeln('');
    }

    if (scanContext != null) {
      buffer.writeln('**Canopy Audit Summary:**');
      buffer.writeln('• **Total Detected:** $total fruits');
      buffer.writeln('• **Harvest-Ready (Ripe):** $ripe (${total > 0 ? ((ripe / total) * 100).toStringAsFixed(0) : 0}%)');
      buffer.writeln('• **Maturing Green (Unripe):** $unripe (${total > 0 ? ((unripe / total) * 100).toStringAsFixed(0) : 0}%)');
      if (overRipe > 0) {
        buffer.writeln('• ⚠️ **Over-Ripe Warning:** $overRipe fruit(s) require immediate removal to prevent fruit fly infestation.');
      }
      buffer.writeln('');
    }

    if (lower.contains('harvest') || lower.contains('pick') || lower.contains('ready') || lower.contains('when') || lower.contains('date')) {
      buffer.writeln('### 🧺 Harvest Window Recommendations');
      if (ripe > 0) {
        buffer.writeln('• **Immediate Action:** The **$ripe ripe mangoes** should be picked within 24–48 hours to minimize bird pecking, fruit fly stings, and sunburn.');
      }
      if (unripe > 0) {
        buffer.writeln('• **Green Batch Timing:** The **$unripe green mangoes** appear to be in mid-to-late development. Monitor shoulder fullness and lenticel color (turning white/cream). Typical maturity window is **7 to 14 days** away.');
      }
      buffer.writeln('• **Harvest Technique:** Use telescopic pole clippers with catching nets. Clip stems leaving **2–3 cm pedicel** to prevent latex/sap burn on the fruit surface.');
      buffer.writeln('• **Desapping:** Invert picked fruits on desapping racks for 20 minutes to allow caustic latex to drain away safely.');

      suggestions = [
        'How do I handle desapping after picking?',
        'What is the flotation test for maturity?',
        'How to store green mangoes for uniform ripening?',
      ];
    } else if (lower.contains('pest') || lower.contains('disease') || lower.contains('fly') || lower.contains('insect') || lower.contains('spot') || lower.contains('rot') || lower.contains('anthracnose')) {
      buffer.writeln('### 🛡️ Pest & Disease Protection Plan');
      buffer.writeln('• **Oriental Fruit Fly (*Bactrocera dorsalis*):** Install methyl eugenol pheromone traps around tree perimeters (4 traps/hectare). Consider bagging individual fruit clusters with breathable double-layered paper bags 30 days before harvest.');
      buffer.writeln('• **Anthracnose (*Colletotrichum gloeosporioides*):** Ensure canopy airflow through selective pruning. If rain is expected, apply copper fungicide or azoxystrobin spray.');
      buffer.writeln('• **Stem-End Rot Prevention:** Post-harvest hot water immersion treatment (**48°C for 15 minutes**) eliminates latent fungal pathogens without chemical residues.');

      suggestions = [
        'What is the best fruit bagging material?',
        'How to prepare hot water treatment for anthracnose?',
        'How to control mango leafhoppers?',
      ];
    } else if (lower.contains('fertiliz') || lower.contains('water') || lower.contains('nutrition') || lower.contains('potassium') || lower.contains('kno3') || lower.contains('calcium')) {
      buffer.writeln('### 💧 Nutrition & Irrigation Guidance');
      buffer.writeln('• **Late Stage Sizing:** Apply Potassium Sulfate (0-0-50) or foliar potassium nitrate (KNO3) at 1–2% concentration to boost brix sweetness and uniform fruit expansion.');
      buffer.writeln('• **Irrigation Cutoff:** Reduce deep watering **10 to 14 days prior to target harvest**. This concentrates fruit sugars, improves shelf life, and prevents water-core splitting.');
      buffer.writeln('• **Calcium Foliar Spray:** Apply chelated calcium to strengthen cell walls, significantly reducing internal fruit breakdown.');

      suggestions = [
        'When should I stop watering before harvest?',
        'What foliar spray boosts mango sweetness?',
        'How much potassium nitrate for flower induction?',
      ];
    } else if (lower.contains('prun') || lower.contains('flower') || lower.contains('canopy') || lower.contains('variety')) {
      buffer.writeln('### 🌿 Canopy Management & Varietal Advice');
      buffer.writeln('• **Post-Harvest Pruning:** Open the tree center ("cup" shape) by removing water sprouts and dead twigs to allow sunlight penetration for next season\'s fruit wood.');
      buffer.writeln('• **Flowering Induction:** For varieties like Carabao, potassium nitrate foliar spray is typically applied 7.5–9 months after previous harvest when leaves are mature and dark green.');
      buffer.writeln('• **Canopy Aeration:** Good wind circulation reduces relative humidity within the foliage, keeping fungal spores from germinating on delicate flower panicles.');

      suggestions = [
        'How to prune after mango harvest?',
        'What leaf maturity is required for flower induction?',
        'Characteristics of Carabao vs Tommy Atkins?',
      ];
    } else {
      buffer.writeln('### 🌿 General Canopy & Orchard Assessment');
      buffer.writeln('• **Ripeness Uniformity:** Your canopy shows a healthy mix of developing and maturing fruit. Selective multiple-pass picking is recommended over single stripping.');
      buffer.writeln('• **Sun Exposure:** Ensure inner canopy branches receive dappled sunlight by light post-harvest pruning of water sprouts.');
      buffer.writeln('• **Yield Potential:** Based on current fruit density, healthy leaf retention indicates strong photosynthetic support for final fruit filling.');

      suggestions = [
        'When is the optimal harvest window?',
        'How to protect maturing fruit from fruit flies?',
        'What fertilizer helps fruit sizing right now?',
      ];
    }

    return ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: ChatRole.assistant,
      text: buffer.toString().trim(),
      timestamp: DateTime.now(),
      suggestedPrompts: suggestions.take(3).toList(),
    );
  }
}
