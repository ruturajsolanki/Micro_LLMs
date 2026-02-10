import 'dart:async';

import 'package:dartz/dartz.dart';

import '../../core/error/failures.dart';
import '../../core/utils/result.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/inference_request.dart';
import '../../domain/entities/model_info.dart';
import '../../domain/repositories/llm_repository.dart';
import '../datasources/llm_native_datasource.dart';

/// Implementation of LLM repository.
/// 
/// Bridges the domain layer to the native data source, handling
/// error translation and result wrapping.
class LLMRepositoryImpl with Loggable implements LLMRepository {
  final LLMNativeDataSource _nativeDataSource;
  
  LLMRepositoryImpl({
    required LLMNativeDataSource nativeDataSource,
  }) : _nativeDataSource = nativeDataSource;
  
  @override
  AsyncResult<ModelInfo> loadModel({
    required String modelPath,
    int? contextSize,
    int? threads,
  }) async {
    try {
      final modelInfo = await _nativeDataSource.loadModel(
        modelPath: modelPath,
        contextSize: contextSize ?? 1024,
        threads: threads ?? 4,
      );
      return Right(modelInfo);
    } catch (e, stack) {
      logger.e('Failed to load model', error: e, stackTrace: stack);
      return Left(_mapException(e, stack));
    }
  }
  
  @override
  AsyncResult<void> unloadModel() async {
    try {
      await _nativeDataSource.unloadModel();
      return const Right(null);
    } catch (e, stack) {
      logger.e('Failed to unload model', error: e, stackTrace: stack);
      return Left(_mapException(e, stack));
    }
  }
  
  @override
  bool get isModelLoaded => _nativeDataSource.isModelLoaded;
  
  @override
  ModelInfo? get currentModelInfo => _nativeDataSource.currentModelInfo;
  
  @override
  AsyncResult<InferenceResponse> generate(InferenceRequest request) async {
    try {
      final response = await _nativeDataSource.generate(request);
      return Right(response);
    } catch (e, stack) {
      logger.e('Inference failed', error: e, stackTrace: stack);
      return Left(_mapException(e, stack));
    }
  }
  
  @override
  Stream<InferenceEvent> generateStream(InferenceRequest request) async* {
    try {
      final stopwatch = Stopwatch()..start();
      final buffer = StringBuffer();
      int tokenCount = 0;
      int? timeToFirstToken;
      
      int promptTokens = 0;
      
      await for (final event in _nativeDataSource.generateStream(request)) {
        switch (event) {
          case NativeTokenEvent(:final token):
            if (timeToFirstToken == null) {
              timeToFirstToken = stopwatch.elapsedMilliseconds;
            }
            buffer.write(token);
            tokenCount++;
            yield TokenEvent(token: token, tokenCount: tokenCount);
            
          case NativePromptProcessedEvent(:final promptTokenCount):
            promptTokens = promptTokenCount;
            // Optionally emit a progress event here
            
          case NativeCompletionEvent(:final wasCancelled, :final elapsedMs):
            stopwatch.stop();
            yield CompletionEvent(
              response: InferenceResponse(
                text: buffer.toString(),
                promptTokens: promptTokens,
                completionTokens: tokenCount,
                timeToFirstTokenMs: timeToFirstToken,
                totalTimeMs: elapsedMs > 0 ? elapsedMs : stopwatch.elapsedMilliseconds,
                stopReason: wasCancelled ? StopReason.cancelled : StopReason.endOfText,
              ),
            );
            
          case NativeErrorEvent(:final message):
            yield ErrorEvent(message: message);
        }
      }
    } catch (e, stack) {
      logger.e('Stream inference failed', error: e, stackTrace: stack);
      yield ErrorEvent(message: e.toString());
    }
  }
  
  @override
  void cancelGeneration() {
    _nativeDataSource.cancelGeneration();
  }
  
  @override
  AsyncResult<int> getTokenCount(String text) async {
    try {
      final count = await _nativeDataSource.tokenize(text);
      return Right(count);
    } catch (e, stack) {
      return Left(_mapException(e, stack));
    }
  }
  
  @override
  int? get memoryUsageBytes => _nativeDataSource.memoryUsageBytes;
  
  @override
  AsyncResult<MemoryStatus> checkMemoryStatus() async {
    try {
      final info = await _nativeDataSource.getMemoryInfo();
      return Right(MemoryStatus(
        totalBytes: info.totalBytes,
        availableBytes: info.availableBytes,
        appUsageBytes: info.appUsageBytes,
      ));
    } catch (e, stack) {
      return Left(_mapException(e, stack));
    }
  }
  
  /// Map exceptions to domain failures.
  LLMFailure _mapException(Object error, StackTrace? stack) {
    // Could add more specific exception handling here
    return LLMFailure(
      message: error.toString(),
      type: LLMFailureType.inferenceError,
      stackTrace: stack,
    );
  }
}
