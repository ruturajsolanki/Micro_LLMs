import 'package:equatable/equatable.dart';

import '../entities/message.dart';
import '../entities/inference_request.dart';
import '../repositories/llm_repository.dart';
import 'usecase.dart';

/// Use case for generating conversational responses.
/// 
/// This is the primary use case for the chat feature. It:
/// 1. Builds a proper prompt from conversation history
/// 2. Manages context window limits
/// 3. Returns a stream of tokens for real-time display
/// 
/// Usage:
/// ```dart
/// final stream = generateResponseUseCase(GenerateResponseParams(
///   userMessage: 'Hello!',
///   conversationHistory: [...],
/// ));
/// 
/// await for (final event in stream) {
///   if (event is TokenEvent) {
///     print(event.token);
///   }
/// }
/// ```
class GenerateResponseUseCase 
    extends StreamUseCase<InferenceEvent, GenerateResponseParams> {
  final LLMRepository _llmRepository;
  
  GenerateResponseUseCase({
    required LLMRepository llmRepository,
  }) : _llmRepository = llmRepository;
  
  @override
  Stream<InferenceEvent> call(GenerateResponseParams params) async* {
    // Validate model is loaded
    if (!_llmRepository.isModelLoaded) {
      yield const ErrorEvent(
        message: 'Model not loaded. Please wait for model to load.',
        code: 'MODEL_NOT_LOADED',
      );
      return;
    }
    
    // Check memory before inference
    final memoryResult = await _llmRepository.checkMemoryStatus();
    final memoryStatus = memoryResult.fold(
      (failure) => null,
      (status) => status,
    );
    
    if (memoryStatus != null && !memoryStatus.hasSufficientMemory) {
      yield ErrorEvent(
        message: 'Insufficient memory for inference. '
                 'Available: ${memoryStatus.availableMB}MB',
        code: 'INSUFFICIENT_MEMORY',
      );
      return;
    }
    
    // Build the inference request
    final request = InferenceRequest.forConversation(
      userMessage: params.userMessage,
      history: params.conversationHistory,
      maxTokens: params.maxTokens,
      temperature: params.temperature,
    );
    
    // Stream the response
    yield* _llmRepository.generateStream(request);
  }
  
  /// Cancel the current generation.
  void cancel() {
    _llmRepository.cancelGeneration();
  }
}

/// Parameters for generate response use case.
class GenerateResponseParams extends Equatable {
  /// The user's message to respond to.
  final String userMessage;
  
  /// Previous messages for context.
  final List<Message> conversationHistory;
  
  /// Maximum tokens to generate.
  final int maxTokens;
  
  /// Temperature for response generation.
  final double temperature;
  
  /// System prompt to use.
  final String? systemPrompt;
  
  const GenerateResponseParams({
    required this.userMessage,
    this.conversationHistory = const [],
    this.maxTokens = 512,
    this.temperature = 0.7,
    this.systemPrompt,
  });
  
  @override
  List<Object?> get props => [
    userMessage,
    conversationHistory,
    maxTokens,
    temperature,
    systemPrompt,
  ];
}
