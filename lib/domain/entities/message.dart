import 'package:equatable/equatable.dart';

/// Represents a single message in a conversation.
/// 
/// Messages are immutable value objects. They represent both user input
/// and assistant responses. The [role] field distinguishes between them.
/// 
/// Design Decision: We store both the original text and optional translation
/// to support the multilingual review feature without re-translating.
class Message extends Equatable {
  /// Unique identifier for this message.
  final String id;
  
  /// The message content.
  final String content;
  
  /// Who sent this message.
  final MessageRole role;
  
  /// When the message was created.
  final DateTime timestamp;
  
  /// Original language of the message (ISO 639-1 code).
  final String? language;
  
  /// Optional translation of the message.
  final String? translation;
  
  /// Language the translation is in.
  final String? translationLanguage;
  
  /// Token count for this message (for context window management).
  final int? tokenCount;
  
  /// Whether this message is currently being streamed.
  final bool isStreaming;
  
  /// Any metadata associated with this message.
  final Map<String, dynamic>? metadata;
  
  const Message({
    required this.id,
    required this.content,
    required this.role,
    required this.timestamp,
    this.language,
    this.translation,
    this.translationLanguage,
    this.tokenCount,
    this.isStreaming = false,
    this.metadata,
  });
  
  /// Create a new user message.
  factory Message.user({
    required String id,
    required String content,
    String? language,
  }) {
    return Message(
      id: id,
      content: content,
      role: MessageRole.user,
      timestamp: DateTime.now(),
      language: language,
    );
  }
  
  /// Create a new assistant message.
  factory Message.assistant({
    required String id,
    required String content,
    bool isStreaming = false,
    int? tokenCount,
  }) {
    return Message(
      id: id,
      content: content,
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
      isStreaming: isStreaming,
      tokenCount: tokenCount,
    );
  }
  
  /// Create a system message (for prompt engineering, not shown to user).
  factory Message.system({
    required String id,
    required String content,
  }) {
    return Message(
      id: id,
      content: content,
      role: MessageRole.system,
      timestamp: DateTime.now(),
    );
  }
  
  /// Create a copy with updated fields.
  Message copyWith({
    String? id,
    String? content,
    MessageRole? role,
    DateTime? timestamp,
    String? language,
    String? translation,
    String? translationLanguage,
    int? tokenCount,
    bool? isStreaming,
    Map<String, dynamic>? metadata,
  }) {
    return Message(
      id: id ?? this.id,
      content: content ?? this.content,
      role: role ?? this.role,
      timestamp: timestamp ?? this.timestamp,
      language: language ?? this.language,
      translation: translation ?? this.translation,
      translationLanguage: translationLanguage ?? this.translationLanguage,
      tokenCount: tokenCount ?? this.tokenCount,
      isStreaming: isStreaming ?? this.isStreaming,
      metadata: metadata ?? this.metadata,
    );
  }
  
  /// Append content to an existing message (for streaming).
  Message appendContent(String additionalContent) {
    return copyWith(content: content + additionalContent);
  }
  
  /// Mark streaming as complete.
  Message completeStreaming({int? finalTokenCount}) {
    return copyWith(
      isStreaming: false,
      tokenCount: finalTokenCount,
    );
  }
  
  /// Add translation to message.
  Message withTranslation(String translatedContent, String targetLanguage) {
    return copyWith(
      translation: translatedContent,
      translationLanguage: targetLanguage,
    );
  }
  
  @override
  List<Object?> get props => [
    id,
    content,
    role,
    timestamp,
    language,
    translation,
    translationLanguage,
    tokenCount,
    isStreaming,
  ];
  
  @override
  String toString() => 'Message(id: $id, role: $role, content: ${content.length > 50 ? '${content.substring(0, 50)}...' : content})';
}

/// Role of the message sender.
enum MessageRole {
  /// Message from the user.
  user,
  
  /// Message from the assistant (LLM).
  assistant,
  
  /// System message (for prompts, not displayed).
  system,
}

/// Extension for MessageRole string conversion.
extension MessageRoleExtension on MessageRole {
  String get displayName {
    switch (this) {
      case MessageRole.user:
        return 'You';
      case MessageRole.assistant:
        return 'Assistant';
      case MessageRole.system:
        return 'System';
    }
  }
  
  /// Convert to prompt format string.
  String get promptPrefix {
    switch (this) {
      case MessageRole.user:
        return 'User: ';
      case MessageRole.assistant:
        return 'Assistant: ';
      case MessageRole.system:
        return '';
    }
  }
}
