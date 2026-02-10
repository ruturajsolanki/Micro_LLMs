part of 'chat_bloc.dart';

/// Base class for chat events.
sealed class ChatEvent extends Equatable {
  const ChatEvent();
  
  @override
  List<Object?> get props => [];
}

/// Initialize the chat with language settings.
final class ChatStarted extends ChatEvent {
  final String sourceLanguage;
  final String targetLanguage;
  
  const ChatStarted({
    required this.sourceLanguage,
    required this.targetLanguage,
  });
  
  @override
  List<Object> get props => [sourceLanguage, targetLanguage];
}

/// Update the active conversation language settings.
///
/// Why:
/// - The user can change languages from Settings while the chat is open.
/// - We must update both the Dart-side `Conversation` metadata AND the native
///   incremental prompt buffer (ChatML system prompt language constraint).
final class ChatLanguagesUpdated extends ChatEvent {
  final String sourceLanguage;
  final String targetLanguage;

  const ChatLanguagesUpdated({
    required this.sourceLanguage,
    required this.targetLanguage,
  });

  @override
  List<Object> get props => [sourceLanguage, targetLanguage];
}

/// Load a previous conversation from history.
final class ChatConversationSelected extends ChatEvent {
  final String conversationId;

  const ChatConversationSelected({required this.conversationId});

  @override
  List<Object> get props => [conversationId];
}

/// Start a fresh chat session, while keeping the current one in history.
final class ChatNewConversationRequested extends ChatEvent {
  const ChatNewConversationRequested();
}

/// User sent a message.
final class ChatMessageSent extends ChatEvent {
  final String content;
  final double? temperature;
  
  const ChatMessageSent({
    required this.content,
    this.temperature,
  });
  
  @override
  List<Object?> get props => [content, temperature];
}

/// Received a token from the LLM during streaming.
final class ChatResponseTokenReceived extends ChatEvent {
  final String token;
  final int tokenCount;
  
  const ChatResponseTokenReceived({
    required this.token,
    required this.tokenCount,
  });
  
  @override
  List<Object> get props => [token, tokenCount];
}

/// LLM generation completed.
final class ChatResponseCompleted extends ChatEvent {
  final int tokenCount;
  final int durationMs;
  
  const ChatResponseCompleted({
    required this.tokenCount,
    required this.durationMs,
  });
  
  @override
  List<Object> get props => [tokenCount, durationMs];
}

/// LLM generation failed.
final class ChatResponseFailed extends ChatEvent {
  final String error;
  
  const ChatResponseFailed({required this.error});
  
  @override
  List<Object> get props => [error];
}

/// User cancelled generation.
final class ChatGenerationCancelled extends ChatEvent {
  const ChatGenerationCancelled();
}

/// Request translation for a message.
final class ChatTranslationRequested extends ChatEvent {
  final String messageId;
  
  const ChatTranslationRequested({required this.messageId});
  
  @override
  List<Object> get props => [messageId];
}

/// Clear the conversation.
final class ChatConversationCleared extends ChatEvent {
  const ChatConversationCleared();
}

/// Delete a specific message.
final class ChatMessageDeleted extends ChatEvent {
  final String messageId;
  
  const ChatMessageDeleted({required this.messageId});
  
  @override
  List<Object> get props => [messageId];
}
