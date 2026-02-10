import 'package:equatable/equatable.dart';
import 'message.dart';

/// Request parameters for LLM inference.
/// 
/// Encapsulates all parameters needed for a single inference call.
/// This allows for type-safe parameter passing and easy testing.
class InferenceRequest extends Equatable {
  /// The prompt to send to the model.
  final String prompt;
  
  /// Conversation history for context.
  final List<Message> contextMessages;
  
  /// Maximum tokens to generate.
  final int maxTokens;
  
  /// Temperature for sampling (0.0-2.0).
  final double temperature;
  
  /// Top-p nucleus sampling parameter.
  final double topP;
  
  /// Top-k sampling parameter.
  final int topK;
  
  /// Repetition penalty.
  final double repetitionPenalty;
  
  /// Stop sequences to halt generation.
  final List<String> stopSequences;
  
  /// Whether to stream tokens as they're generated.
  final bool stream;
  
  /// If true, run this request in an isolated (stateless) context.
  ///
  /// Why:
  /// - Translation/explanation prompts should not pollute the main chat memory.
  /// - Chat history can "anchor" the model to the wrong language and degrade translation quality.
  /// - The JNI backend keeps an incremental KV-cache; isolation prevents cross-contamination.
  final bool isolated;

  /// Optional system prompt override used for isolated requests.
  ///
  /// The JNI backend uses ChatML and can accept a system prompt for stateless calls.
  final String? systemPrompt;

  const InferenceRequest({
    required this.prompt,
    this.contextMessages = const [],
    this.maxTokens = 512,
    this.temperature = 0.7,
    this.topP = 0.9,
    this.topK = 40,
    this.repetitionPenalty = 1.1,
    this.stopSequences = const [],
    this.stream = true,
    this.isolated = false,
    this.systemPrompt,
  });
  
  /// Create a request for a conversation response.
  factory InferenceRequest.forConversation({
    required String userMessage,
    required List<Message> history,
    int maxTokens = 512,
    double temperature = 0.7,
  }) {
    return InferenceRequest(
      prompt: userMessage,
      contextMessages: history,
      maxTokens: maxTokens,
      temperature: temperature,
      stream: true,
      isolated: false,
    );
  }
  
  /// Create a request for translation.
  factory InferenceRequest.forTranslation({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    // Translation should be more deterministic
    return InferenceRequest(
      // NOTE: This is intentionally stateless. Chat history often contains English and
      // can anchor the model to the wrong language, producing poor translations.
      isolated: true,
      systemPrompt: '''You are a professional translator.
You translate from $sourceLanguage to $targetLanguage.
Output ONLY the translated text in $targetLanguage.
Do not add explanations, quotes, bullet points, or any extra words.
Preserve meaning, tone, punctuation, and formatting.
Do not romanize; preserve the original script when applicable.''',
      prompt: '''Translate from $sourceLanguage to $targetLanguage.
Text:
$text''',
      maxTokens: 256,
      temperature: 0.1, // Lower temperature for translation
      stream: false, // Translation doesn't need streaming
      stopSequences: ['\n\n', '<|im_end|>'], // Trim common stop patterns
    );
  }
  
  /// Create a request for explanation.
  factory InferenceRequest.forExplanation({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    return InferenceRequest(
      prompt: '''Explain the following $sourceLanguage text in $targetLanguage.
Provide meaning, usage context, and any cultural notes if relevant.

Text: $text

Explanation:''',
      maxTokens: 384,
      temperature: 0.5,
      stream: true,
      isolated: false,
    );
  }
  
  /// Build the full prompt including context.
  /// Uses simple format that works with most models.
  String buildFullPrompt() {
    final buffer = StringBuffer();
    
    // Simple, clear prompt format
    buffer.writeln('You are a helpful assistant. Always respond in English.');
    buffer.writeln();
    
    // Add context messages
    for (final message in contextMessages) {
      if (message.role == MessageRole.user) {
        buffer.write('User: ');
        buffer.writeln(message.content);
      } else if (message.role == MessageRole.assistant) {
        buffer.write('Assistant: ');
        buffer.writeln(message.content);
      }
      buffer.writeln();
    }
    
    // Add current prompt
    buffer.write('User: ');
    buffer.writeln(prompt);
    buffer.writeln();
    buffer.write('Assistant:');
    
    return buffer.toString();
  }
  
  @override
  List<Object?> get props => [
    prompt,
    contextMessages,
    maxTokens,
    temperature,
    topP,
    topK,
    repetitionPenalty,
    stopSequences,
    stream,
    isolated,
    systemPrompt,
  ];
}

/// Response from LLM inference.
class InferenceResponse extends Equatable {
  /// Generated text.
  final String text;
  
  /// Number of tokens in the prompt.
  final int promptTokens;
  
  /// Number of tokens generated.
  final int completionTokens;
  
  /// Total tokens (prompt + completion).
  int get totalTokens => promptTokens + completionTokens;
  
  /// Time to first token (milliseconds).
  final int? timeToFirstTokenMs;
  
  /// Total inference time (milliseconds).
  final int totalTimeMs;
  
  /// Tokens per second.
  double get tokensPerSecond =>
      totalTimeMs > 0 ? completionTokens / (totalTimeMs / 1000) : 0;
  
  /// Whether generation was stopped due to reaching max tokens.
  final bool reachedMaxTokens;
  
  /// Stop reason.
  final StopReason stopReason;
  
  const InferenceResponse({
    required this.text,
    required this.promptTokens,
    required this.completionTokens,
    this.timeToFirstTokenMs,
    required this.totalTimeMs,
    this.reachedMaxTokens = false,
    this.stopReason = StopReason.endOfText,
  });
  
  @override
  List<Object?> get props => [
    text,
    promptTokens,
    completionTokens,
    timeToFirstTokenMs,
    totalTimeMs,
    reachedMaxTokens,
    stopReason,
  ];
}

/// Reason for stopping generation.
enum StopReason {
  /// Natural end of text.
  endOfText,
  
  /// Hit a stop sequence.
  stopSequence,
  
  /// Reached max tokens.
  maxTokens,
  
  /// User cancelled.
  cancelled,
  
  /// Error occurred.
  error,
}
