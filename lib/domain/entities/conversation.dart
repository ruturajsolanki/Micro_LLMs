import 'package:equatable/equatable.dart';
import 'message.dart';

/// Represents a conversation session with the assistant.
/// 
/// A conversation maintains the full message history and metadata
/// needed for context management and persistence.
class Conversation extends Equatable {
  /// Unique identifier for this conversation.
  final String id;
  
  /// Human-readable title (auto-generated or user-set).
  final String title;
  
  /// All messages in chronological order.
  final List<Message> messages;
  
  /// When the conversation was created.
  final DateTime createdAt;
  
  /// When the conversation was last updated.
  final DateTime updatedAt;
  
  /// Primary language of this conversation.
  final String primaryLanguage;
  
  /// Target language for translations.
  final String targetLanguage;
  
  /// Total token count for context window management.
  final int totalTokenCount;
  
  /// Whether this conversation is currently active.
  final bool isActive;
  
  const Conversation({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
    required this.primaryLanguage,
    required this.targetLanguage,
    this.totalTokenCount = 0,
    this.isActive = true,
  });
  
  /// Create a new empty conversation.
  factory Conversation.create({
    required String id,
    String title = 'New Conversation',
    String primaryLanguage = 'en',
    String targetLanguage = 'es',
  }) {
    final now = DateTime.now();
    return Conversation(
      id: id,
      title: title,
      messages: const [],
      createdAt: now,
      updatedAt: now,
      primaryLanguage: primaryLanguage,
      targetLanguage: targetLanguage,
    );
  }
  
  /// Create a copy with updated fields.
  Conversation copyWith({
    String? id,
    String? title,
    List<Message>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? primaryLanguage,
    String? targetLanguage,
    int? totalTokenCount,
    bool? isActive,
  }) {
    return Conversation(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      primaryLanguage: primaryLanguage ?? this.primaryLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      totalTokenCount: totalTokenCount ?? this.totalTokenCount,
      isActive: isActive ?? this.isActive,
    );
  }
  
  /// Add a message to the conversation.
  Conversation addMessage(Message message) {
    return copyWith(
      messages: [...messages, message],
      totalTokenCount: totalTokenCount + (message.tokenCount ?? 0),
    );
  }
  
  /// Update the last message (for streaming).
  Conversation updateLastMessage(Message updatedMessage) {
    if (messages.isEmpty) {
      return addMessage(updatedMessage);
    }
    
    final updatedMessages = List<Message>.from(messages);
    updatedMessages[updatedMessages.length - 1] = updatedMessage;
    
    return copyWith(messages: updatedMessages);
  }
  
  /// Get messages formatted for the LLM prompt.
  /// 
  /// This method handles context window limits by truncating old messages
  /// while preserving the system prompt and recent context.
  List<Message> getContextMessages({
    required int maxTokens,
    Message? systemMessage,
  }) {
    final result = <Message>[];
    int tokenCount = systemMessage?.tokenCount ?? 0;
    
    // Always include system message if present
    if (systemMessage != null) {
      result.add(systemMessage);
    }
    
    // Add messages from newest to oldest until we hit the limit
    for (int i = messages.length - 1; i >= 0; i--) {
      final message = messages[i];
      final messageTokens = message.tokenCount ?? _estimateTokens(message.content);
      
      if (tokenCount + messageTokens > maxTokens) {
        break; // Stop adding messages
      }
      
      result.insert(systemMessage != null ? 1 : 0, message);
      tokenCount += messageTokens;
    }
    
    return result;
  }
  
  /// Rough token estimation when actual count is unavailable.
  /// Uses the approximation of ~4 characters per token for English.
  int _estimateTokens(String text) {
    return (text.length / 4).ceil();
  }
  
  /// Get only user messages.
  List<Message> get userMessages =>
      messages.where((m) => m.role == MessageRole.user).toList();
  
  /// Get only assistant messages.
  List<Message> get assistantMessages =>
      messages.where((m) => m.role == MessageRole.assistant).toList();
  
  /// Get the last message.
  Message? get lastMessage => messages.isNotEmpty ? messages.last : null;
  
  /// Get the last user message.
  Message? get lastUserMessage {
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == MessageRole.user) {
        return messages[i];
      }
    }
    return null;
  }
  
  /// Whether the conversation has any messages.
  bool get isEmpty => messages.isEmpty;
  
  /// Whether the conversation has messages.
  bool get isNotEmpty => messages.isNotEmpty;
  
  /// Number of messages in the conversation.
  int get messageCount => messages.length;
  
  /// Generate a title from the first user message.
  String generateTitle() {
    Message? firstUserMessage;
    try {
      firstUserMessage = messages.firstWhere(
        (m) => m.role == MessageRole.user,
      );
    } catch (_) {
      firstUserMessage = null;
    }
    
    if (firstUserMessage == null) {
      return 'New Conversation';
    }
    
    final content = firstUserMessage.content;
    if (content.length <= 30) {
      return content;
    }
    return '${content.substring(0, 30)}...';
  }
  
  @override
  List<Object?> get props => [
    id,
    title,
    messages,
    createdAt,
    updatedAt,
    primaryLanguage,
    targetLanguage,
    totalTokenCount,
    isActive,
  ];
}
