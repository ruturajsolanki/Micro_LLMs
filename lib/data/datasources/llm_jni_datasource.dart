import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/exceptions.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/model_info.dart';
import '../../domain/entities/inference_request.dart';
import 'llm_native_datasource.dart';

/// Implementation of LLM native data source using JNI via platform channels.
/// 
/// This bypasses Dart FFI completely and uses Kotlin/JNI to call llama.cpp,
/// avoiding all struct alignment issues that plague the FFI approach.
class LLMJniDataSourceImpl with Loggable implements LLMNativeDataSource {
  static const _channel = MethodChannel('com.microllm.app/llama');
  static const _memoryChannel = MethodChannel('com.microllm.app/memory');
  
  ModelInfo? _modelInfo;
  bool _isCancelled = false;
  int _eosToken = 2;
  
  @override
  Future<ModelInfo> loadModel({
    required String modelPath,
    int contextSize = 2048,
    int threads = 4,
  }) async {
    // Use more threads on multi-core devices for better performance
    final optimizedThreads = threads < 6 ? 6 : threads;
    logger.i('Loading model via JNI: $modelPath (threads: $optimizedThreads)');
    
    // Validate file exists
    final file = File(modelPath);
    if (!await file.exists()) {
      throw ModelFileException(
        message: 'Model file not found',
        filePath: modelPath,
      );
    }
    
    final fileSize = await file.length();
    final fileSizeMB = fileSize ~/ 1024 ~/ 1024;
    logger.d('Model file size: ${fileSizeMB}MB');
    
    // Validate file size
    if (fileSize < 10 * 1024 * 1024) {
      throw ModelFileException(
        message: 'Model file too small (${fileSizeMB}MB). The file may be corrupted or incomplete.',
        filePath: modelPath,
      );
    }
    
    // Check available memory
    try {
      final memoryInfo = await _memoryChannel.invokeMethod<Map>('getMemoryInfo');
      
      if (memoryInfo != null) {
        final availableRam = (memoryInfo['availableBytes'] as num?)?.toInt() ?? 0;
        final totalRam = (memoryInfo['totalBytes'] as num?)?.toInt() ?? 0;
        final availableMB = availableRam ~/ 1024 ~/ 1024;
        final totalGB = totalRam / 1024 / 1024 / 1024;
        
        logger.i('Device RAM: ${totalGB.toStringAsFixed(1)}GB total, ${availableMB}MB available');
        
        final estimatedRequiredBytes = (fileSize * 1.5).toInt();
        final requiredMB = estimatedRequiredBytes ~/ 1024 ~/ 1024;
        
        if (availableRam < estimatedRequiredBytes) {
          logger.e('Insufficient RAM: need ~${requiredMB}MB, only ${availableMB}MB available');
          throw LLMException(
            message: 'Not enough memory to load this model.\n\n'
                     'Required: ~${requiredMB}MB\n'
                     'Available: ${availableMB}MB\n\n'
                     'Try closing other apps or use a smaller model.',
            code: 'INSUFFICIENT_MEMORY',
          );
        }
        
        logger.d('Memory check passed: ${availableMB}MB available, ~${requiredMB}MB required');
      }
    } catch (e) {
      if (e is LLMException) rethrow;
      logger.w('Could not check memory: $e - proceeding anyway');
    }
    
    // Check GGUF magic
    try {
      final raf = await file.open();
      final magic = await raf.read(4);
      await raf.close();
      
      final magicStr = String.fromCharCodes(magic);
      if (magicStr != 'GGUF') {
        throw ModelFileException(
          message: 'Invalid model file format. Expected GGUF file.',
          filePath: modelPath,
        );
      }
    } catch (e) {
      if (e is ModelFileException) rethrow;
      logger.w('Could not verify GGUF magic: $e');
    }
    
    logger.i('Starting model load via JNI - this may take 1-5 minutes...');
    
    try {
      final result = await _channel.invokeMethod<Map>('loadModel', {
        'modelPath': modelPath,
        'contextSize': contextSize,
        'threads': optimizedThreads,
      });
      
      if (result == null || result['success'] != true) {
        throw const LLMException(
          message: 'Failed to load model via JNI',
          code: 'LOAD_FAILED',
        );
      }
      
      // Get EOS token
      try {
        _eosToken = await _channel.invokeMethod<int>('getEosToken') ?? 2;
      } catch (e) {
        logger.w('Could not get EOS token: $e, using default 2');
      }
      
      final loadTimeMs = result['loadTimeMs'] as int? ?? 0;
      final fileSizeBytes = result['fileSizeBytes'] as int? ?? fileSize;
      final actualContextSize = result['contextSize'] as int? ?? contextSize;
      
      logger.i('Model loaded successfully in ${loadTimeMs}ms');
      
      // Create model info
      final fileName = modelPath.split('/').last;
      _modelInfo = ModelInfo(
        fileName: fileName,
        filePath: modelPath,
        sizeBytes: fileSizeBytes,
        quantization: _detectQuantization(fileName),
        parameterCount: _formatParams(_estimateParams(fileSizeBytes)),
        contextSize: actualContextSize,
        architecture: 'Unknown',
      );
      
      logger.d('Context size: $actualContextSize, Model size: ${fileSizeBytes ~/ 1024 ~/ 1024}MB');
      
      return _modelInfo!;
    } on PlatformException catch (e) {
      logger.e('JNI load failed', error: e);
      throw LLMException(
        message: 'Failed to load model: ${e.message}',
        code: e.code,
      );
    }
  }
  
  @override
  Future<void> unloadModel() async {
    logger.i('Unloading model via JNI');
    try {
      await _channel.invokeMethod('unloadModel');
      _modelInfo = null;
      logger.i('Model unloaded');
    } on PlatformException catch (e) {
      logger.e('Failed to unload model', error: e);
    }
  }
  
  @override
  bool get isModelLoaded => _modelInfo != null;
  
  @override
  ModelInfo? get currentModelInfo => _modelInfo;
  
  @override
  Future<InferenceResponse> generate(InferenceRequest request) async {
    if (!isModelLoaded) {
      throw const LLMException(
        message: 'Model not loaded',
        code: 'NOT_LOADED',
      );
    }
    
    final stopwatch = Stopwatch()..start();
    
    try {
      final prompt = request.prompt;

      // Translation/explanation style prompts must not pollute chat memory.
      // Use the stateless native call which snapshots + restores the conversation buffer.
      final method = request.isolated ? 'generateStateless' : 'generate';
      final result = await _channel.invokeMethod<Map>(method, {
        'prompt': prompt,
        'maxTokens': request.maxTokens,
        'temperature': request.temperature,
        'topP': request.topP,
        'topK': request.topK,
        if (request.isolated) 'systemPrompt': request.systemPrompt,
        if (request.isolated) 'stopSequences': request.stopSequences,
      });
      
      stopwatch.stop();
      
      if (result == null) {
        throw const LLMException(
          message: 'Generation returned null',
          code: 'GENERATE_FAILED',
        );
      }
      
      return InferenceResponse(
        text: result['text'] as String? ?? '',
        promptTokens: result['promptTokens'] as int? ?? 0,
        completionTokens: result['tokenCount'] as int? ?? 0,
        totalTimeMs: stopwatch.elapsedMilliseconds,
      );
    } on PlatformException catch (e) {
      logger.e('Generate failed', error: e);
      throw LLMException(
        message: 'Generation failed: ${e.message}',
        code: e.code,
      );
    }
  }
  
  @override
  Stream<NativeInferenceEvent> generateStream(InferenceRequest request) async* {
    if (!isModelLoaded) {
      yield const NativeErrorEvent(message: 'Model not loaded');
      return;
    }
    
    _isCancelled = false;
    
    try {
      final prompt = request.prompt;
      logger.d('Generating response for user message (${prompt.length} chars)...');
      
      // Use batch generation - much faster than individual token calls
      final method = request.isolated ? 'generateStateless' : 'generate';
      final result = await _channel.invokeMethod<Map>(method, {
        'prompt': prompt,
        'maxTokens': request.maxTokens,
        'temperature': request.temperature,
        'topP': request.topP,
        'topK': request.topK,
        if (request.isolated) 'systemPrompt': request.systemPrompt,
        if (request.isolated) 'stopSequences': request.stopSequences,
      });
      
      if (result == null) {
        yield const NativeErrorEvent(message: 'Generation returned null');
        return;
      }
      
      final promptTokens = result['promptTokens'] as int? ?? 0;
      final text = result['text'] as String? ?? '';
      final tokenCount = result['tokenCount'] as int? ?? 0;
      
      yield NativePromptProcessedEvent(promptTokenCount: promptTokens);
      
      // Emit the entire text as one token event (batch mode)
      if (text.isNotEmpty) {
        yield NativeTokenEvent(
          token: text,
          tokenCount: tokenCount,
        );
      }
      
      yield NativeCompletionEvent(
        wasCancelled: _isCancelled,
        totalTokens: tokenCount,
        elapsedMs: 0,
      );
      
    } catch (e, stack) {
      logger.e('Inference error', error: e, stackTrace: stack);
      yield NativeErrorEvent(message: e.toString());
    }
  }
  
  @override
  void cancelGeneration() {
    _isCancelled = true;
  }
  
  @override
  Future<int> tokenize(String text) async {
    if (!isModelLoaded) return 0;
    
    try {
      final tokens = await _channel.invokeMethod<List>('tokenize', {
        'text': text,
        'addBos': false,
      });
      return tokens?.length ?? 0;
    } catch (e) {
      logger.w('Tokenize failed: $e');
      return 0;
    }
  }
  
  @override
  int? get memoryUsageBytes => _modelInfo?.sizeBytes;
  
  @override
  Future<MemoryInfo> getMemoryInfo() async {
    try {
      final memoryInfo = await _memoryChannel.invokeMethod<Map>('getMemoryInfo');
      
      if (memoryInfo != null) {
        return MemoryInfo(
          totalBytes: (memoryInfo['totalBytes'] as num?)?.toInt() ?? 0,
          availableBytes: (memoryInfo['availableBytes'] as num?)?.toInt() ?? 0,
          appUsageBytes: 0,
        );
      }
    } catch (e) {
      logger.w('Failed to get memory info: $e');
    }
    
    return const MemoryInfo(
      totalBytes: 0,
      availableBytes: 0,
      appUsageBytes: 0,
    );
  }
  
  String _detectQuantization(String path) {
    final lower = path.toLowerCase();
    if (lower.contains('q4_k_m')) return 'Q4_K_M';
    if (lower.contains('q4_k_s')) return 'Q4_K_S';
    if (lower.contains('q4_0')) return 'Q4_0';
    if (lower.contains('q5_k_m')) return 'Q5_K_M';
    if (lower.contains('q5_k_s')) return 'Q5_K_S';
    if (lower.contains('q8_0')) return 'Q8_0';
    if (lower.contains('f16')) return 'F16';
    return 'Unknown';
  }
  
  int _estimateParams(int fileSize) {
    // Rough estimate based on Q4_K_M quantization (~0.5GB per 1B params)
    return (fileSize / 0.5e9 * 1e9).toInt();
  }
  
  String _formatParams(int params) {
    if (params >= 1e9) return '${(params / 1e9).toStringAsFixed(1)}B';
    if (params >= 1e6) return '${(params / 1e6).toStringAsFixed(0)}M';
    return '$params';
  }
}
