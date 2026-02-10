import '../repositories/model_repository.dart';
import '../../core/utils/result.dart';
import '../../core/error/failures.dart';
import 'usecase.dart';

/// Use case for downloading the LLM model.
/// 
/// Handles the model download process with:
/// - Storage space verification
/// - Progress reporting
/// - Integrity verification after download
/// - Cancellation support
class DownloadModelUseCase 
    extends StreamUseCase<ModelDownloadEvent, NoParams> {
  final ModelRepository _modelRepository;
  
  DownloadModelUseCase({
    required ModelRepository modelRepository,
  }) : _modelRepository = modelRepository;
  
  @override
  Stream<ModelDownloadEvent> call(NoParams params) async* {
    // Check if already downloaded
    final isDownloaded = await _modelRepository.isModelDownloaded();
    if (isDownloaded.fold((f) => false, (v) => v)) {
      // Verify integrity of existing download
      final integrityResult = await _modelRepository.verifyModelIntegrity();
      final isValid = integrityResult.fold((f) => false, (v) => v);
      
      if (isValid) {
        final modelInfo = await _modelRepository.getModelInfo();
        yield modelInfo.fold(
          (failure) => DownloadFailedEvent(
            message: 'Failed to read model info: ${failure.message}',
          ),
          (info) => DownloadCompletedEvent(
            modelPath: info!.filePath,
            modelInfo: info,
          ),
        );
        return;
      }
      
      // Model is corrupted, delete and re-download
      await _modelRepository.deleteModel();
    }
    
    // Check storage space
    final hasSpace = await _modelRepository.hasEnoughStorage();
    final enoughSpace = hasSpace.fold((f) => false, (v) => v);
    
    if (!enoughSpace) {
      final availableResult = await _modelRepository.getAvailableStorage();
      final available = availableResult.fold((f) => 0, (v) => v);
      
      yield DownloadFailedEvent(
        message: 'Insufficient storage space. '
                 'Need ${_modelRepository.expectedModelSize ~/ 1024 ~/ 1024}MB, '
                 'have ${available ~/ 1024 ~/ 1024}MB',
        code: 'INSUFFICIENT_STORAGE',
      );
      return;
    }
    
    // Start download
    yield* _modelRepository.downloadModel();
  }
  
  /// Cancel ongoing download.
  Future<void> cancel() async {
    await _modelRepository.cancelDownload();
  }
}
