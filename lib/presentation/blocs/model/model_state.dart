part of 'model_bloc.dart';

/// State of the model loading/downloading process.
class ModelState extends Equatable {
  /// Current status.
  final ModelStatus status;
  
  /// Model information (if available).
  final ModelInfo? modelInfo;
  
  /// Download progress (if downloading).
  final DownloadProgress? downloadProgress;
  
  /// Error message (if error status).
  final String? errorMessage;
  
  const ModelState({
    this.status = ModelStatus.notDownloaded,
    this.modelInfo,
    this.downloadProgress,
    this.errorMessage,
  });
  
  /// Create a copy with updated fields.
  ModelState copyWith({
    ModelStatus? status,
    ModelInfo? modelInfo,
    DownloadProgress? downloadProgress,
    String? errorMessage,
  }) {
    return ModelState(
      status: status ?? this.status,
      modelInfo: modelInfo ?? this.modelInfo,
      downloadProgress: downloadProgress,
      errorMessage: errorMessage,
    );
  }
  
  /// Whether the model is ready for inference.
  bool get isReady => status == ModelStatus.ready;
  
  /// Whether download is in progress.
  bool get isDownloading => status == ModelStatus.downloading;
  
  /// Whether model is being loaded.
  bool get isLoading => status == ModelStatus.loading;
  
  /// Whether there's an error.
  bool get hasError => status == ModelStatus.error;
  
  /// Whether model needs to be downloaded.
  bool get needsDownload => status == ModelStatus.notDownloaded;
  
  /// Whether model is downloaded but not loaded.
  bool get needsLoading => status == ModelStatus.downloaded;
  
  /// Download progress as percentage (0-100).
  int get downloadPercentage {
    if (downloadProgress == null) return 0;
    return (downloadProgress!.progress * 100).round();
  }
  
  /// Status message for display.
  String get statusMessage {
    switch (status) {
      case ModelStatus.notDownloaded:
        return 'Model not downloaded';
      case ModelStatus.downloading:
        final progress = downloadProgress;
        if (progress != null) {
          return 'Downloading: ${progress.progressPercent}\n'
                 '${progress.downloadedFormatted} / ${progress.totalFormatted}\n'
                 '${progress.speedFormatted}';
        }
        return 'Downloading...';
      case ModelStatus.downloaded:
        return 'Model downloaded, ready to load';
      case ModelStatus.loading:
        return 'Loading model...';
      case ModelStatus.ready:
        return 'Model ready';
      case ModelStatus.unloading:
        return 'Unloading model...';
      case ModelStatus.error:
        return errorMessage ?? 'An error occurred';
    }
  }
  
  @override
  List<Object?> get props => [
    status,
    modelInfo,
    downloadProgress,
    errorMessage,
  ];
}
