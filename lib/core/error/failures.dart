import 'package:equatable/equatable.dart';

/// Base failure class for domain-level errors.
/// 
/// Failures are domain-friendly error representations that hide
/// implementation details from upper layers. They are immutable
/// and equatable for easy testing and comparison.
/// 
/// Design Decision: We use sealed classes to ensure exhaustive
/// pattern matching in error handling code.
sealed class Failure extends Equatable {
  /// Human-readable error message for logging/debugging.
  final String message;
  
  /// Optional error code for programmatic handling.
  final String? code;
  
  /// Stack trace captured at failure creation for debugging.
  final StackTrace? stackTrace;
  
  const Failure({
    required this.message,
    this.code,
    this.stackTrace,
  });
  
  @override
  List<Object?> get props => [message, code];
}

/// Failure during LLM model operations.
final class LLMFailure extends Failure {
  /// Type of LLM failure for categorized handling.
  final LLMFailureType type;
  
  const LLMFailure({
    required super.message,
    required this.type,
    super.code,
    super.stackTrace,
  });
  
  /// Factory for model loading failures.
  factory LLMFailure.modelNotFound(String path) => LLMFailure(
    message: 'Model file not found at: $path',
    type: LLMFailureType.modelNotFound,
    code: 'LLM_MODEL_NOT_FOUND',
  );
  
  /// Factory for out-of-memory during inference.
  factory LLMFailure.outOfMemory(int availableBytes, int requiredBytes) => LLMFailure(
    message: 'Insufficient memory: ${availableBytes ~/ 1024 ~/ 1024}MB available, '
             '${requiredBytes ~/ 1024 ~/ 1024}MB required',
    type: LLMFailureType.outOfMemory,
    code: 'LLM_OOM',
  );
  
  /// Factory for model corruption.
  factory LLMFailure.modelCorrupted(String expectedHash, String actualHash) => LLMFailure(
    message: 'Model file corrupted. Expected hash: $expectedHash, got: $actualHash',
    type: LLMFailureType.modelCorrupted,
    code: 'LLM_MODEL_CORRUPTED',
  );
  
  /// Factory for inference errors.
  factory LLMFailure.inferenceError(String details) => LLMFailure(
    message: 'Inference failed: $details',
    type: LLMFailureType.inferenceError,
    code: 'LLM_INFERENCE_ERROR',
  );
  
  /// Factory for context overflow.
  factory LLMFailure.contextOverflow(int tokenCount, int maxTokens) => LLMFailure(
    message: 'Context overflow: $tokenCount tokens exceeds limit of $maxTokens',
    type: LLMFailureType.contextOverflow,
    code: 'LLM_CONTEXT_OVERFLOW',
  );
  
  /// Factory for model not loaded.
  factory LLMFailure.modelNotLoaded() => const LLMFailure(
    message: 'Model not loaded. Call loadModel() first.',
    type: LLMFailureType.modelNotLoaded,
    code: 'LLM_NOT_LOADED',
  );
  
  @override
  List<Object?> get props => [...super.props, type];
}

/// Categorization of LLM failures for handling logic.
enum LLMFailureType {
  modelNotFound,
  modelCorrupted,
  outOfMemory,
  inferenceError,
  contextOverflow,
  modelNotLoaded,
  unsupportedModel,
}

/// Failure during voice operations (STT/TTS).
final class VoiceFailure extends Failure {
  final VoiceFailureType type;
  
  const VoiceFailure({
    required super.message,
    required this.type,
    super.code,
    super.stackTrace,
  });
  
  factory VoiceFailure.speechRecognitionUnavailable() => const VoiceFailure(
    message: 'Speech recognition not available on this device',
    type: VoiceFailureType.sttUnavailable,
    code: 'VOICE_STT_UNAVAILABLE',
  );
  
  factory VoiceFailure.ttsUnavailable() => const VoiceFailure(
    message: 'Text-to-speech not available on this device',
    type: VoiceFailureType.ttsUnavailable,
    code: 'VOICE_TTS_UNAVAILABLE',
  );
  
  factory VoiceFailure.languageNotSupported(String language) => VoiceFailure(
    message: 'Language "$language" not supported for voice',
    type: VoiceFailureType.languageNotSupported,
    code: 'VOICE_LANG_UNSUPPORTED',
  );
  
  factory VoiceFailure.microphonePermissionDenied() => const VoiceFailure(
    message: 'Microphone permission denied',
    type: VoiceFailureType.permissionDenied,
    code: 'VOICE_MIC_DENIED',
  );
  
  @override
  List<Object?> get props => [...super.props, type];
}

enum VoiceFailureType {
  sttUnavailable,
  ttsUnavailable,
  languageNotSupported,
  permissionDenied,
  recognitionError,
  synthesisError,
}

/// Failure during model download.
final class DownloadFailure extends Failure {
  final DownloadFailureType type;
  final double? progress; // 0.0 to 1.0, null if unknown
  
  const DownloadFailure({
    required super.message,
    required this.type,
    this.progress,
    super.code,
    super.stackTrace,
  });
  
  factory DownloadFailure.networkError(String details) => DownloadFailure(
    message: 'Network error during download: $details',
    type: DownloadFailureType.networkError,
    code: 'DOWNLOAD_NETWORK_ERROR',
  );
  
  factory DownloadFailure.insufficientStorage(int required, int available) => DownloadFailure(
    message: 'Insufficient storage: ${required ~/ 1024 ~/ 1024}MB required, '
             '${available ~/ 1024 ~/ 1024}MB available',
    type: DownloadFailureType.insufficientStorage,
    code: 'DOWNLOAD_NO_SPACE',
  );
  
  factory DownloadFailure.cancelled() => const DownloadFailure(
    message: 'Download cancelled by user',
    type: DownloadFailureType.cancelled,
    code: 'DOWNLOAD_CANCELLED',
  );
  
  factory DownloadFailure.checksumMismatch() => const DownloadFailure(
    message: 'Downloaded file checksum does not match expected value',
    type: DownloadFailureType.checksumMismatch,
    code: 'DOWNLOAD_CHECKSUM_MISMATCH',
  );
  
  @override
  List<Object?> get props => [...super.props, type, progress];
}

enum DownloadFailureType {
  networkError,
  insufficientStorage,
  cancelled,
  checksumMismatch,
  timeout,
}

/// Failure during storage operations.
final class StorageFailure extends Failure {
  const StorageFailure({
    required super.message,
    super.code,
    super.stackTrace,
  });
  
  factory StorageFailure.readError(String key, Object error) => StorageFailure(
    message: 'Failed to read "$key": $error',
    code: 'STORAGE_READ_ERROR',
  );
  
  factory StorageFailure.writeError(String key, Object error) => StorageFailure(
    message: 'Failed to write "$key": $error',
    code: 'STORAGE_WRITE_ERROR',
  );
  
  factory StorageFailure.encryptionError(Object error) => StorageFailure(
    message: 'Encryption operation failed: $error',
    code: 'STORAGE_ENCRYPTION_ERROR',
  );
}
