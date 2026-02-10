import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/exceptions.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/model_info.dart';
import '../../domain/entities/inference_request.dart';
import '../../native/llama_bindings.dart';

/// Data source for LLM operations via native llama.cpp.
/// 
/// This class interfaces with the native layer through FFI.
/// All operations are designed to be thread-safe and memory-efficient.
abstract class LLMNativeDataSource {
  /// Load a model from disk.
  Future<ModelInfo> loadModel({
    required String modelPath,
    int contextSize = 2048,
    int threads = 4,
  });
  
  /// Unload the current model.
  Future<void> unloadModel();
  
  /// Check if a model is loaded.
  bool get isModelLoaded;
  
  /// Get current model info.
  ModelInfo? get currentModelInfo;
  
  /// Run inference (non-streaming).
  Future<InferenceResponse> generate(InferenceRequest request);
  
  /// Run streaming inference.
  Stream<NativeInferenceEvent> generateStream(InferenceRequest request);
  
  /// Cancel ongoing inference.
  void cancelGeneration();
  
  /// Get token count for text.
  Future<int> tokenize(String text);
  
  /// Get memory usage.
  int? get memoryUsageBytes;
  
  /// Check available memory.
  Future<MemoryInfo> getMemoryInfo();
}

/// Implementation of LLM native data source using llama.cpp FFI bindings.
class LLMNativeDataSourceImpl with Loggable implements LLMNativeDataSource {
  LlamaBindings? _bindings;
  Pointer<Void>? _model;
  Pointer<Void>? _context;
  Pointer<Void>? _sampler;
  ModelInfo? _modelInfo;
  bool _isCancelled = false;
  int _currentPos = 0;
  
  // Token buffer for tokenization
  static const int _maxTokens = 8192;
  Pointer<Int32>? _tokenBuffer;
  
  // Text buffer for detokenization
  static const int _pieceBufferSize = 256;
  Pointer<Utf8>? _pieceBuffer;
  
  @override
  Future<ModelInfo> loadModel({
    required String modelPath,
    int contextSize = 2048,
    int threads = 4,
  }) async {
    logger.i('Loading model from: $modelPath');
    
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
    
    // Validate file size - minimum ~10MB for even tiny models
    if (fileSize < 10 * 1024 * 1024) {
      throw ModelFileException(
        message: 'Model file too small (${fileSizeMB}MB). The file may be corrupted or incomplete.',
        filePath: modelPath,
      );
    }
    
    // Check available memory before loading to prevent OOM crash
    try {
      final memoryChannel = const MethodChannel('com.microllm.app/memory');
      final memoryInfo = await memoryChannel.invokeMethod<Map>('getMemoryInfo');
      
      if (memoryInfo != null) {
        // Note: Kotlin handler returns 'availableBytes' and 'totalBytes' as Long
        final availableRam = (memoryInfo['availableBytes'] as num?)?.toInt() ?? 0;
        final totalRam = (memoryInfo['totalBytes'] as num?)?.toInt() ?? 0;
        final availableMB = availableRam ~/ 1024 ~/ 1024;
        final totalGB = totalRam / 1024 / 1024 / 1024;
        
        logger.i('Device RAM: ${totalGB.toStringAsFixed(1)}GB total, ${availableMB}MB available');
        
        // Estimate required memory: model file size * 1.5 (for context, buffers, etc.)
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
    
    // Check if file looks like a GGUF file (magic bytes)
    try {
      final raf = await file.open();
      final magic = await raf.read(4);
      await raf.close();
      
      // GGUF magic: "GGUF" = 0x46554747
      final magicStr = String.fromCharCodes(magic);
      if (magicStr != 'GGUF') {
        logger.w('File does not appear to be a GGUF file (magic: $magicStr)');
        throw ModelFileException(
          message: 'Invalid model file format. Expected GGUF file.',
          filePath: modelPath,
        );
      }
      logger.d('Valid GGUF file detected');
    } catch (e) {
      if (e is ModelFileException) rethrow;
      logger.w('Could not validate GGUF magic bytes: $e');
      // Continue anyway - the native loader will fail if invalid
    }
    
    // Estimate loading time based on file size (rough: ~1 min per GB on modern phones)
    final estimatedMinutes = (fileSizeMB / 1024).ceil();
    logger.i('Estimated loading time: ${estimatedMinutes > 0 ? estimatedMinutes : 1} minute(s)');
    
    // CRITICAL: Yield to UI before starting heavy FFI operations
    // This allows the loading indicator to render before we block
    await Future.delayed(const Duration(milliseconds: 100));
    
    try {
      // Initialize bindings if not already done
      _bindings ??= LlamaBindings();
      
      // Initialize backend
      _bindings!.llamaBackendInit();
      
      // Yield again after backend init
      await Future.delayed(const Duration(milliseconds: 50));
      
      // Allocate buffers
      _tokenBuffer ??= calloc<Int32>(_maxTokens);
      _pieceBuffer ??= calloc<Uint8>(_pieceBufferSize).cast<Utf8>();
      
      // Get native default params directly - avoids conversion overhead
      // and preserves all native defaults that llama.cpp sets
      final modelParamsPtr = _bindings!.llamaModelDefaultParamsNative();
      
      // Modify only what we need directly on the native struct
      modelParamsPtr.ref.nGpuLayers = 0; // CPU only for mobile
      modelParamsPtr.ref.useMmap = true;
      modelParamsPtr.ref.useMlock = false;
      
      // Debug: Print struct info
      logger.d('Model params struct size: ${sizeOf<LlamaModelParamsNative>()} bytes');
      logger.d('Loading model with nGpuLayers=${modelParamsPtr.ref.nGpuLayers}, useMmap=${modelParamsPtr.ref.useMmap}');
      logger.d('splitMode=${modelParamsPtr.ref.splitMode}, useExtraBuffs=${modelParamsPtr.ref.useExtraBuffs}');
      logger.d('Model path: $modelPath');
      logger.i('Starting model load - this may take 1-5 minutes depending on model size...');
      
      // Yield right before the heavy load - this is the critical point
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Load model using native struct directly - THIS IS THE BLOCKING CALL
      // Unfortunately FFI calls are synchronous and block the main thread
      // The delays above ensure the UI has rendered before we get here
      logger.d('Calling llama_model_load_from_file...');
      _model = _bindings!.llamaModelLoadFromFileNative(modelPath, modelParamsPtr);
      logger.d('llama_model_load_from_file returned: $_model');
      
      // Free the params pointer
      calloc.free(modelParamsPtr);
      
      if (_model == null || _model == nullptr) {
        throw const LLMException(
          message: 'Failed to load model - null pointer returned',
          code: 'LOAD_FAILED',
        );
      }
      
      logger.d('Model loaded, creating context...');
      
      // Yield after model load before context creation
      await Future.delayed(const Duration(milliseconds: 50));
      
      // Get native default context params directly - avoids conversion overhead
      // and preserves all native defaults that llama.cpp sets
      final contextParamsPtr = _bindings!.llamaContextDefaultParamsNative();
      
      // Modify only what we need directly on the native struct
      contextParamsPtr.ref.nCtx = contextSize;
      contextParamsPtr.ref.nBatch = 512;
      contextParamsPtr.ref.nUbatch = 512;
      contextParamsPtr.ref.nThreads = threads;
      contextParamsPtr.ref.nThreadsBatch = threads;
      contextParamsPtr.ref.flashAttnType = 0; // Disabled for CPU-only mobile
      
      logger.d('Context params: nCtx=${contextParamsPtr.ref.nCtx}, nBatch=${contextParamsPtr.ref.nBatch}, threads=$threads');
      
      _context = _bindings!.llamaInitFromModelNative(_model!, contextParamsPtr);
      
      // Free the params pointer
      calloc.free(contextParamsPtr);
      
      if (_context == null || _context == nullptr) {
        _bindings!.llamaModelFree(_model!);
        _model = null;
        throw const LLMException(
          message: 'Failed to create context',
          code: 'CONTEXT_FAILED',
        );
      }
      
      logger.d('Context created, setting up sampler...');
      
      // Create sampler chain with temperature and top-p
      _setupSampler();
      
      // Get model info
      final actualCtxSize = _bindings!.llamaNCtx(_context!);
      final modelSize = _bindings!.llamaModelSize(_model!);
      final nParams = _bindings!.llamaModelNParams(_model!);
      
      _modelInfo = ModelInfo(
        fileName: modelPath.split('/').last,
        filePath: modelPath,
        sizeBytes: fileSize,
        quantization: _detectQuantization(modelPath),
        parameterCount: _formatParams(nParams),
        contextSize: actualCtxSize,
        isLoaded: true,
        memoryUsageBytes: modelSize.toInt(),
      );
      
      _currentPos = 0;
      
      logger.i('Model loaded successfully: ${_modelInfo!.fileName}');
      logger.d('Context size: $actualCtxSize, Model size: ${modelSize ~/ 1024 ~/ 1024}MB');
      
      return _modelInfo!;
      
    } catch (e, stack) {
      logger.e('Failed to load model', error: e, stackTrace: stack);
      
      // Clean up on failure
      await _cleanup();
      
      if (e is AppException) rethrow;
      throw LLMException(
        message: 'Failed to load model: $e',
        cause: e,
        stackTrace: stack,
      );
    }
  }
  
  void _setupSampler({double temperature = 0.7, double topP = 0.9, int topK = 40}) {
    // Free existing sampler
    if (_sampler != null && _sampler != nullptr) {
      _bindings!.llamaSamplerFree(_sampler!);
    }
    
    // Create sampler chain using native params directly
    _sampler = _bindings!.llamaSamplerChainInitNative();
    
    // Add samplers in order: top-k -> top-p -> temperature -> distribution
    if (topK > 0) {
      _bindings!.llamaSamplerChainAdd(_sampler!, _bindings!.llamaSamplerInitTopK(topK));
    }
    if (topP < 1.0) {
      _bindings!.llamaSamplerChainAdd(_sampler!, _bindings!.llamaSamplerInitTopP(topP, 1));
    }
    if (temperature > 0) {
      _bindings!.llamaSamplerChainAdd(_sampler!, _bindings!.llamaSamplerInitTemp(temperature));
      _bindings!.llamaSamplerChainAdd(_sampler!, _bindings!.llamaSamplerInitDist(DateTime.now().millisecondsSinceEpoch));
    } else {
      // Greedy sampling when temperature is 0
      _bindings!.llamaSamplerChainAdd(_sampler!, _bindings!.llamaSamplerInitGreedy());
    }
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
  
  String _formatParams(int params) {
    if (params >= 1e9) return '${(params / 1e9).toStringAsFixed(1)}B';
    if (params >= 1e6) return '${(params / 1e6).toStringAsFixed(0)}M';
    return '$params';
  }
  
  @override
  Future<void> unloadModel() async {
    logger.i('Unloading model');
    cancelGeneration();
    await _cleanup();
    logger.i('Model unloaded');
  }
  
  Future<void> _cleanup() async {
    // Free sampler
    if (_sampler != null && _sampler != nullptr) {
      _bindings?.llamaSamplerFree(_sampler!);
      _sampler = null;
    }
    
    // Free context
    if (_context != null && _context != nullptr) {
      _bindings?.llamaFree(_context!);
      _context = null;
    }
    
    // Free model
    if (_model != null && _model != nullptr) {
      _bindings?.llamaModelFree(_model!);
      _model = null;
    }
    
    // Free buffers
    if (_tokenBuffer != null) {
      calloc.free(_tokenBuffer!);
      _tokenBuffer = null;
    }
    if (_pieceBuffer != null) {
      calloc.free(_pieceBuffer!.cast<Uint8>());
      _pieceBuffer = null;
    }
    
    _modelInfo = null;
    _currentPos = 0;
  }
  
  @override
  bool get isModelLoaded => _model != null && _context != null;
  
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
    final buffer = StringBuffer();
    int tokenCount = 0;
    int promptTokens = 0;
    
    await for (final event in generateStream(request)) {
      switch (event) {
        case NativeTokenEvent(:final token):
          buffer.write(token);
          tokenCount++;
        case NativePromptProcessedEvent(:final promptTokenCount):
          promptTokens = promptTokenCount;
        case NativeErrorEvent(:final message):
          throw LLMException(message: message);
        case NativeCompletionEvent():
          break;
      }
    }
    
    stopwatch.stop();
    
    return InferenceResponse(
      text: buffer.toString(),
      promptTokens: promptTokens,
      completionTokens: tokenCount,
      totalTimeMs: stopwatch.elapsedMilliseconds,
    );
  }
  
  @override
  Stream<NativeInferenceEvent> generateStream(InferenceRequest request) async* {
    if (!isModelLoaded) {
      yield const NativeErrorEvent(message: 'Model not loaded');
      return;
    }
    
    _isCancelled = false;
    final stopwatch = Stopwatch()..start();
    
    try {
      // Reset sampler with request parameters
      _setupSampler(
        temperature: request.temperature,
        topP: request.topP,
        topK: request.topK,
      );
      
      // Build and tokenize prompt
      final fullPrompt = request.buildFullPrompt();
      final promptTokens = _tokenizeText(fullPrompt);
      
      if (promptTokens.isEmpty) {
        yield const NativeErrorEvent(message: 'Failed to tokenize prompt');
        return;
      }
      
      // Check context window
      final ctxSize = _bindings!.llamaNCtx(_context!);
      if (promptTokens.length > ctxSize - 4) {
        yield NativeErrorEvent(
          message: 'Prompt too long: ${promptTokens.length} tokens exceeds '
                   'context size of $ctxSize',
        );
        return;
      }
      
      logger.d('Processing ${promptTokens.length} prompt tokens...');
      
      // Reset position for new generation
      _currentPos = 0;
      
      // Process prompt in batches using simple batch API
      final batchSize = _bindings!.llamaNBatch(_context!);
      for (int i = 0; i < promptTokens.length && !_isCancelled; i += batchSize) {
        final end = (i + batchSize > promptTokens.length) ? promptTokens.length : i + batchSize;
        final batchTokens = promptTokens.sublist(i, end);
        
        // Use simple batch API - allocate token array
        final tokenArray = calloc<Int32>(batchTokens.length);
        for (int j = 0; j < batchTokens.length; j++) {
          tokenArray[j] = batchTokens[j];
        }
        
        logger.d('Decoding batch of ${batchTokens.length} tokens...');
        final result = _bindings!.llamaDecodeSimple(_context!, tokenArray, batchTokens.length);
        
        // Free the token array
        calloc.free(tokenArray);
        
        if (result != 0) {
          yield NativeErrorEvent(message: 'Decode failed with code $result');
          return;
        }
        
        _currentPos += batchTokens.length;
      }
      
      if (_isCancelled) {
        yield const NativeCompletionEvent(wasCancelled: true);
        return;
      }
      
      yield NativePromptProcessedEvent(promptTokenCount: promptTokens.length);
      
      // Generate tokens
      int generatedCount = 0;
      final maxTokens = request.maxTokens;
      
      logger.d('Generating up to $maxTokens tokens...');
      
      while (generatedCount < maxTokens && !_isCancelled) {
        // Sample next token
        final newToken = _bindings!.llamaSamplerSample(_sampler!, _context!, -1);
        
        // Accept the token
        _bindings!.llamaSamplerAccept(_sampler!, newToken);
        
        // Check for end of sequence (token ID 2 is typically EOS for most models)
        // In practice, we should check against the model's actual EOS token
        if (newToken == 2 || newToken == 0) {
          break;
        }
        
        // Convert token to text
        final tokenText = _tokenToText(newToken);
        
        generatedCount++;
        
        yield NativeTokenEvent(
          token: tokenText,
          tokenCount: generatedCount,
        );
        
        // Decode the new token using simple batch API
        final singleTokenArray = calloc<Int32>(1);
        singleTokenArray[0] = newToken;
        final result = _bindings!.llamaDecodeSimple(_context!, singleTokenArray, 1);
        calloc.free(singleTokenArray);
        
        if (result != 0) {
          yield NativeErrorEvent(message: 'Decode failed during generation with code $result');
          return;
        }
        
        _currentPos++;
        
        // Check for stop sequences
        // TODO: Implement stop sequence checking
      }
      
      stopwatch.stop();
      
      yield NativeCompletionEvent(
        wasCancelled: _isCancelled,
        totalTokens: generatedCount,
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
      
    } catch (e, stack) {
      logger.e('Inference error', error: e, stackTrace: stack);
      yield NativeErrorEvent(message: e.toString());
    }
  }
  
  List<int> _tokenizeText(String text) {
    if (_model == null || _tokenBuffer == null) return [];
    
    final nTokens = _bindings!.llamaTokenize(
      _model!,
      text,
      _tokenBuffer!,
      _maxTokens,
      addSpecial: true,
      parseSpecial: false,
    );
    
    if (nTokens < 0) {
      logger.e('Tokenization failed with code $nTokens');
      return [];
    }
    
    return List.generate(nTokens, (i) => _tokenBuffer![i]);
  }
  
  String _tokenToText(int token) {
    if (_model == null || _pieceBuffer == null) return '';
    
    final nChars = _bindings!.llamaTokenToPiece(
      _model!,
      token,
      _pieceBuffer!,
      _pieceBufferSize,
      lstrip: 0,
      special: true,
    );
    
    if (nChars < 0) {
      return '';
    }
    
    return _pieceBuffer!.cast<Utf8>().toDartString(length: nChars);
  }
  
  @override
  void cancelGeneration() {
    _isCancelled = true;
  }
  
  @override
  Future<int> tokenize(String text) async {
    if (!isModelLoaded) {
      throw const LLMException(
        message: 'Model not loaded',
        code: 'NOT_LOADED',
      );
    }
    
    return _tokenizeText(text).length;
  }
  
  @override
  int? get memoryUsageBytes {
    if (!isModelLoaded) return null;
    return _modelInfo?.memoryUsageBytes;
  }
  
  @override
  Future<MemoryInfo> getMemoryInfo() async {
    // This should ideally call the platform channel to get real memory info
    // For now, return estimated values
    return const MemoryInfo(
      totalBytes: 4 * 1024 * 1024 * 1024, // 4GB
      availableBytes: 2 * 1024 * 1024 * 1024, // 2GB
      appUsageBytes: 512 * 1024 * 1024, // 512MB
    );
  }
}

/// Native inference events.
sealed class NativeInferenceEvent {
  const NativeInferenceEvent();
}

final class NativeTokenEvent extends NativeInferenceEvent {
  final String token;
  final int tokenCount;
  
  const NativeTokenEvent({
    required this.token,
    required this.tokenCount,
  });
}

final class NativePromptProcessedEvent extends NativeInferenceEvent {
  final int promptTokenCount;
  
  const NativePromptProcessedEvent({required this.promptTokenCount});
}

final class NativeCompletionEvent extends NativeInferenceEvent {
  final bool wasCancelled;
  final int totalTokens;
  final int elapsedMs;
  
  const NativeCompletionEvent({
    this.wasCancelled = false,
    this.totalTokens = 0,
    this.elapsedMs = 0,
  });
}

final class NativeErrorEvent extends NativeInferenceEvent {
  final String message;
  
  const NativeErrorEvent({required this.message});
}

/// Memory information.
class MemoryInfo {
  final int totalBytes;
  final int availableBytes;
  final int appUsageBytes;
  
  const MemoryInfo({
    required this.totalBytes,
    required this.availableBytes,
    required this.appUsageBytes,
  });
}
