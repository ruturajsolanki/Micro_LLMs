import 'dart:async';

import 'package:dartz/dartz.dart';

import '../../core/error/failures.dart';
import '../../core/utils/logger.dart';
import '../../core/utils/result.dart';
import '../../domain/entities/cloud_provider.dart';
import '../../domain/entities/inference_request.dart';
import '../../domain/entities/model_info.dart';
import '../../domain/repositories/llm_repository.dart';
import '../services/cloud_api_key_storage.dart';
import '../services/groq_api_service.dart';
import '../services/gemini_api_service.dart';

/// Cloud-backed implementation of [LLMRepository].
///
/// Routes inference calls to Groq or Gemini APIs based on the configured
/// [CloudLLMProvider]. Implements the same interface so all existing use cases
/// (SummarizeTranscriptUseCase, EvaluationUseCase, SafetyPreprocessorUseCase)
/// work with zero changes.
class CloudLLMRepositoryImpl implements LLMRepository {
  final GroqApiService _groqApi;
  final GeminiApiService _geminiApi;
  final CloudApiKeyStorage _keyStorage;

  CloudLLMProvider _provider;
  bool _ready = false;

  CloudLLMRepositoryImpl({
    required GroqApiService groqApi,
    required GeminiApiService geminiApi,
    required CloudApiKeyStorage keyStorage,
    CloudLLMProvider provider = CloudLLMProvider.groq,
  })  : _groqApi = groqApi,
        _geminiApi = geminiApi,
        _keyStorage = keyStorage,
        _provider = provider;

  /// Change the active cloud provider at runtime.
  void setProvider(CloudLLMProvider provider) {
    _provider = provider;
  }

  CloudLLMProvider get provider => _provider;

  // ── LLMRepository interface ───────────────────────────────────────

  @override
  AsyncResult<ModelInfo> loadModel({
    required String modelPath,
    int? contextSize,
    int? threads,
  }) async {
    // Cloud models don't need loading. We just validate the key.
    final hasKey = _provider == CloudLLMProvider.groq
        ? await _keyStorage.hasGroqApiKey()
        : await _keyStorage.hasGeminiApiKey();

    if (!hasKey) {
      return Left(LLMFailure.modelNotLoaded());
    }

    _ready = true;

    return Right(ModelInfo(
      fileName: _provider.defaultModel,
      filePath: 'cloud://${_provider.id}/${_provider.defaultModel}',
      sizeBytes: 0,
      quantization: 'cloud',
      parameterCount: _provider == CloudLLMProvider.groq ? '70B' : 'unknown',
      contextSize: contextSize ?? 131072,
      isLoaded: true,
      architecture: _provider.id,
    ));
  }

  @override
  AsyncResult<void> unloadModel() async {
    _ready = false;
    return const Right(null);
  }

  @override
  bool get isModelLoaded => _ready;

  @override
  ModelInfo? get currentModelInfo => _ready
      ? ModelInfo(
          fileName: _provider.defaultModel,
          filePath: 'cloud://${_provider.id}/${_provider.defaultModel}',
          sizeBytes: 0,
          quantization: 'cloud',
          parameterCount:
              _provider == CloudLLMProvider.groq ? '70B' : 'unknown',
          contextSize: 131072,
          isLoaded: true,
          architecture: _provider.id,
        )
      : null;

  @override
  AsyncResult<InferenceResponse> generate(InferenceRequest request) async {
    try {
      switch (_provider) {
        case CloudLLMProvider.groq:
          return _generateGroq(request);
        case CloudLLMProvider.gemini:
          return _generateGemini(request);
      }
    } catch (e, stack) {
      AppLogger.e('CloudLLMRepository generate error: $e\n$stack');
      return Left(LLMFailure.inferenceError(e.toString()));
    }
  }

  @override
  Stream<InferenceEvent> generateStream(InferenceRequest request) async* {
    try {
      switch (_provider) {
        case CloudLLMProvider.groq:
          yield* _streamGroq(request);
        case CloudLLMProvider.gemini:
          yield* _streamGemini(request);
      }
    } catch (e) {
      yield ErrorEvent(message: e.toString());
    }
  }

  @override
  void cancelGeneration() {
    // Cloud requests are HTTP — cancellation is handled by Dio's
    // CancelToken if needed. For now, no-op.
  }

  @override
  AsyncResult<int> getTokenCount(String text) async {
    // Approximate: 1 token ≈ 4 characters (rough heuristic).
    return Right((text.length / 4).ceil());
  }

  @override
  int? get memoryUsageBytes => null;

  @override
  AsyncResult<MemoryStatus> checkMemoryStatus() async {
    return const Right(MemoryStatus(
      totalBytes: 0,
      availableBytes: 999999999,
      appUsageBytes: 0,
    ));
  }

  // ── Private: Groq ─────────────────────────────────────────────────

  Future<Result<InferenceResponse>> _generateGroq(
      InferenceRequest request) async {
    final key = await _keyStorage.getGroqApiKey();
    if (key == null || key.isEmpty) {
      return Left(LLMFailure.modelNotLoaded());
    }

    final response = await _groqApi.chatCompletion(
      apiKey: key,
      request: request,
    );

    return Right(InferenceResponse(
      text: response.text,
      promptTokens: response.promptTokens,
      completionTokens: response.completionTokens,
      totalTimeMs: response.totalTimeMs,
      stopReason: _mapFinishReason(response.finishReason),
      reachedMaxTokens: response.finishReason == 'length',
    ));
  }

  Stream<InferenceEvent> _streamGroq(InferenceRequest request) async* {
    final key = await _keyStorage.getGroqApiKey();
    if (key == null || key.isEmpty) {
      yield const ErrorEvent(message: 'Groq API key not configured');
      return;
    }

    await for (final event
        in _groqApi.chatCompletionStream(apiKey: key, request: request)) {
      if (event is GroqStreamToken) {
        yield TokenEvent(token: event.token, tokenCount: event.tokenCount);
      } else if (event is GroqStreamDone) {
        yield CompletionEvent(
          response: InferenceResponse(
            text: event.fullText,
            promptTokens: 0,
            completionTokens: event.tokenCount,
            totalTimeMs: event.totalTimeMs,
          ),
        );
      }
    }
  }

  // ── Private: Gemini ───────────────────────────────────────────────

  Future<Result<InferenceResponse>> _generateGemini(
      InferenceRequest request) async {
    final key = await _keyStorage.getGeminiApiKey();
    if (key == null || key.isEmpty) {
      return Left(LLMFailure.modelNotLoaded());
    }

    final response = await _geminiApi.generateContent(
      apiKey: key,
      request: request,
    );

    return Right(InferenceResponse(
      text: response.text,
      promptTokens: response.promptTokens,
      completionTokens: response.completionTokens,
      totalTimeMs: response.totalTimeMs,
      stopReason: response.finishReason == 'STOP'
          ? StopReason.endOfText
          : StopReason.maxTokens,
      reachedMaxTokens: response.finishReason == 'MAX_TOKENS',
    ));
  }

  Stream<InferenceEvent> _streamGemini(InferenceRequest request) async* {
    final key = await _keyStorage.getGeminiApiKey();
    if (key == null || key.isEmpty) {
      yield const ErrorEvent(message: 'Gemini API key not configured');
      return;
    }

    await for (final event
        in _geminiApi.generateContentStream(apiKey: key, request: request)) {
      if (event is GeminiStreamToken) {
        yield TokenEvent(token: event.token, tokenCount: event.tokenCount);
      } else if (event is GeminiStreamDone) {
        yield CompletionEvent(
          response: InferenceResponse(
            text: event.fullText,
            promptTokens: 0,
            completionTokens: event.tokenCount,
            totalTimeMs: event.totalTimeMs,
          ),
        );
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────

  StopReason _mapFinishReason(String reason) {
    switch (reason) {
      case 'stop':
        return StopReason.endOfText;
      case 'length':
        return StopReason.maxTokens;
      default:
        return StopReason.endOfText;
    }
  }
}
