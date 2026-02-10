import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../data/datasources/device_scanner_datasource.dart';
import '../../../data/services/model_download_service.dart';
import '../../../domain/entities/device_specs.dart';
import '../../../domain/services/compatibility_calculator.dart';
import '../../../domain/services/model_catalog.dart';
import '../../../core/utils/logger.dart';

part 'device_event.dart';
part 'device_state.dart';

/// BLoC for device scanning and model compatibility assessment.
/// 
/// Handles:
/// - Scanning device hardware specs
/// - Assessing model compatibility
/// - Recommending optimal models
/// - Real-time memory monitoring
/// - Model downloads
class DeviceBloc extends Bloc<DeviceEvent, DeviceState> with Loggable {
  final DeviceScannerDataSource _deviceScanner;
  final ModelDownloadService _downloadService = ModelDownloadService();
  StreamSubscription? _downloadSubscription;
  
  DeviceBloc({
    required DeviceScannerDataSource deviceScanner,
  })  : _deviceScanner = deviceScanner,
        super(const DeviceState()) {
    on<DeviceScanRequested>(_onScanRequested);
    on<DeviceMemoryRefreshRequested>(_onMemoryRefreshRequested);
    on<DeviceModelSelected>(_onModelSelected);
    on<ModelDownloadRequested>(_onDownloadRequested);
    on<ModelDownloadProgressUpdated>(_onDownloadProgress);
    on<ModelDownloadCompleted>(_onDownloadCompleted);
    on<ModelDownloadFailed>(_onDownloadFailed);
    on<ModelDownloadCancelled>(_onDownloadCancelled);
    
    // Check for already downloaded models on init
    _checkDownloadedModels();
  }
  
  Future<void> _checkDownloadedModels() async {
    try {
      final downloaded = await _downloadService.getDownloadedModels();
      final ids = downloaded
          .where((m) => m.catalogModel != null)
          .map((m) => m.catalogModel!.id)
          .toSet();
      // ignore: invalid_use_of_visible_for_testing_member
      emit(state.copyWith(downloadedModels: ids));
    } catch (e) {
      logger.w('Could not check downloaded models: $e');
    }
  }
  
  @override
  Future<void> close() {
    _downloadSubscription?.cancel();
    return super.close();
  }
  
  Future<void> _onScanRequested(
    DeviceScanRequested event,
    Emitter<DeviceState> emit,
  ) async {
    emit(state.copyWith(status: DeviceScanStatus.scanning));
    
    try {
      // Scan device
      final specs = await _deviceScanner.scanDevice();
      
      logger.i('Device scanned: ${specs.deviceModel}');
      logger.d('RAM: ${specs.ramFormatted}, Cores: ${specs.cpuCores}, '
               'Arch: ${specs.cpuArchitecture}');
      
      // Assess all models
      final assessments = CompatibilityCalculator.assessAll(specs);
      
      // Get recommendation
      final recommended = CompatibilityCalculator.getRecommended(specs);
      
      emit(state.copyWith(
        status: DeviceScanStatus.complete,
        deviceSpecs: specs,
        modelAssessments: assessments,
        recommendedModel: recommended,
      ));
      
    } catch (e, stack) {
      logger.e('Device scan failed', error: e, stackTrace: stack);
      emit(state.copyWith(
        status: DeviceScanStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }
  
  Future<void> _onMemoryRefreshRequested(
    DeviceMemoryRefreshRequested event,
    Emitter<DeviceState> emit,
  ) async {
    if (state.deviceSpecs == null) return;
    
    try {
      final memoryStatus = await _deviceScanner.getMemoryStatus();
      
      // Update device specs with new available RAM
      final updatedSpecs = DeviceSpecs(
        totalRamBytes: state.deviceSpecs!.totalRamBytes,
        availableRamBytes: memoryStatus.availableBytes,
        cpuCores: state.deviceSpecs!.cpuCores,
        cpuArchitecture: state.deviceSpecs!.cpuArchitecture,
        cpuMaxFrequencyMHz: state.deviceSpecs!.cpuMaxFrequencyMHz,
        supportsNeon: state.deviceSpecs!.supportsNeon,
        hasNpu: state.deviceSpecs!.hasNpu,
        gpuName: state.deviceSpecs!.gpuName,
        availableStorageBytes: state.deviceSpecs!.availableStorageBytes,
        deviceModel: state.deviceSpecs!.deviceModel,
        sdkVersion: state.deviceSpecs!.sdkVersion,
        socName: state.deviceSpecs!.socName,
      );
      
      // Re-assess with updated RAM
      final assessments = CompatibilityCalculator.assessAll(updatedSpecs);
      
      emit(state.copyWith(
        deviceSpecs: updatedSpecs,
        modelAssessments: assessments,
        isLowMemory: memoryStatus.isLowMemory,
      ));
      
    } catch (e) {
      logger.w('Memory refresh failed: $e');
    }
  }
  
  void _onModelSelected(
    DeviceModelSelected event,
    Emitter<DeviceState> emit,
  ) {
    final model = ModelCatalog.findById(event.modelId);
    if (model == null) return;
    
    final assessment = state.modelAssessments.firstWhere(
      (a) => a.model.id == event.modelId,
      orElse: () => state.modelAssessments.first,
    );
    
    emit(state.copyWith(selectedModel: assessment));
  }
  
  Future<void> _onDownloadRequested(
    ModelDownloadRequested event,
    Emitter<DeviceState> emit,
  ) async {
    if (state.downloadingModelId != null) {
      logger.w('Already downloading a model');
      return;
    }
    
    logger.i('Starting download for model: ${event.modelId}');
    
    emit(state.copyWith(
      downloadingModelId: event.modelId,
      downloadProgress: 0.0,
    ));
    
    await _downloadSubscription?.cancel();
    
    _downloadSubscription = _downloadService.downloadModel(event.modelId).listen(
      (downloadEvent) {
        switch (downloadEvent) {
          case DownloadStarted():
            add(ModelDownloadProgressUpdated(
              modelId: event.modelId,
              progress: 0.0,
            ));
          case DownloadProgress(:final progress):
            add(ModelDownloadProgressUpdated(
              modelId: event.modelId,
              progress: progress,
            ));
          case DownloadComplete():
            add(ModelDownloadCompleted(modelId: event.modelId));
          case DownloadError(:final message):
            add(ModelDownloadFailed(modelId: event.modelId, error: message));
          case DownloadCancelled():
            add(ModelDownloadCancelled(modelId: event.modelId));
        }
      },
      onError: (error) {
        add(ModelDownloadFailed(
          modelId: event.modelId,
          error: error.toString(),
        ));
      },
    );
  }
  
  void _onDownloadProgress(
    ModelDownloadProgressUpdated event,
    Emitter<DeviceState> emit,
  ) {
    emit(state.copyWith(downloadProgress: event.progress));
  }
  
  Future<void> _onDownloadCompleted(
    ModelDownloadCompleted event,
    Emitter<DeviceState> emit,
  ) async {
    logger.i('Download completed: ${event.modelId}');
    
    final updatedDownloads = Set<String>.from(state.downloadedModels)
      ..add(event.modelId);
    
    emit(state.copyWith(
      downloadedModels: updatedDownloads,
      downloadProgress: 1.0,
      clearDownloading: true,
    ));
  }
  
  void _onDownloadFailed(
    ModelDownloadFailed event,
    Emitter<DeviceState> emit,
  ) {
    logger.e('Download failed: ${event.error}');
    
    emit(state.copyWith(
      errorMessage: 'Download failed: ${event.error}',
      clearDownloading: true,
    ));
  }
  
  void _onDownloadCancelled(
    ModelDownloadCancelled event,
    Emitter<DeviceState> emit,
  ) {
    _downloadSubscription?.cancel();
    _downloadService.cancelDownload();
    
    emit(state.copyWith(clearDownloading: true));
  }
}
