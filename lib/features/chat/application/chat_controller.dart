import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/chat_message.dart';
import '../domain/scan_chat_context.dart';
import '../data/chat_service.dart';
import '../../settings/application/settings_controller.dart';

class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final ScanChatContext? scanContext;
  final List<String> suggestedPrompts;
  final String? errorMessage;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.scanContext,
    this.suggestedPrompts = const [],
    this.errorMessage,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    ScanChatContext? scanContext,
    List<String>? suggestedPrompts,
    String? errorMessage,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      scanContext: scanContext ?? this.scanContext,
      suggestedPrompts: suggestedPrompts ?? this.suggestedPrompts,
      errorMessage: errorMessage,
    );
  }
}

class ChatController extends StateNotifier<ChatState> {
  final Ref ref;

  ChatController(this.ref) : super(const ChatState());

  /// Sets up a new chat session, optionally bound to an optical scan result.
  void initSession({ScanChatContext? scanContext, String? initialQuestion}) {
    final List<ChatMessage> initialMessages = [];
    final List<String> initialSuggestions = [];

    if (scanContext != null) {
      final total = scanContext.totalCount;
      final ripe = scanContext.ripeCount;
      final unripe = scanContext.unripeCount;
      final over = scanContext.overRipeCount;

      initialSuggestions.addAll([
        if (ripe > 0) 'Are the $ripe ripe mangoes ready for harvest?',
        if (unripe > 0) 'How many days until the $unripe green mangoes ripen?',
        if (over > 0) 'What should I do with the $over over-ripe fruit?',
        'How can I protect this canopy from fruit flies?',
        'What fertilizer maximizes fruit sweetness right now?',
      ]);

      final buffer = StringBuffer();
      buffer.writeln('👋 Hello! I am your **MangoCount AI Agronomist**.');
      buffer.writeln('');
      buffer.writeln('I have reviewed your orchard canopy scan:');
      buffer.writeln('• **Total Fruit:** $total visible mangoes');
      buffer.writeln('• **Ripe:** $ripe harvest-ready');
      buffer.writeln('• **Unripe:** $unripe developing green');
      if (over > 0) {
        buffer.writeln('• **Over-Ripe:** $over past peak maturity');
      }
      buffer.writeln('');
      buffer.writeln('Ask me anything about harvest scheduling, ripening stages, fruit protection, or tree health! Tap a prompt below or type your question:');

      initialMessages.add(
        ChatMessage(
          id: 'welcome-${DateTime.now().millisecondsSinceEpoch}',
          role: ChatRole.assistant,
          text: buffer.toString().trim(),
          timestamp: DateTime.now(),
          suggestedPrompts: initialSuggestions,
        ),
      );
    } else {
      initialSuggestions.addAll([
        'How do I know when Carabao mangoes are mature?',
        'Best fertilizer schedule for mango trees',
        'How to prevent anthracnose fungal spots?',
        'Tips to induce uniform mango flowering',
      ]);

      initialMessages.add(
        ChatMessage(
          id: 'welcome-general',
          role: ChatRole.assistant,
          text: '👋 Hello! I am your **MangoCount AI Agronomist**.\n\nAsk me anything about mango cultivation, variety characteristics, flowering induction, pest management, or harvest timing. How can I assist your orchard today?',
          timestamp: DateTime.now(),
          suggestedPrompts: initialSuggestions,
        ),
      );
    }

    state = ChatState(
      messages: initialMessages,
      scanContext: scanContext,
      suggestedPrompts: initialSuggestions,
      isLoading: false,
    );

    if (initialQuestion != null && initialQuestion.trim().isNotEmpty) {
      sendMessage(initialQuestion.trim());
    }
  }

  /// Sends a user question and gets the agronomist response.
  Future<void> sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty) return;

    final userMsg = ChatMessage(
      id: 'user-${DateTime.now().millisecondsSinceEpoch}',
      role: ChatRole.user,
      text: query,
      timestamp: DateTime.now(),
    );

    final updatedMessages = [...state.messages, userMsg];
    state = state.copyWith(
      messages: updatedMessages,
      isLoading: true,
      errorMessage: null,
      suggestedPrompts: [],
    );

    final settings = ref.read(settingsProvider);

    try {
      final assistantMsg = await ChatService.sendMessage(
        conversationHistory: updatedMessages,
        userPrompt: query,
        scanContext: state.scanContext,
        apiKey: settings.geminiApiKey,
      );

      state = state.copyWith(
        messages: [...updatedMessages, assistantMsg],
        isLoading: false,
        suggestedPrompts: assistantMsg.suggestedPrompts,
      );
    } catch (e) {
      final errorMsg = ChatMessage(
        id: 'error-${DateTime.now().millisecondsSinceEpoch}',
        role: ChatRole.assistant,
        text: '⚠️ I encountered an unexpected error processing your inquiry: $e. Please verify network connectivity or check your Gemini API key in Settings.',
        timestamp: DateTime.now(),
        isError: true,
      );

      state = state.copyWith(
        messages: [...updatedMessages, errorMsg],
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  void clearChat() {
    initSession(scanContext: state.scanContext);
  }
}

final chatControllerProvider = StateNotifierProvider<ChatController, ChatState>((ref) {
  return ChatController(ref);
});
