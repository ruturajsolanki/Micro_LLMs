import 'package:equatable/equatable.dart';

/// Information about the loaded LLM model.
/// 
/// This entity encapsulates all metadata about the currently loaded
/// model, including its capabilities and resource requirements.
class ModelInfo extends Equatable {
  /// Model file name.
  final String fileName;
  
  /// Full path to the model file.
  final String filePath;
  
  /// Model size in bytes.
  final int sizeBytes;
  
  /// Quantization type (e.g., "Q4_K_M").
  final String quantization;
  
  /// Number of parameters (e.g., 2.7B for Phi-2).
  final String parameterCount;
  
  /// Context window size in tokens.
  final int contextSize;
  
  /// Whether the model is currently loaded in memory.
  final bool isLoaded;
  
  /// Memory usage when loaded (bytes).
  final int? memoryUsageBytes;
  
  /// SHA256 hash for integrity verification.
  final String? sha256Hash;
  
  /// Model architecture (e.g., "phi2", "llama", "gemma").
  final String? architecture;
  
  /// Supported languages (if known).
  final List<String>? supportedLanguages;
  
  const ModelInfo({
    required this.fileName,
    required this.filePath,
    required this.sizeBytes,
    required this.quantization,
    required this.parameterCount,
    required this.contextSize,
    this.isLoaded = false,
    this.memoryUsageBytes,
    this.sha256Hash,
    this.architecture,
    this.supportedLanguages,
  });
  
  /// Create from GGUF metadata.
  factory ModelInfo.fromMetadata({
    required String filePath,
    required int sizeBytes,
    required Map<String, dynamic> metadata,
  }) {
    return ModelInfo(
      fileName: filePath.split('/').last,
      filePath: filePath,
      sizeBytes: sizeBytes,
      quantization: metadata['quantization'] as String? ?? 'unknown',
      parameterCount: metadata['parameter_count'] as String? ?? 'unknown',
      contextSize: metadata['context_size'] as int? ?? 2048,
      architecture: metadata['architecture'] as String?,
    );
  }
  
  /// Create a copy with updated fields.
  ModelInfo copyWith({
    String? fileName,
    String? filePath,
    int? sizeBytes,
    String? quantization,
    String? parameterCount,
    int? contextSize,
    bool? isLoaded,
    int? memoryUsageBytes,
    String? sha256Hash,
    String? architecture,
    List<String>? supportedLanguages,
  }) {
    return ModelInfo(
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      quantization: quantization ?? this.quantization,
      parameterCount: parameterCount ?? this.parameterCount,
      contextSize: contextSize ?? this.contextSize,
      isLoaded: isLoaded ?? this.isLoaded,
      memoryUsageBytes: memoryUsageBytes ?? this.memoryUsageBytes,
      sha256Hash: sha256Hash ?? this.sha256Hash,
      architecture: architecture ?? this.architecture,
      supportedLanguages: supportedLanguages ?? this.supportedLanguages,
    );
  }
  
  /// Human-readable size string.
  String get sizeFormatted {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    } else if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
  }
  
  /// Human-readable memory usage.
  String? get memoryUsageFormatted {
    if (memoryUsageBytes == null) return null;
    return '${(memoryUsageBytes! / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
  
  @override
  List<Object?> get props => [
    fileName,
    filePath,
    sizeBytes,
    quantization,
    parameterCount,
    contextSize,
    isLoaded,
    memoryUsageBytes,
    sha256Hash,
    architecture,
  ];
}

/// Status of model download/loading.
enum ModelStatus {
  /// Model not present on device.
  notDownloaded,
  
  /// Download in progress.
  downloading,
  
  /// Download complete, not loaded.
  downloaded,
  
  /// Currently loading into memory.
  loading,
  
  /// Model loaded and ready for inference.
  ready,
  
  /// Model unloading from memory.
  unloading,
  
  /// Error state.
  error,
}

/// Download progress information.
class DownloadProgress extends Equatable {
  /// Bytes downloaded so far.
  final int downloadedBytes;
  
  /// Total bytes to download.
  final int totalBytes;
  
  /// Current download speed (bytes/second).
  final int bytesPerSecond;
  
  /// Estimated time remaining.
  final Duration? estimatedRemaining;
  
  const DownloadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
    this.bytesPerSecond = 0,
    this.estimatedRemaining,
  });
  
  /// Progress as a fraction (0.0 to 1.0).
  double get progress => totalBytes > 0 ? downloadedBytes / totalBytes : 0;
  
  /// Progress as a percentage string.
  String get progressPercent => '${(progress * 100).toStringAsFixed(1)}%';
  
  /// Downloaded size formatted.
  String get downloadedFormatted =>
      '${(downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  
  /// Total size formatted.
  String get totalFormatted =>
      '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  
  /// Speed formatted.
  String get speedFormatted {
    if (bytesPerSecond >= 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    } else {
      return '${(bytesPerSecond / 1024).toStringAsFixed(0)} KB/s';
    }
  }
  
  @override
  List<Object?> get props => [downloadedBytes, totalBytes, bytesPerSecond];
}
