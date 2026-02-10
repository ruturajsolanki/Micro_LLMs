import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// FFI bindings to llama.cpp native library.
/// 
/// This class provides Dart bindings to the compiled llama.cpp shared library.
/// The native library is compiled via Android NDK and loaded at runtime.
/// 
/// API Version: Compatible with llama.cpp b4000+ (2024/2025)
class LlamaBindings {
  late final DynamicLibrary _lib;
  bool _isInitialized = false;
  
  // Singleton pattern for safety
  static LlamaBindings? _instance;
  
  factory LlamaBindings() {
    _instance ??= LlamaBindings._internal();
    return _instance!;
  }
  
  LlamaBindings._internal() {
    _lib = _loadLibrary();
    _bindFunctions();
  }
  
  /// Load the native library based on platform.
  DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libllama.so');
    } else if (Platform.isIOS) {
      return DynamicLibrary.process();
    } else if (Platform.isMacOS) {
      return DynamicLibrary.open('libllama.dylib');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libllama.so');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('llama.dll');
    } else {
      throw UnsupportedError('Platform not supported');
    }
  }
  
  // ============================================================================
  // Native function pointers
  // ============================================================================
  
  // Backend
  late final Pointer<NativeFunction<Void Function()>> _llamaBackendInitPtr;
  late final Pointer<NativeFunction<Void Function()>> _llamaBackendFreePtr;
  
  // Model params
  late final Pointer<NativeFunction<LlamaModelParamsNative Function()>> _llamaModelDefaultParamsPtr;
  late final Pointer<NativeFunction<LlamaContextParamsNative Function()>> _llamaContextDefaultParamsPtr;
  
  // Model loading - using non-deprecated versions
  late final Pointer<NativeFunction<Pointer<Void> Function(Pointer<Utf8>, LlamaModelParamsNative)>> _llamaModelLoadFromFilePtr;
  late final Pointer<NativeFunction<Void Function(Pointer<Void>)>> _llamaModelFreePtr;
  
  // Context
  late final Pointer<NativeFunction<Pointer<Void> Function(Pointer<Void>, LlamaContextParamsNative)>> _llamaInitFromModelPtr;
  late final Pointer<NativeFunction<Void Function(Pointer<Void>)>> _llamaFreePtr;
  
  // Context info
  late final Pointer<NativeFunction<Uint32 Function(Pointer<Void>)>> _llamaNCtxPtr;
  late final Pointer<NativeFunction<Uint32 Function(Pointer<Void>)>> _llamaNBatchPtr;
  
  // Tokenization
  late final Pointer<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Utf8>, Int32, Pointer<Int32>, Int32, Bool, Bool)>> _llamaTokenizePtr;
  late final Pointer<NativeFunction<Int32 Function(Pointer<Void>, Int32, Pointer<Utf8>, Int32, Int32, Bool)>> _llamaTokenToPiecePtr;
  
  // Batch
  late final Pointer<NativeFunction<LlamaBatchNative Function(Pointer<Int32>, Int32)>> _llamaBatchGetOnePtr;
  late final Pointer<NativeFunction<LlamaBatchNative Function(Int32, Int32, Int32)>> _llamaBatchInitPtr;
  late final Pointer<NativeFunction<Void Function(LlamaBatchNative)>> _llamaBatchFreePtr;
  
  // Decode
  late final Pointer<NativeFunction<Int32 Function(Pointer<Void>, LlamaBatchNative)>> _llamaDecodePtr;
  
  // Sampler chain
  late final Pointer<NativeFunction<LlamaSamplerChainParamsNative Function()>> _llamaSamplerChainDefaultParamsPtr;
  late final Pointer<NativeFunction<Pointer<Void> Function(LlamaSamplerChainParamsNative)>> _llamaSamplerChainInitPtr;
  late final Pointer<NativeFunction<Void Function(Pointer<Void>, Pointer<Void>)>> _llamaSamplerChainAddPtr;
  late final Pointer<NativeFunction<Void Function(Pointer<Void>)>> _llamaSamplerFreePtr;
  
  // Individual samplers
  late final Pointer<NativeFunction<Pointer<Void> Function()>> _llamaSamplerInitGreedyPtr;
  late final Pointer<NativeFunction<Pointer<Void> Function(Uint32)>> _llamaSamplerInitDistPtr;
  late final Pointer<NativeFunction<Pointer<Void> Function(Int32)>> _llamaSamplerInitTopKPtr;
  late final Pointer<NativeFunction<Pointer<Void> Function(Float, Size)>> _llamaSamplerInitTopPPtr;
  late final Pointer<NativeFunction<Pointer<Void> Function(Float)>> _llamaSamplerInitTempPtr;
  
  // Sampling
  late final Pointer<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Void>, Int32)>> _llamaSamplerSamplePtr;
  late final Pointer<NativeFunction<Void Function(Pointer<Void>, Int32)>> _llamaSamplerAcceptPtr;
  
  // Vocab / Special tokens (through model)
  late final Pointer<NativeFunction<Pointer<Void> Function(Pointer<Void>)>> _llamaModelGetVocabPtr;
  late final Pointer<NativeFunction<Int32 Function(Pointer<Void>)>> _llamaVocabNTokensPtr;
  
  // Model info
  late final Pointer<NativeFunction<Pointer<Void> Function(Pointer<Void>)>> _llamaGetModelPtr;
  late final Pointer<NativeFunction<Uint64 Function(Pointer<Void>)>> _llamaModelSizePtr;
  late final Pointer<NativeFunction<Uint64 Function(Pointer<Void>)>> _llamaModelNParamsPtr;
  
  // Logits
  late final Pointer<NativeFunction<Pointer<Float> Function(Pointer<Void>)>> _llamaGetLogitsPtr;
  late final Pointer<NativeFunction<Pointer<Float> Function(Pointer<Void>, Int32)>> _llamaGetLogitsIthPtr;
  
  /// Bind native functions.
  void _bindFunctions() {
    // Backend
    _llamaBackendInitPtr = _lib.lookup('llama_backend_init');
    _llamaBackendFreePtr = _lib.lookup('llama_backend_free');
    
    // Model params
    _llamaModelDefaultParamsPtr = _lib.lookup('llama_model_default_params');
    _llamaContextDefaultParamsPtr = _lib.lookup('llama_context_default_params');
    
    // Model loading - try new API first, fallback to deprecated
    try {
      _llamaModelLoadFromFilePtr = _lib.lookup('llama_model_load_from_file');
    } catch (_) {
      _llamaModelLoadFromFilePtr = _lib.lookup('llama_load_model_from_file');
    }
    
    try {
      _llamaModelFreePtr = _lib.lookup('llama_model_free');
    } catch (_) {
      _llamaModelFreePtr = _lib.lookup('llama_free_model');
    }
    
    // Context
    try {
      _llamaInitFromModelPtr = _lib.lookup('llama_init_from_model');
    } catch (_) {
      _llamaInitFromModelPtr = _lib.lookup('llama_new_context_with_model');
    }
    _llamaFreePtr = _lib.lookup('llama_free');
    
    // Context info
    _llamaNCtxPtr = _lib.lookup('llama_n_ctx');
    _llamaNBatchPtr = _lib.lookup('llama_n_batch');
    
    // Tokenization
    _llamaTokenizePtr = _lib.lookup('llama_tokenize');
    _llamaTokenToPiecePtr = _lib.lookup('llama_token_to_piece');
    
    // Batch
    _llamaBatchGetOnePtr = _lib.lookup('llama_batch_get_one');
    _llamaBatchInitPtr = _lib.lookup('llama_batch_init');
    _llamaBatchFreePtr = _lib.lookup('llama_batch_free');
    
    // Decode
    _llamaDecodePtr = _lib.lookup('llama_decode');
    
    // Sampler
    _llamaSamplerChainDefaultParamsPtr = _lib.lookup('llama_sampler_chain_default_params');
    _llamaSamplerChainInitPtr = _lib.lookup('llama_sampler_chain_init');
    _llamaSamplerChainAddPtr = _lib.lookup('llama_sampler_chain_add');
    _llamaSamplerFreePtr = _lib.lookup('llama_sampler_free');
    
    // Individual samplers
    _llamaSamplerInitGreedyPtr = _lib.lookup('llama_sampler_init_greedy');
    _llamaSamplerInitDistPtr = _lib.lookup('llama_sampler_init_dist');
    _llamaSamplerInitTopKPtr = _lib.lookup('llama_sampler_init_top_k');
    _llamaSamplerInitTopPPtr = _lib.lookup('llama_sampler_init_top_p');
    _llamaSamplerInitTempPtr = _lib.lookup('llama_sampler_init_temp');
    
    // Sampling
    _llamaSamplerSamplePtr = _lib.lookup('llama_sampler_sample');
    _llamaSamplerAcceptPtr = _lib.lookup('llama_sampler_accept');
    
    // Vocab
    _llamaModelGetVocabPtr = _lib.lookup('llama_model_get_vocab');
    _llamaVocabNTokensPtr = _lib.lookup('llama_vocab_n_tokens');
    
    // Model info
    _llamaGetModelPtr = _lib.lookup('llama_get_model');
    _llamaModelSizePtr = _lib.lookup('llama_model_size');
    _llamaModelNParamsPtr = _lib.lookup('llama_model_n_params');
    
    // Logits
    _llamaGetLogitsPtr = _lib.lookup('llama_get_logits');
    _llamaGetLogitsIthPtr = _lib.lookup('llama_get_logits_ith');
  }
  
  // ============================================================================
  // Public API
  // ============================================================================
  
  /// Initialize the llama backend. Call once before using any other functions.
  void llamaBackendInit() {
    if (_isInitialized) return;
    _llamaBackendInitPtr.asFunction<void Function()>()();
    _isInitialized = true;
  }
  
  /// Free the llama backend. Call when done with all models.
  void llamaBackendFree() {
    if (!_isInitialized) return;
    _llamaBackendFreePtr.asFunction<void Function()>()();
    _isInitialized = false;
  }
  
  /// Get default model loading parameters as a Dart wrapper.
  LlamaModelParams llamaModelDefaultParams() {
    final native = _llamaModelDefaultParamsPtr
        .asFunction<LlamaModelParamsNative Function()>()();
    return LlamaModelParams.fromNative(native);
  }
  
  /// Get default model loading parameters as native struct pointer.
  /// This avoids conversion overhead and preserves all native defaults.
  Pointer<LlamaModelParamsNative> llamaModelDefaultParamsNative() {
    final ptr = calloc<LlamaModelParamsNative>();
    final native = _llamaModelDefaultParamsPtr
        .asFunction<LlamaModelParamsNative Function()>()();
    // Copy the entire native struct to our allocated memory
    ptr.ref = native;
    return ptr;
  }
  
  /// Get default context parameters as Dart wrapper.
  LlamaContextParams llamaContextDefaultParams() {
    final native = _llamaContextDefaultParamsPtr
        .asFunction<LlamaContextParamsNative Function()>()();
    return LlamaContextParams.fromNative(native);
  }
  
  /// Get default context parameters as native struct pointer.
  /// This avoids conversion overhead and preserves all native defaults.
  Pointer<LlamaContextParamsNative> llamaContextDefaultParamsNative() {
    final ptr = calloc<LlamaContextParamsNative>();
    final native = _llamaContextDefaultParamsPtr
        .asFunction<LlamaContextParamsNative Function()>()();
    // Copy the entire native struct to our allocated memory
    ptr.ref = native;
    return ptr;
  }
  
  /// Load a model from a GGUF file using wrapper class.
  Pointer<Void> llamaModelLoadFromFile(String path, LlamaModelParams params) {
    final pathPtr = path.toNativeUtf8();
    try {
      return _llamaModelLoadFromFilePtr
          .asFunction<Pointer<Void> Function(Pointer<Utf8>, LlamaModelParamsNative)>()
          (pathPtr, params.toNative());
    } finally {
      malloc.free(pathPtr);
    }
  }
  
  /// Load a model from a GGUF file using native struct pointer directly.
  /// This preserves all native default values without conversion overhead.
  Pointer<Void> llamaModelLoadFromFileNative(String path, Pointer<LlamaModelParamsNative> params) {
    final pathPtr = path.toNativeUtf8();
    try {
      return _llamaModelLoadFromFilePtr
          .asFunction<Pointer<Void> Function(Pointer<Utf8>, LlamaModelParamsNative)>()
          (pathPtr, params.ref);
    } finally {
      malloc.free(pathPtr);
    }
  }
  
  /// Free a loaded model.
  void llamaModelFree(Pointer<Void> model) {
    _llamaModelFreePtr.asFunction<void Function(Pointer<Void>)>()(model);
  }
  
  /// Create a context from a model.
  /// Create a context from a model using Dart wrapper.
  Pointer<Void> llamaInitFromModel(Pointer<Void> model, LlamaContextParams params) {
    return _llamaInitFromModelPtr
        .asFunction<Pointer<Void> Function(Pointer<Void>, LlamaContextParamsNative)>()
        (model, params.toNative());
  }
  
  /// Create a context from a model using native struct pointer directly.
  /// This preserves all native default values without conversion overhead.
  Pointer<Void> llamaInitFromModelNative(Pointer<Void> model, Pointer<LlamaContextParamsNative> params) {
    return _llamaInitFromModelPtr
        .asFunction<Pointer<Void> Function(Pointer<Void>, LlamaContextParamsNative)>()
        (model, params.ref);
  }
  
  /// Free a context.
  void llamaFree(Pointer<Void> ctx) {
    _llamaFreePtr.asFunction<void Function(Pointer<Void>)>()(ctx);
  }
  
  /// Get context size.
  int llamaNCtx(Pointer<Void> ctx) {
    return _llamaNCtxPtr.asFunction<int Function(Pointer<Void>)>()(ctx);
  }
  
  /// Get batch size.
  int llamaNBatch(Pointer<Void> ctx) {
    return _llamaNBatchPtr.asFunction<int Function(Pointer<Void>)>()(ctx);
  }
  
  /// Tokenize text into tokens.
  /// Returns the number of tokens written, or negative on error.
  int llamaTokenize(
    Pointer<Void> model,
    String text,
    Pointer<Int32> tokens,
    int nTokensMax, {
    bool addSpecial = true,
    bool parseSpecial = false,
  }) {
    final textPtr = text.toNativeUtf8();
    try {
      return _llamaTokenizePtr
          .asFunction<int Function(Pointer<Void>, Pointer<Utf8>, int, Pointer<Int32>, int, bool, bool)>()
          (model, textPtr, text.length, tokens, nTokensMax, addSpecial, parseSpecial);
    } finally {
      malloc.free(textPtr);
    }
  }
  
  /// Convert a token to text.
  /// Returns the number of characters written.
  int llamaTokenToPiece(
    Pointer<Void> model,
    int token,
    Pointer<Utf8> buf,
    int length, {
    int lstrip = 0,
    bool special = true,
  }) {
    return _llamaTokenToPiecePtr
        .asFunction<int Function(Pointer<Void>, int, Pointer<Utf8>, int, int, bool)>()
        (model, token, buf, length, lstrip, special);
  }
  
  /// Decode a batch of tokens.
  /// Returns 0 on success, negative on error.
  int llamaDecode(Pointer<Void> ctx, LlamaBatch batch) {
    return _llamaDecodePtr
        .asFunction<int Function(Pointer<Void>, LlamaBatchNative)>()
        (ctx, batch.toNative());
  }
  
  /// Decode tokens using llama_batch_get_one (simpler API).
  /// This avoids complex batch struct construction.
  /// Returns 0 on success, negative on error.
  int llamaDecodeSimple(Pointer<Void> ctx, Pointer<Int32> tokens, int nTokens) {
    final batchNative = _llamaBatchGetOnePtr
        .asFunction<LlamaBatchNative Function(Pointer<Int32>, int)>()
        (tokens, nTokens);
    return _llamaDecodePtr
        .asFunction<int Function(Pointer<Void>, LlamaBatchNative)>()
        (ctx, batchNative);
  }
  
  /// Get default sampler chain parameters.
  LlamaSamplerChainParams llamaSamplerChainDefaultParams() {
    final native = _llamaSamplerChainDefaultParamsPtr
        .asFunction<LlamaSamplerChainParamsNative Function()>()();
    return LlamaSamplerChainParams.fromNative(native);
  }
  
  /// Initialize a sampler chain.
  Pointer<Void> llamaSamplerChainInit(LlamaSamplerChainParams params) {
    return _llamaSamplerChainInitPtr
        .asFunction<Pointer<Void> Function(LlamaSamplerChainParamsNative)>()
        (params.toNative());
  }
  
  /// Initialize a sampler chain using native params directly.
  /// This preserves all native default values.
  Pointer<Void> llamaSamplerChainInitNative() {
    final native = _llamaSamplerChainDefaultParamsPtr
        .asFunction<LlamaSamplerChainParamsNative Function()>()();
    return _llamaSamplerChainInitPtr
        .asFunction<Pointer<Void> Function(LlamaSamplerChainParamsNative)>()
        (native);
  }
  
  /// Add a sampler to the chain.
  void llamaSamplerChainAdd(Pointer<Void> chain, Pointer<Void> sampler) {
    _llamaSamplerChainAddPtr
        .asFunction<void Function(Pointer<Void>, Pointer<Void>)>()
        (chain, sampler);
  }
  
  /// Free a sampler (chain or individual).
  void llamaSamplerFree(Pointer<Void> sampler) {
    _llamaSamplerFreePtr.asFunction<void Function(Pointer<Void>)>()(sampler);
  }
  
  /// Create a greedy sampler (always picks highest probability).
  Pointer<Void> llamaSamplerInitGreedy() {
    return _llamaSamplerInitGreedyPtr.asFunction<Pointer<Void> Function()>()();
  }
  
  /// Create a distribution sampler (random sampling with seed).
  Pointer<Void> llamaSamplerInitDist(int seed) {
    return _llamaSamplerInitDistPtr.asFunction<Pointer<Void> Function(int)>()(seed);
  }
  
  /// Create a top-k sampler.
  Pointer<Void> llamaSamplerInitTopK(int k) {
    return _llamaSamplerInitTopKPtr.asFunction<Pointer<Void> Function(int)>()(k);
  }
  
  /// Create a top-p (nucleus) sampler.
  Pointer<Void> llamaSamplerInitTopP(double p, int minKeep) {
    return _llamaSamplerInitTopPPtr.asFunction<Pointer<Void> Function(double, int)>()(p, minKeep);
  }
  
  /// Create a temperature sampler.
  Pointer<Void> llamaSamplerInitTemp(double temp) {
    return _llamaSamplerInitTempPtr.asFunction<Pointer<Void> Function(double)>()(temp);
  }
  
  /// Sample a token from the context at position idx.
  int llamaSamplerSample(Pointer<Void> sampler, Pointer<Void> ctx, int idx) {
    return _llamaSamplerSamplePtr
        .asFunction<int Function(Pointer<Void>, Pointer<Void>, int)>()
        (sampler, ctx, idx);
  }
  
  /// Accept a token (for repetition penalty etc).
  void llamaSamplerAccept(Pointer<Void> sampler, int token) {
    _llamaSamplerAcceptPtr
        .asFunction<void Function(Pointer<Void>, int)>()
        (sampler, token);
  }
  
  /// Get vocab from model.
  Pointer<Void> llamaModelGetVocab(Pointer<Void> model) {
    return _llamaModelGetVocabPtr.asFunction<Pointer<Void> Function(Pointer<Void>)>()(model);
  }
  
  /// Get vocab size.
  int llamaVocabNTokens(Pointer<Void> vocab) {
    return _llamaVocabNTokensPtr.asFunction<int Function(Pointer<Void>)>()(vocab);
  }
  
  /// Get model from context.
  Pointer<Void> llamaGetModel(Pointer<Void> ctx) {
    return _llamaGetModelPtr.asFunction<Pointer<Void> Function(Pointer<Void>)>()(ctx);
  }
  
  /// Get model size in bytes.
  int llamaModelSize(Pointer<Void> model) {
    return _llamaModelSizePtr.asFunction<int Function(Pointer<Void>)>()(model);
  }
  
  /// Get model parameter count.
  int llamaModelNParams(Pointer<Void> model) {
    return _llamaModelNParamsPtr.asFunction<int Function(Pointer<Void>)>()(model);
  }
  
  /// Get logits pointer.
  Pointer<Float> llamaGetLogits(Pointer<Void> ctx) {
    return _llamaGetLogitsPtr.asFunction<Pointer<Float> Function(Pointer<Void>)>()(ctx);
  }
  
  /// Get logits at index.
  Pointer<Float> llamaGetLogitsIth(Pointer<Void> ctx, int idx) {
    return _llamaGetLogitsIthPtr
        .asFunction<Pointer<Float> Function(Pointer<Void>, int)>()(ctx, idx);
  }
}

// ============================================================================
// Native struct definitions
// ============================================================================

/// Native model params struct - MUST match llama.cpp llama_model_params exactly.
/// Updated to match llama.cpp b4000+ (2024/2025 API)
/// CRITICAL: Field order and padding must exactly match the C struct layout!
final class LlamaModelParamsNative extends Struct {
  // ggml_backend_dev_t * devices - NULL-terminated list (offset 0)
  external Pointer<Void> devices;
  
  // const struct llama_model_tensor_buft_override * tensor_buft_overrides (offset 8)
  external Pointer<Void> tensorBuftOverrides;
  
  // int32_t n_gpu_layers (offset 16)
  @Int32()
  external int nGpuLayers;
  
  // enum llama_split_mode split_mode (offset 20) - enum is int32
  @Int32()
  external int splitMode;
  
  // int32_t main_gpu (offset 24)
  @Int32()
  external int mainGpu;
  
  // PADDING: 4 bytes to align next pointer to 8-byte boundary (offset 28)
  @Int32()
  external int _padding1;
  
  // const float * tensor_split (offset 32)
  external Pointer<Float> tensorSplit;
  
  // llama_progress_callback progress_callback (offset 40)
  external Pointer<NativeFunction<Bool Function(Float, Pointer<Void>)>> progressCallback;
  
  // void * progress_callback_user_data (offset 48)
  external Pointer<Void> progressCallbackUserData;
  
  // const struct llama_model_kv_override * kv_overrides (offset 56)
  external Pointer<Void> kvOverrides;
  
  // Booleans are packed together at the end (offset 64)
  @Bool()
  external bool vocabOnly;
  
  @Bool()
  external bool useMmap;
  
  @Bool()
  external bool useDirectIo;
  
  @Bool()
  external bool useMlock;
  
  @Bool()
  external bool checkTensors;
  
  @Bool()
  external bool useExtraBuffs;
  
  @Bool()
  external bool noHost;
  
  @Bool()
  external bool noAlloc;
}

/// Native context params struct - MUST match llama.cpp llama_context_params exactly.
/// Updated to match llama.cpp b4000+ (2024/2025 API)
final class LlamaContextParamsNative extends Struct {
  @Uint32()
  external int nCtx;
  
  @Uint32()
  external int nBatch;
  
  @Uint32()
  external int nUbatch;
  
  @Uint32()
  external int nSeqMax;
  
  @Int32()
  external int nThreads;
  
  @Int32()
  external int nThreadsBatch;
  
  @Int32()
  external int ropeScalingType;
  
  @Int32()
  external int poolingType;
  
  @Int32()
  external int attentionType;
  
  @Int32()
  external int flashAttnType;
  
  @Float()
  external double ropeFreqBase;
  
  @Float()
  external double ropeFreqScale;
  
  @Float()
  external double yarnExtFactor;
  
  @Float()
  external double yarnAttnFactor;
  
  @Float()
  external double yarnBetaFast;
  
  @Float()
  external double yarnBetaSlow;
  
  @Uint32()
  external int yarnOrigCtx;
  
  @Float()
  external double defragThold;
  
  // Callback for evaluation
  external Pointer<Void> cbEval;
  external Pointer<Void> cbEvalUserData;
  
  @Int32()
  external int typeK;
  
  @Int32()
  external int typeV;
  
  // Abort callback
  external Pointer<Void> abortCallback;
  external Pointer<Void> abortCallbackData;
  
  // Boolean fields at the end
  @Bool()
  external bool embeddings;
  
  @Bool()
  external bool offloadKqv;
  
  @Bool()
  external bool noPerf;
  
  @Bool()
  external bool opOffload;
  
  @Bool()
  external bool swaFull;
  
  @Bool()
  external bool kvUnified;
  
  // Sampler chain config
  external Pointer<Void> samplers;
  
  @Size()
  external int nSamplers;
}

/// Native batch struct.
/// Layout on ARM64:
///   int32_t n_tokens;    // 4 bytes, offset 0
///   [padding]            // 4 bytes, offset 4 (align token ptr to 8)
///   llama_token* token;  // 8 bytes, offset 8
///   float* embd;         // 8 bytes, offset 16
///   llama_pos* pos;      // 8 bytes, offset 24
///   int32_t* n_seq_id;   // 8 bytes, offset 32
///   llama_seq_id** seq_id; // 8 bytes, offset 40
///   int8_t* logits;      // 8 bytes, offset 48
/// Total: 56 bytes
final class LlamaBatchNative extends Struct {
  @Int32()
  external int nTokens;
  
  // Padding to align next pointer to 8-byte boundary
  @Int32()
  external int _padding;
  
  external Pointer<Int32> token;
  
  external Pointer<Float> embd;
  
  external Pointer<Int32> pos;
  
  external Pointer<Int32> nSeqId;
  
  external Pointer<Pointer<Int32>> seqId;
  
  external Pointer<Int8> logits;
}

/// Native sampler chain params.
final class LlamaSamplerChainParamsNative extends Struct {
  @Bool()
  external bool noPerf;
}

// ============================================================================
// Dart wrapper classes
// ============================================================================

/// Model loading parameters.
class LlamaModelParams {
  int nGpuLayers;
  bool vocabOnly;
  bool useMmap;
  bool useMlock;
  bool checkTensors;
  bool useDirectIo;
  bool useExtraBuffs;
  bool noHost;
  bool noAlloc;
  
  LlamaModelParams({
    this.nGpuLayers = 0,
    this.vocabOnly = false,
    this.useMmap = true,
    this.useMlock = false,
    this.checkTensors = false,
    this.useDirectIo = false,
    this.useExtraBuffs = false,
    this.noHost = false,
    this.noAlloc = false,
  });
  
  factory LlamaModelParams.fromNative(LlamaModelParamsNative native) {
    return LlamaModelParams(
      nGpuLayers: native.nGpuLayers,
      vocabOnly: native.vocabOnly,
      useMmap: native.useMmap,
      useMlock: native.useMlock,
      checkTensors: native.checkTensors,
      useDirectIo: native.useDirectIo,
      useExtraBuffs: native.useExtraBuffs,
      noHost: native.noHost,
      noAlloc: native.noAlloc,
    );
  }
  
  LlamaModelParamsNative toNative() {
    final ptr = calloc<LlamaModelParamsNative>();
    // New fields at the beginning
    ptr.ref.devices = nullptr;
    ptr.ref.tensorBuftOverrides = nullptr;
    // Existing fields
    ptr.ref.nGpuLayers = nGpuLayers;
    ptr.ref.splitMode = 0; // LLAMA_SPLIT_MODE_NONE
    ptr.ref.mainGpu = 0;
    ptr.ref._padding1 = 0; // Alignment padding
    ptr.ref.tensorSplit = nullptr;
    ptr.ref.progressCallback = nullptr;
    ptr.ref.progressCallbackUserData = nullptr;
    ptr.ref.kvOverrides = nullptr;
    // Boolean fields
    ptr.ref.vocabOnly = vocabOnly;
    ptr.ref.useMmap = useMmap;
    ptr.ref.useDirectIo = useDirectIo;
    ptr.ref.useMlock = useMlock;
    ptr.ref.checkTensors = checkTensors;
    ptr.ref.useExtraBuffs = useExtraBuffs;
    ptr.ref.noHost = noHost;
    ptr.ref.noAlloc = noAlloc;
    return ptr.ref;
  }
}

/// Context parameters.
class LlamaContextParams {
  int nCtx;
  int nBatch;
  int nThreads;
  int nThreadsBatch;
  bool embeddings;
  int flashAttnType; // 0 = disabled, 1 = enabled when possible
  
  LlamaContextParams({
    this.nCtx = 512,
    this.nBatch = 512,
    this.nThreads = 4,
    this.nThreadsBatch = 4,
    this.embeddings = false,
    this.flashAttnType = 0,
  });
  
  factory LlamaContextParams.fromNative(LlamaContextParamsNative native) {
    return LlamaContextParams(
      nCtx: native.nCtx,
      nBatch: native.nBatch,
      nThreads: native.nThreads,
      nThreadsBatch: native.nThreadsBatch,
      embeddings: native.embeddings,
      flashAttnType: native.flashAttnType,
    );
  }
  
  LlamaContextParamsNative toNative() {
    final ptr = calloc<LlamaContextParamsNative>();
    ptr.ref.nCtx = nCtx;
    ptr.ref.nBatch = nBatch;
    ptr.ref.nUbatch = nBatch;
    ptr.ref.nSeqMax = 1;
    ptr.ref.nThreads = nThreads;
    ptr.ref.nThreadsBatch = nThreadsBatch;
    ptr.ref.ropeScalingType = -1; // LLAMA_ROPE_SCALING_TYPE_UNSPECIFIED
    ptr.ref.poolingType = -1; // LLAMA_POOLING_TYPE_UNSPECIFIED
    ptr.ref.attentionType = 0; // LLAMA_ATTENTION_TYPE_UNSPECIFIED
    ptr.ref.flashAttnType = flashAttnType;
    ptr.ref.ropeFreqBase = 0.0;
    ptr.ref.ropeFreqScale = 0.0;
    ptr.ref.yarnExtFactor = -1.0;
    ptr.ref.yarnAttnFactor = 1.0;
    ptr.ref.yarnBetaFast = 32.0;
    ptr.ref.yarnBetaSlow = 1.0;
    ptr.ref.yarnOrigCtx = 0;
    ptr.ref.defragThold = -1.0;
    ptr.ref.cbEval = nullptr;
    ptr.ref.cbEvalUserData = nullptr;
    ptr.ref.typeK = 1; // GGML_TYPE_F16
    ptr.ref.typeV = 1; // GGML_TYPE_F16
    ptr.ref.abortCallback = nullptr;
    ptr.ref.abortCallbackData = nullptr;
    ptr.ref.embeddings = embeddings;
    ptr.ref.offloadKqv = true;
    ptr.ref.noPerf = false;
    ptr.ref.opOffload = true;
    ptr.ref.swaFull = true;
    ptr.ref.kvUnified = true;
    ptr.ref.samplers = nullptr;
    ptr.ref.nSamplers = 0;
    return ptr.ref;
  }
}

/// Batch of tokens.
class LlamaBatch {
  final Pointer<Int32> tokens;
  final int nTokens;
  final Pointer<Int32> pos;
  final Pointer<Int32> nSeqId;
  final Pointer<Pointer<Int32>> seqId;
  final Pointer<Int8> logits;
  
  LlamaBatch._({
    required this.tokens,
    required this.nTokens,
    required this.pos,
    required this.nSeqId,
    required this.seqId,
    required this.logits,
  });
  
  /// Create a simple batch from a list of tokens.
  factory LlamaBatch.fromTokens(List<int> tokenList, {int startPos = 0, bool lastLogits = true}) {
    final n = tokenList.length;
    final tokens = calloc<Int32>(n);
    final pos = calloc<Int32>(n);
    final nSeqId = calloc<Int32>(n);
    final seqId = calloc<Pointer<Int32>>(n);
    final logits = calloc<Int8>(n);
    
    for (int i = 0; i < n; i++) {
      tokens[i] = tokenList[i];
      pos[i] = startPos + i;
      nSeqId[i] = 1;
      final seqIdPtr = calloc<Int32>(1);
      seqIdPtr[0] = 0;
      seqId[i] = seqIdPtr;
      // Only compute logits for the last token (or all if needed)
      logits[i] = (lastLogits && i == n - 1) ? 1 : 0;
    }
    
    return LlamaBatch._(
      tokens: tokens,
      nTokens: n,
      pos: pos,
      nSeqId: nSeqId,
      seqId: seqId,
      logits: logits,
    );
  }
  
  LlamaBatchNative toNative() {
    final ptr = calloc<LlamaBatchNative>();
    ptr.ref.nTokens = nTokens;
    ptr.ref._padding = 0; // Alignment padding
    ptr.ref.token = tokens;
    ptr.ref.embd = nullptr;
    ptr.ref.pos = pos;
    ptr.ref.nSeqId = nSeqId;
    ptr.ref.seqId = seqId;
    ptr.ref.logits = logits;
    return ptr.ref;
  }
  
  void free() {
    for (int i = 0; i < nTokens; i++) {
      calloc.free(seqId[i]);
    }
    calloc.free(tokens);
    calloc.free(pos);
    calloc.free(nSeqId);
    calloc.free(seqId);
    calloc.free(logits);
  }
}

/// Sampler chain parameters.
class LlamaSamplerChainParams {
  bool noPerf;
  
  LlamaSamplerChainParams({this.noPerf = false});
  
  factory LlamaSamplerChainParams.fromNative(LlamaSamplerChainParamsNative native) {
    return LlamaSamplerChainParams(noPerf: native.noPerf);
  }
  
  LlamaSamplerChainParamsNative toNative() {
    final ptr = calloc<LlamaSamplerChainParamsNative>();
    ptr.ref.noPerf = noPerf;
    return ptr.ref;
  }
}
