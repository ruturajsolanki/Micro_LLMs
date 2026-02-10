part of 'model_bloc.dart';

/// Base class for model events.
sealed class ModelEvent extends Equatable {
  const ModelEvent();
  
  @override
  List<Object?> get props => [];
}

/// Check if model is downloaded/available.
final class ModelCheckRequested extends ModelEvent {
  const ModelCheckRequested();
}

/// Start model download.
final class ModelDownloadStarted extends ModelEvent {
  const ModelDownloadStarted();
}

/// Download progress update (internal event).
final class ModelDownloadProgressUpdated extends ModelEvent {
  final DownloadProgress progress;
  
  const ModelDownloadProgressUpdated({required this.progress});
  
  @override
  List<Object> get props => [progress];
}

/// Download completed (internal event).
final class ModelDownloadCompleted extends ModelEvent {
  final String modelPath;
  final ModelInfo modelInfo;
  
  const ModelDownloadCompleted({
    required this.modelPath,
    required this.modelInfo,
  });
  
  @override
  List<Object> get props => [modelPath, modelInfo];
}

/// Download failed (internal event).
final class ModelDownloadFailed extends ModelEvent {
  final String error;
  final String? code;
  
  const ModelDownloadFailed({
    required this.error,
    this.code,
  });
  
  @override
  List<Object?> get props => [error, code];
}

/// Download was cancelled.
final class ModelDownloadCancelled extends ModelEvent {
  const ModelDownloadCancelled();
}

/// Load model into memory.
final class ModelLoadRequested extends ModelEvent {
  final int? contextSize;
  final int? threads;
  
  const ModelLoadRequested({
    this.contextSize,
    this.threads,
  });
  
  @override
  List<Object?> get props => [contextSize, threads];
}

/// Load a specific model file into memory.
final class ModelLoadFromPathRequested extends ModelEvent {
  final String modelPath;
  final int? contextSize;
  final int? threads;

  const ModelLoadFromPathRequested({
    required this.modelPath,
    this.contextSize,
    this.threads,
  });

  @override
  List<Object?> get props => [modelPath, contextSize, threads];
}

/// Unload model from memory.
final class ModelUnloadRequested extends ModelEvent {
  const ModelUnloadRequested();
}
