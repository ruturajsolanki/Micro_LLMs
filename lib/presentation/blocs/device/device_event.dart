part of 'device_bloc.dart';

/// Base class for device events.
sealed class DeviceEvent extends Equatable {
  const DeviceEvent();
  
  @override
  List<Object?> get props => [];
}

/// Request device scan.
final class DeviceScanRequested extends DeviceEvent {
  const DeviceScanRequested();
}

/// Refresh memory status.
final class DeviceMemoryRefreshRequested extends DeviceEvent {
  const DeviceMemoryRefreshRequested();
}

/// User selected a model.
final class DeviceModelSelected extends DeviceEvent {
  final String modelId;
  
  const DeviceModelSelected({required this.modelId});
  
  @override
  List<Object> get props => [modelId];
}

/// Start downloading a model.
final class ModelDownloadRequested extends DeviceEvent {
  final String modelId;
  
  const ModelDownloadRequested({required this.modelId});
  
  @override
  List<Object> get props => [modelId];
}

/// Download progress update.
final class ModelDownloadProgressUpdated extends DeviceEvent {
  final String modelId;
  final double progress;
  
  const ModelDownloadProgressUpdated({
    required this.modelId,
    required this.progress,
  });
  
  @override
  List<Object> get props => [modelId, progress];
}

/// Download completed.
final class ModelDownloadCompleted extends DeviceEvent {
  final String modelId;
  
  const ModelDownloadCompleted({required this.modelId});
  
  @override
  List<Object> get props => [modelId];
}

/// Download failed.
final class ModelDownloadFailed extends DeviceEvent {
  final String modelId;
  final String error;
  
  const ModelDownloadFailed({required this.modelId, required this.error});
  
  @override
  List<Object> get props => [modelId, error];
}

/// Cancel download.
final class ModelDownloadCancelled extends DeviceEvent {
  final String modelId;
  
  const ModelDownloadCancelled({required this.modelId});
  
  @override
  List<Object> get props => [modelId];
}
