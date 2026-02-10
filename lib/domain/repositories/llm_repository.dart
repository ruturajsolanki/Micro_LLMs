import '../entities/inference_request.dart';
import '../entities/model_info.dart';
import '../../core/utils/result.dart';

/// Repository interface for LLM operations.
/// 
/// This interface defines the contract for all LLM-related operations.
/// The implementation handles the actual interaction with llama.cpp via FFI.
/// 
/// Design Decision: Using a repository pattern allows us to:
/// 1. Mock the LLM for testing
/// 2. Swap implementations (e.g., different inference backends)
/// 3. Add caching, logging, or other cross-cutting concerns
abstract class LLMRepository {
  /// Load a model from the given path.
  /// 
  /// Returns [ModelInfo] on success with model metadata.
  /// This operation is expensive and should be done once at app startup
  /// or when switching models.
  /// 
  /// Parameters:
  /// - [modelPath]: Absolute path to the GGUF model file.
  /// - [contextSize]: Context window size (defaults to model's native size).
  /// - [threads]: Number of threads for inference.
  AsyncResult<ModelInfo> loadModel({
    required String modelPath,
    int? contextSize,
    int? threads,
  });
  
  /// Unload the currently loaded model from memory.
  /// 
  /// Should be called when:
  /// - App goes to background for extended period
  /// - User explicitly requests to free memory
  /// - Before loading a different model
  AsyncResult<void> unloadModel();
  
  /// Check if a model is currently loaded and ready.
  bool get isModelLoaded;
  
  /// Get information about the currently loaded model.
  ModelInfo? get currentModelInfo;
  
  /// Generate a response for the given request.
  /// 
  /// For streaming responses, use [generateStream] instead.
  /// This method waits for the complete response.
  AsyncResult<InferenceResponse> generate(InferenceRequest request);
  
  /// Generate a streaming response.
  /// 
  /// Yields tokens as they are generated. The final event contains
  /// the complete [InferenceResponse] with timing information.
  /// 
  /// The stream will emit:
  /// - [TokenEvent]: For each generated token
  /// - [CompletionEvent]: When generation is complete
  /// - [ErrorEvent]: If an error occurs
  Stream<InferenceEvent> generateStream(InferenceRequest request);
  
  /// Cancel an ongoing generation.
  /// 
  /// Safe to call even if no generation is in progress.
  void cancelGeneration();
  
  /// Get the token count for a given text.
  /// 
  /// Useful for:
  /// - Context window management
  /// - Displaying token count in UI
  /// - Estimating generation cost
  AsyncResult<int> getTokenCount(String text);
  
  /// Get current memory usage of the model.
  /// 
  /// Returns memory usage in bytes, or null if not available.
  int? get memoryUsageBytes;
  
  /// Check available system memory.
  /// 
  /// Used to determine if it's safe to load a model or run inference.
  AsyncResult<MemoryStatus> checkMemoryStatus();
}

/// Events emitted during streaming generation.
sealed class InferenceEvent {
  const InferenceEvent();
}

/// A single token was generated.
final class TokenEvent extends InferenceEvent {
  /// The generated token text.
  final String token;
  
  /// Running total of generated tokens.
  final int tokenCount;
  
  const TokenEvent({
    required this.token,
    required this.tokenCount,
  });
}

/// Generation completed successfully.
final class CompletionEvent extends InferenceEvent {
  /// The complete response with metrics.
  final InferenceResponse response;
  
  const CompletionEvent({required this.response});
}

/// An error occurred during generation.
final class ErrorEvent extends InferenceEvent {
  /// Error message.
  final String message;
  
  /// Error code if available.
  final String? code;
  
  const ErrorEvent({
    required this.message,
    this.code,
  });
}

/// Memory status information.
class MemoryStatus {
  /// Total system memory in bytes.
  final int totalBytes;
  
  /// Available memory in bytes.
  final int availableBytes;
  
  /// Memory used by the app in bytes.
  final int appUsageBytes;
  
  const MemoryStatus({
    required this.totalBytes,
    required this.availableBytes,
    required this.appUsageBytes,
  });
  
  /// Whether there's enough memory for model loading/inference.
  bool get hasSufficientMemory => availableBytes > 512 * 1024 * 1024; // 512MB
  
  /// Available memory in MB.
  int get availableMB => availableBytes ~/ (1024 * 1024);
  
  /// App usage in MB.
  int get appUsageMB => appUsageBytes ~/ (1024 * 1024);
}
