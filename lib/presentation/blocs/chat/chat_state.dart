part of 'chat_bloc.dart';

/// Status of the chat.
enum ChatStatus {
  /// Initial state before conversation starts.
  initial,
  
  /// Ready to accept input.
  ready,
  
  /// Currently generating a response.
  generating,
  
  /// Translating a message.
  translating,
  
  /// An error occurred.
  error,
}

/// State of the chat conversation.
class ChatState extends Equatable {
  static const Object _unset = Object();
  /// The current conversation.
  final Conversation conversation;
  
  /// Current status.
  final ChatStatus status;
  
  /// ID of message currently being streamed.
  final String? currentStreamingMessageId;
  
  /// Error message if status is error.
  final String? errorMessage;
  
  /// Token count of last generation (for stats display).
  final int? lastGenerationTokenCount;
  
  /// Duration of last generation in milliseconds.
  final int? lastGenerationDurationMs;
  
  const ChatState({
    required this.conversation,
    required this.status,
    this.currentStreamingMessageId,
    this.errorMessage,
    this.lastGenerationTokenCount,
    this.lastGenerationDurationMs,
  });
  
  /// Create initial state.
  factory ChatState.initial() {
    return ChatState(
      conversation: Conversation.create(id: ''),
      status: ChatStatus.initial,
    );
  }
  
  /// Create a copy with updated fields.
  ChatState copyWith({
    Conversation? conversation,
    ChatStatus? status,
    Object? currentStreamingMessageId = _unset,
    Object? errorMessage = _unset,
    Object? lastGenerationTokenCount = _unset,
    Object? lastGenerationDurationMs = _unset,
  }) {
    return ChatState(
      conversation: conversation ?? this.conversation,
      status: status ?? this.status,
      currentStreamingMessageId: identical(currentStreamingMessageId, _unset)
          ? this.currentStreamingMessageId
          : currentStreamingMessageId as String?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      lastGenerationTokenCount: identical(lastGenerationTokenCount, _unset)
          ? this.lastGenerationTokenCount
          : lastGenerationTokenCount as int?,
      lastGenerationDurationMs: identical(lastGenerationDurationMs, _unset)
          ? this.lastGenerationDurationMs
          : lastGenerationDurationMs as int?,
    );
  }
  
  /// Whether the chat is currently generating.
  bool get isGenerating => status == ChatStatus.generating;
  
  /// Whether the chat is ready for input.
  bool get isReady => status == ChatStatus.ready;
  
  /// Whether there's an error.
  bool get hasError => status == ChatStatus.error && errorMessage != null;
  
  /// Get the currently streaming message.
  Message? get streamingMessage {
    if (currentStreamingMessageId == null) return null;
    try {
      return conversation.messages.firstWhere(
        (m) => m.id == currentStreamingMessageId,
      );
    } catch (_) {
      return null;
    }
  }
  
  /// Tokens per second for last generation.
  double? get tokensPerSecond {
    if (lastGenerationTokenCount == null || lastGenerationDurationMs == null) {
      return null;
    }
    if (lastGenerationDurationMs == 0) return 0;
    return lastGenerationTokenCount! / (lastGenerationDurationMs! / 1000);
  }
  
  @override
  List<Object?> get props => [
    conversation,
    status,
    currentStreamingMessageId,
    errorMessage,
    lastGenerationTokenCount,
    lastGenerationDurationMs,
  ];
}
