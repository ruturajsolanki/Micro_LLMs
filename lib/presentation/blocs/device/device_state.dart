part of 'device_bloc.dart';

/// Status of device scanning.
enum DeviceScanStatus {
  initial,
  scanning,
  complete,
  error,
}

/// State of device scanning and compatibility.
class DeviceState extends Equatable {
  /// Current status.
  final DeviceScanStatus status;
  
  /// Device specifications.
  final DeviceSpecs? deviceSpecs;
  
  /// Compatibility assessments for all models.
  final List<ModelCompatibility> modelAssessments;
  
  /// Recommended model for this device.
  final ModelCompatibility? recommendedModel;
  
  /// User-selected model (if different from recommended).
  final ModelCompatibility? selectedModel;
  
  /// Whether device is in low memory state.
  final bool isLowMemory;
  
  /// Error message.
  final String? errorMessage;
  
  /// Set of downloaded model IDs.
  final Set<String> downloadedModels;
  
  /// Model currently being downloaded (if any).
  final String? downloadingModelId;
  
  /// Download progress (0.0 to 1.0).
  final double downloadProgress;
  
  const DeviceState({
    this.status = DeviceScanStatus.initial,
    this.deviceSpecs,
    this.modelAssessments = const [],
    this.recommendedModel,
    this.selectedModel,
    this.isLowMemory = false,
    this.errorMessage,
    this.downloadedModels = const {},
    this.downloadingModelId,
    this.downloadProgress = 0.0,
  });
  
  /// Create copy with updated fields.
  DeviceState copyWith({
    DeviceScanStatus? status,
    DeviceSpecs? deviceSpecs,
    List<ModelCompatibility>? modelAssessments,
    ModelCompatibility? recommendedModel,
    ModelCompatibility? selectedModel,
    bool? isLowMemory,
    String? errorMessage,
    Set<String>? downloadedModels,
    String? downloadingModelId,
    double? downloadProgress,
    bool clearDownloading = false,
  }) {
    return DeviceState(
      status: status ?? this.status,
      deviceSpecs: deviceSpecs ?? this.deviceSpecs,
      modelAssessments: modelAssessments ?? this.modelAssessments,
      recommendedModel: recommendedModel ?? this.recommendedModel,
      selectedModel: selectedModel ?? this.selectedModel,
      isLowMemory: isLowMemory ?? this.isLowMemory,
      errorMessage: errorMessage,
      downloadedModels: downloadedModels ?? this.downloadedModels,
      downloadingModelId: clearDownloading ? null : (downloadingModelId ?? this.downloadingModelId),
      downloadProgress: downloadProgress ?? this.downloadProgress,
    );
  }
  
  /// Check if a model is downloaded.
  bool isModelDownloaded(String modelId) => downloadedModels.contains(modelId);
  
  /// Check if a model is currently downloading.
  bool isModelDownloading(String modelId) => downloadingModelId == modelId;
  
  /// Whether scan is in progress.
  bool get isScanning => status == DeviceScanStatus.scanning;
  
  /// Whether scan completed successfully.
  bool get isComplete => status == DeviceScanStatus.complete;
  
  /// Whether there was an error.
  bool get hasError => status == DeviceScanStatus.error;
  
  /// Get the active model (selected or recommended).
  ModelCompatibility? get activeModel => selectedModel ?? recommendedModel;
  
  /// Get compatible models (fair or better).
  List<ModelCompatibility> get compatibleModels => modelAssessments
      .where((a) => a.level != CompatibilityLevel.incompatible &&
                    a.level != CompatibilityLevel.poor)
      .toList();
  
  /// Get models that can run (including poor but not incompatible).
  List<ModelCompatibility> get runnableModels => modelAssessments
      .where((a) => a.level != CompatibilityLevel.incompatible)
      .toList();
  
  @override
  List<Object?> get props => [
    status,
    deviceSpecs,
    modelAssessments,
    recommendedModel,
    selectedModel,
    isLowMemory,
    errorMessage,
    downloadedModels,
    downloadingModelId,
    downloadProgress,
  ];
}
