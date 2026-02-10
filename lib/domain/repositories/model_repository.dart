import '../entities/model_info.dart';
import '../../core/utils/result.dart';

/// Repository interface for model file management.
/// 
/// Handles model download, storage, and validation. Separate from
/// LLMRepository which handles model loading and inference.
abstract class ModelRepository {
  /// Check if a model file exists at the expected location.
  AsyncResult<bool> isModelDownloaded();
  
  /// Get the path where the model should be stored.
  AsyncResult<String> getModelPath();
  
  /// Get model file information without loading it.
  AsyncResult<ModelInfo?> getModelInfo();
  
  /// Download the model from the configured URL.
  /// 
  /// Returns a stream of download progress events.
  /// The final event will be either a success or failure.
  Stream<ModelDownloadEvent> downloadModel();
  
  /// Cancel an ongoing download.
  Future<void> cancelDownload();
  
  /// Delete the downloaded model file.
  /// 
  /// Use to free storage space or re-download a corrupted model.
  AsyncResult<void> deleteModel();
  
  /// Verify model file integrity.
  /// 
  /// Computes and verifies SHA256 hash against stored/expected value.
  AsyncResult<bool> verifyModelIntegrity();
  
  /// Get available storage space in bytes.
  AsyncResult<int> getAvailableStorage();
  
  /// Check if there's enough storage for the model.
  AsyncResult<bool> hasEnoughStorage();
  
  /// Get the model download URL.
  String get modelDownloadUrl;
  
  /// Get the expected model size in bytes.
  int get expectedModelSize;
}

/// Events emitted during model download.
sealed class ModelDownloadEvent {
  const ModelDownloadEvent();
}

/// Download started.
final class DownloadStartedEvent extends ModelDownloadEvent {
  final int totalBytes;
  
  const DownloadStartedEvent({required this.totalBytes});
}

/// Download progress update.
final class DownloadProgressEvent extends ModelDownloadEvent {
  final DownloadProgress progress;
  
  const DownloadProgressEvent({required this.progress});
}

/// Download completed successfully.
final class DownloadCompletedEvent extends ModelDownloadEvent {
  final String modelPath;
  final ModelInfo modelInfo;
  
  const DownloadCompletedEvent({
    required this.modelPath,
    required this.modelInfo,
  });
}

/// Download failed.
final class DownloadFailedEvent extends ModelDownloadEvent {
  final String message;
  final String? code;
  final double? progressAtFailure;
  
  const DownloadFailedEvent({
    required this.message,
    this.code,
    this.progressAtFailure,
  });
}

/// Download cancelled by user.
final class DownloadCancelledEvent extends ModelDownloadEvent {
  const DownloadCancelledEvent();
}
