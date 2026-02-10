import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../domain/entities/model_info.dart';
import '../../../domain/repositories/model_repository.dart';
import '../../../domain/usecases/download_model_usecase.dart';
import '../../../domain/usecases/load_model_usecase.dart';
import '../../../domain/usecases/usecase.dart';
import '../../../core/utils/logger.dart';

part 'model_event.dart';
part 'model_state.dart';

/// BLoC for managing model download and loading state.
/// 
/// Handles:
/// - Checking if model is downloaded
/// - Downloading model with progress
/// - Loading model into memory
/// - Unloading model
class ModelBloc extends Bloc<ModelEvent, ModelState> with Loggable {
  final DownloadModelUseCase _downloadModelUseCase;
  final LoadModelUseCase _loadModelUseCase;
  final ModelRepository _modelRepository;
  
  StreamSubscription<ModelDownloadEvent>? _downloadSubscription;
  
  ModelBloc({
    required DownloadModelUseCase downloadModelUseCase,
    required LoadModelUseCase loadModelUseCase,
    required ModelRepository modelRepository,
  })  : _downloadModelUseCase = downloadModelUseCase,
        _loadModelUseCase = loadModelUseCase,
        _modelRepository = modelRepository,
        super(const ModelState()) {
    on<ModelCheckRequested>(_onCheckRequested);
    on<ModelDownloadStarted>(_onDownloadStarted);
    on<ModelDownloadProgressUpdated>(_onDownloadProgressUpdated);
    on<ModelDownloadCompleted>(_onDownloadCompleted);
    on<ModelDownloadFailed>(_onDownloadFailed);
    on<ModelDownloadCancelled>(_onDownloadCancelled);
    on<ModelLoadRequested>(_onLoadRequested);
    on<ModelLoadFromPathRequested>(_onLoadFromPathRequested);
    on<ModelUnloadRequested>(_onUnloadRequested);
  }
  
  @override
  Future<void> close() {
    _downloadSubscription?.cancel();
    return super.close();
  }
  
  Future<void> _onCheckRequested(
    ModelCheckRequested event,
    Emitter<ModelState> emit,
  ) async {
    emit(state.copyWith(status: ModelStatus.loading));
    
    final isDownloaded = await _modelRepository.isModelDownloaded();
    
    // Use pattern matching to handle Either properly with async
    final bool downloaded = isDownloaded.fold(
      (failure) {
        emit(state.copyWith(
          status: ModelStatus.error,
          errorMessage: failure.message,
        ));
        return false;
      },
      (value) => value,
    );
    
    // Early return if there was a failure
    if (isDownloaded.isLeft()) return;
    
    if (downloaded) {
      // Model exists, get info - MUST await to prevent emit after handler completes
      final infoResult = await _modelRepository.getModelInfo();
      infoResult.fold(
        (failure) {
          emit(state.copyWith(status: ModelStatus.downloaded));
        },
        (info) {
          emit(state.copyWith(
            status: ModelStatus.downloaded,
            modelInfo: info,
          ));
        },
      );
    } else {
      emit(state.copyWith(status: ModelStatus.notDownloaded));
    }
  }
  
  Future<void> _onDownloadStarted(
    ModelDownloadStarted event,
    Emitter<ModelState> emit,
  ) async {
    emit(state.copyWith(status: ModelStatus.downloading));
    
    await _downloadSubscription?.cancel();
    
    _downloadSubscription = _downloadModelUseCase(const NoParams()).listen(
      (downloadEvent) {
        switch (downloadEvent) {
          case DownloadStartedEvent(:final totalBytes):
            add(ModelDownloadProgressUpdated(
              progress: DownloadProgress(
                downloadedBytes: 0,
                totalBytes: totalBytes,
              ),
            ));
          case DownloadProgressEvent(:final progress):
            add(ModelDownloadProgressUpdated(progress: progress));
          case DownloadCompletedEvent(:final modelPath, :final modelInfo):
            add(ModelDownloadCompleted(
              modelPath: modelPath,
              modelInfo: modelInfo,
            ));
          case DownloadFailedEvent(:final message, :final code):
            add(ModelDownloadFailed(error: message, code: code));
          case DownloadCancelledEvent():
            add(const ModelDownloadCancelled());
        }
      },
      onError: (error) {
        add(ModelDownloadFailed(error: error.toString()));
      },
    );
  }
  
  void _onDownloadProgressUpdated(
    ModelDownloadProgressUpdated event,
    Emitter<ModelState> emit,
  ) {
    emit(state.copyWith(
      status: ModelStatus.downloading,
      downloadProgress: event.progress,
    ));
  }
  
  void _onDownloadCompleted(
    ModelDownloadCompleted event,
    Emitter<ModelState> emit,
  ) {
    logger.i('Model download completed');
    emit(state.copyWith(
      status: ModelStatus.downloaded,
      modelInfo: event.modelInfo,
      downloadProgress: null,
    ));
  }
  
  void _onDownloadFailed(
    ModelDownloadFailed event,
    Emitter<ModelState> emit,
  ) {
    logger.e('Download failed: ${event.error}');
    emit(state.copyWith(
      status: ModelStatus.error,
      errorMessage: event.error,
      downloadProgress: null,
    ));
  }
  
  void _onDownloadCancelled(
    ModelDownloadCancelled event,
    Emitter<ModelState> emit,
  ) {
    _downloadSubscription?.cancel();
    emit(state.copyWith(
      status: ModelStatus.notDownloaded,
      downloadProgress: null,
    ));
  }
  
  Future<void> _onLoadRequested(
    ModelLoadRequested event,
    Emitter<ModelState> emit,
  ) async {
    emit(state.copyWith(status: ModelStatus.loading));
    
    // CRITICAL: Yield to UI to allow the loading indicator to render
    // Without this, the blocking FFI call starts before Flutter can paint
    await Future.delayed(const Duration(milliseconds: 200));
    
    // Get model path (default)
    final pathResult = await _modelRepository.getModelPath();
    final modelPath = pathResult.fold((_) => null, (path) => path);

    if (modelPath == null) {
      emit(state.copyWith(
        status: ModelStatus.error,
        errorMessage: 'Could not determine model path',
      ));
      return;
    }

    await _loadFromPath(
      emit: emit,
      modelPath: modelPath,
      contextSize: event.contextSize,
      threads: event.threads,
    );
  }

  Future<void> _onLoadFromPathRequested(
    ModelLoadFromPathRequested event,
    Emitter<ModelState> emit,
  ) async {
    emit(state.copyWith(status: ModelStatus.loading));
    await Future.delayed(const Duration(milliseconds: 200));

    await _loadFromPath(
      emit: emit,
      modelPath: event.modelPath,
      contextSize: event.contextSize,
      threads: event.threads,
    );
  }

  Future<void> _loadFromPath({
    required Emitter<ModelState> emit,
    required String modelPath,
    int? contextSize,
    int? threads,
  }) async {
    logger.i('Starting model load from: $modelPath');
    logger.i('This may take 1-5 minutes for larger models...');

    final result = await _loadModelUseCase(LoadModelParams(
      modelPath: modelPath,
      contextSize: contextSize,
      threads: threads,
    ));
    
    result.fold(
      (failure) {
        logger.e('Failed to load model: ${failure.message}');
        emit(state.copyWith(
          status: ModelStatus.error,
          errorMessage: failure.message,
        ));
      },
      (modelInfo) {
        logger.i('Model loaded successfully');
        emit(state.copyWith(
          status: ModelStatus.ready,
          modelInfo: modelInfo,
        ));
      },
    );
  }
  
  Future<void> _onUnloadRequested(
    ModelUnloadRequested event,
    Emitter<ModelState> emit,
  ) async {
    emit(state.copyWith(status: ModelStatus.unloading));
    
    final result = await _loadModelUseCase.unload();
    
    result.fold(
      (failure) {
        emit(state.copyWith(
          status: ModelStatus.error,
          errorMessage: failure.message,
        ));
      },
      (_) {
        emit(state.copyWith(
          status: ModelStatus.downloaded,
          modelInfo: state.modelInfo?.copyWith(isLoaded: false),
        ));
      },
    );
  }
}
