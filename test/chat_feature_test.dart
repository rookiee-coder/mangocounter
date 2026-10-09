import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mangocounter/features/chat/domain/chat_message.dart';
import 'package:mangocounter/features/chat/domain/scan_chat_context.dart';
import 'package:mangocounter/features/chat/application/chat_controller.dart';
import 'package:mangocounter/features/chat/data/chat_service.dart';

void main() {
  group('ScanChatContext domain tests', () {
    test('Formats summary prompt accurately with all telemetry', () {
      final ctx = ScanChatContext(
        imageBytes: Uint8List(10),
        originalPath: '/test/image.jpg',
        totalCount: 15,
        ripeCount: 8,
        unripeCount: 5,
        overRipeCount: 2,
        inferenceMs: 142,
        confThreshold: 0.25,
        aiVerifiedCount: 7,
        userEditedCount: 1,
        actualCount: 16,
      );

      final summary = ctx.toSummaryPrompt();
      expect(summary, contains('Total visible mangoes detected: 15'));
      expect(summary, contains('Ripe (Harvest ready): 8'));
      expect(summary, contains('Unripe (Developing green): 5'));
      expect(summary, contains('Over-ripe (Late stage): 2'));
      expect(summary, contains('AI Verified fruits: 7'));
      expect(summary, contains('Field user manually placed boxes: 1'));
      expect(summary, contains('Ground truth manual count: 16'));
      expect(summary, contains('142ms'));
      expect(summary, contains('25%'));
    });
  });

  group('ChatMessage domain tests', () {
    test('Role helpers and properties operate correctly', () {
      final userMsg = ChatMessage(
        id: 'msg-1',
        role: ChatRole.user,
        text: 'When should I harvest?',
        timestamp: DateTime.now(),
      );
      expect(userMsg.isUser, isTrue);
      expect(userMsg.isAssistant, isFalse);

      final assistantMsg = userMsg.copyWith(
        id: 'msg-2',
        role: ChatRole.assistant,
        text: 'Harvest in 2 days.',
        suggestedPrompts: ['How to desap?'],
      );
      expect(assistantMsg.isAssistant, isTrue);
      expect(assistantMsg.suggestedPrompts, contains('How to desap?'));
    });
  });

  group('ChatController StateNotifier tests', () {
    test('Initializes with scan context and generates tailored welcome message and follow-up prompts', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);
      const ctx = ScanChatContext(
        totalCount: 12,
        ripeCount: 7,
        unripeCount: 4,
        overRipeCount: 1,
      );

      controller.initSession(scanContext: ctx);

      final state = container.read(chatControllerProvider);
      expect(state.messages.length, 1);
      expect(state.messages.first.role, ChatRole.assistant);
      expect(state.messages.first.text, contains('12 visible mangoes'));
      expect(state.messages.first.text, contains('7 harvest-ready'));
      expect(state.messages.first.text, contains('4 developing green'));
      expect(state.suggestedPrompts, isNotEmpty);
      expect(state.suggestedPrompts.any((p) => p.contains('ready for harvest')), isTrue);
    });

    test('Initializes without scan context and provides general pomology suggestions', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider.notifier);
      controller.initSession(scanContext: null);

      final state = container.read(chatControllerProvider);
      expect(state.messages.length, 1);
      expect(state.messages.first.text, contains('MangoCount AI Agronomist'));
      expect(state.suggestedPrompts.any((p) => p.contains('Carabao')), isTrue);
    });
  });

  group('AI Chatbot Scope & Domain Boundary Tests', () {
    test('User greeting or identity query ("hi tell me about yourselfd") correctly introduces Agronomist persona', () async {
      final response = await ChatService.sendMessage(
        conversationHistory: [],
        userPrompt: 'hi tell me about yourselfd',
      );

      expect(response.role, ChatRole.assistant);
      expect(response.text, contains('MangoCount AI Agronomist'));
      expect(response.text.toLowerCase(), contains('pomolog'));
      expect(response.suggestedPrompts, isNotEmpty);
    });

    test('Out-of-scope query triggers strict Domain Boundary Notice', () async {
      final response = await ChatService.sendMessage(
        conversationHistory: [],
        userPrompt: 'Can you write python code for a binary search tree?',
      );

      expect(response.role, ChatRole.assistant);
      expect(response.text, contains('Domain Boundary Notice'));
      expect(response.text, contains('MangoCount AI Agronomist'));
      expect(response.suggestedPrompts, isNotEmpty);
    });

    test('In-scope query about pests and fruit flies produces pest protection plan', () async {
      final response = await ChatService.sendMessage(
        conversationHistory: [],
        userPrompt: 'How can I prevent oriental fruit fly stings on my mangoes?',
      );

      expect(response.role, ChatRole.assistant);
      expect(response.text.toLowerCase(), contains('fruit fly'));
      expect(response.text, contains('Bactrocera dorsalis'));
    });
  });
}
