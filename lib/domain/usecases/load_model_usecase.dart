import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../entities/model_info.dart';
import '../repositories/llm_repository.dart';
import '../repositories/model_repository.dart';
import '../../core/utils/result.dart';
import '../../core/error/failures.dart';
import '../../core/constants/app_constants.dart';
import 'usecase.dart';

/// Use case for loading the LLM model into memory.
/// 
/// This is an expensive operation that:
/// 1. Verifies the model file exists and is valid
/// 2. Checks available memory
/// 3. Loads the model into memory
/// 
/// Should be called once at app startup or when resuming from background.
class LoadModelUseCase extends UseCase<ModelInfo, LoadModelParams> {
  final LLMRepository _llmRepository;
  
  LoadModelUseCase({
    required LLMRepository llmRepository,
  }) : _llmRepository = llmRepository;
  
  @override
  AsyncResult<ModelInfo> call(LoadModelParams params) async {
    // Check if already loaded
    if (_llmRepository.isModelLoaded && !params.forceReload) {
      final currentInfo = _llmRepository.currentModelInfo;
      if (currentInfo != null) {
        return Right(currentInfo);
      }
    }
    
    // Check memory before loading
    final memoryResult = await _llmRepository.checkMemoryStatus();
    final memoryOk = memoryResult.fold(
      (failure) => true, // Proceed if we can't check (fallback to llama.cpp checks)
      (status) => status.hasSufficientMemory,
    );
    
    if (!memoryOk) {
      final status = memoryResult.fold((f) => null, (s) => s);
      return Left(LLMFailure.outOfMemory(
        status?.availableBytes ?? 0,
        ModelConstants.minAvailableMemoryBytes,
      ));
    }
    
    // Unload existing model if reloading
    if (_llmRepository.isModelLoaded) {
      await _llmRepository.unloadModel();
    }
    
    // Load the model
    return _llmRepository.loadModel(
      modelPath: params.modelPath,
      contextSize: params.contextSize ?? ModelConstants.contextWindowSize,
      threads: params.threads ?? ModelConstants.maxInferenceThreads,
    );
  }
  
  /// Unload the model from memory.
  AsyncResult<void> unload() async {
    return _llmRepository.unloadModel();
  }
  
  /// Check if model is loaded.
  bool get isLoaded => _llmRepository.isModelLoaded;
}

/// Parameters for loading the model.
class LoadModelParams extends Equatable {
  /// Path to the model file.
  final String modelPath;
  
  /// Context window size (optional, uses default if not specified).
  final int? contextSize;
  
  /// Number of inference threads (optional, auto-detected if not specified).
  final int? threads;
  
  /// Force reload even if already loaded.
  final bool forceReload;
  
  const LoadModelParams({
    required this.modelPath,
    this.contextSize,
    this.threads,
    this.forceReload = false,
  });
  
  @override
  List<Object?> get props => [modelPath, contextSize, threads, forceReload];
}
