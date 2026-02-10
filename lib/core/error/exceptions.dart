/// Data layer exceptions.
/// 
/// These are thrown by data sources and caught by repositories,
/// which convert them to Failures for the domain layer.
/// 
/// Design Decision: Exceptions are used at the data layer because
/// they can carry more context and are natural for I/O operations.
/// They are converted to Failures at repository boundaries.
library;

/// Base exception for all app-specific exceptions.
abstract class AppException implements Exception {
  final String message;
  final String? code;
  final Object? cause;
  final StackTrace? stackTrace;
  
  const AppException({
    required this.message,
    this.code,
    this.cause,
    this.stackTrace,
  });
  
  @override
  String toString() => '$runtimeType: $message${code != null ? ' ($code)' : ''}';
}

/// Exception thrown by LLM native operations.
class LLMException extends AppException {
  /// Native error code from llama.cpp, if available.
  final int? nativeErrorCode;
  
  const LLMException({
    required super.message,
    super.code,
    super.cause,
    super.stackTrace,
    this.nativeErrorCode,
  });
  
  factory LLMException.fromNative(int errorCode, String nativeMessage) {
    return LLMException(
      message: 'Native LLM error: $nativeMessage',
      code: 'NATIVE_$errorCode',
      nativeErrorCode: errorCode,
    );
  }
}

/// Exception for model file operations.
class ModelFileException extends AppException {
  final String filePath;
  
  const ModelFileException({
    required super.message,
    required this.filePath,
    super.code,
    super.cause,
    super.stackTrace,
  });
}

/// Exception for memory-related issues.
class MemoryException extends AppException {
  final int availableBytes;
  final int requiredBytes;
  
  const MemoryException({
    required super.message,
    required this.availableBytes,
    required this.requiredBytes,
    super.code,
    super.stackTrace,
  });
}

/// Exception for voice service operations.
class VoiceException extends AppException {
  final bool isRecoverable;
  
  const VoiceException({
    required super.message,
    this.isRecoverable = false,
    super.code,
    super.cause,
    super.stackTrace,
  });
}

/// Exception for download operations.
class DownloadException extends AppException {
  final int? httpStatusCode;
  final double? progressAtFailure;
  
  const DownloadException({
    required super.message,
    this.httpStatusCode,
    this.progressAtFailure,
    super.code,
    super.cause,
    super.stackTrace,
  });
}

/// Exception for storage operations.
class StorageException extends AppException {
  final String? key;
  
  const StorageException({
    required super.message,
    this.key,
    super.code,
    super.cause,
    super.stackTrace,
  });
}

/// Exception for security/encryption operations.
class SecurityException extends AppException {
  const SecurityException({
    required super.message,
    super.code,
    super.cause,
    super.stackTrace,
  });
}
