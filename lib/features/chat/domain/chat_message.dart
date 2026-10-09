import 'dart:typed_data';

enum ChatRole {
  user,
  assistant,
  system,
}

class ChatMessage {
  final String id;
  final ChatRole role;
  final String text;
  final DateTime timestamp;
  final Uint8List? imageBytes;
  final List<String> suggestedPrompts;
  final bool isError;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
    this.imageBytes,
    this.suggestedPrompts = const [],
    this.isError = false,
  });

  bool get isUser => role == ChatRole.user;
  bool get isAssistant => role == ChatRole.assistant;
  bool get isSystem => role == ChatRole.system;

  ChatMessage copyWith({
    String? id,
    ChatRole? role,
    String? text,
    DateTime? timestamp,
    Uint8List? imageBytes,
    List<String>? suggestedPrompts,
    bool? isError,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      imageBytes: imageBytes ?? this.imageBytes,
      suggestedPrompts: suggestedPrompts ?? this.suggestedPrompts,
      isError: isError ?? this.isError,
    );
  }
}
