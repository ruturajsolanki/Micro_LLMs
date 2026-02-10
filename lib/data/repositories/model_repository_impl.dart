import 'package:dartz/dartz.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/failures.dart';
import '../../core/utils/result.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/model_info.dart';
import '../../domain/repositories/model_repository.dart';
import '../datasources/model_download_datasource.dart';

/// Implementation of model repository.
class ModelRepositoryImpl with Loggable implements ModelRepository {
  final ModelDownloadDataSource _downloadDataSource;
  final FlutterSecureStorage _secureStorage;
  
  ModelRepositoryImpl({
    required ModelDownloadDataSource downloadDataSource,
    required FlutterSecureStorage secureStorage,
  })  : _downloadDataSource = downloadDataSource,
        _secureStorage = secureStorage;
  
  @override
  AsyncResult<bool> isModelDownloaded() async {
    try {
      final downloaded = await _downloadDataSource.isModelDownloaded();
      return Right(downloaded);
    } catch (e, stack) {
      logger.e('Failed to check model', error: e, stackTrace: stack);
      return Left(StorageFailure(
        message: 'Failed to check model: $e',
        stackTrace: stack,
      ));
    }
  }
  
  @override
  AsyncResult<String> getModelPath() async {
    try {
      final path = await _downloadDataSource.getModelPath();
      return Right(path);
    } catch (e, stack) {
      return Left(StorageFailure(
        message: 'Failed to get model path: $e',
        stackTrace: stack,
      ));
    }
  }
  
  @override
  AsyncResult<ModelInfo?> getModelInfo() async {
    try {
      final info = await _downloadDataSource.getModelInfo();
      return Right(info);
    } catch (e, stack) {
      return Left(StorageFailure(
        message: 'Failed to get model info: $e',
        stackTrace: stack,
      ));
    }
  }
  
  @override
  Stream<ModelDownloadEvent> downloadModel() {
    logger.i('Starting model download from $modelDownloadUrl');
    return _downloadDataSource.downloadModel(modelDownloadUrl);
  }
  
  @override
  Future<void> cancelDownload() async {
    await _downloadDataSource.cancelDownload();
    logger.i('Download cancelled');
  }
  
  @override
  AsyncResult<void> deleteModel() async {
    try {
      await _downloadDataSource.deleteModel();
      await _secureStorage.delete(key: 'model_checksum');
      return const Right(null);
    } catch (e, stack) {
      logger.e('Failed to delete model', error: e, stackTrace: stack);
      return Left(StorageFailure(
        message: 'Failed to delete model: $e',
        stackTrace: stack,
      ));
    }
  }
  
  @override
  AsyncResult<bool> verifyModelIntegrity() async {
    try {
      // First check if we have a stored checksum
      final storedChecksum = await _secureStorage.read(key: 'model_checksum');
      
      if (storedChecksum == null) {
        // No checksum stored, compute and store it
        // For now, return true if file exists and has reasonable size
        final isDownloaded = await _downloadDataSource.isModelDownloaded();
        return Right(isDownloaded);
      }
      
      // Verify against stored checksum
      final isValid = await _downloadDataSource.verifyChecksum(storedChecksum);
      return Right(isValid);
    } catch (e, stack) {
      logger.e('Integrity check failed', error: e, stackTrace: stack);
      return const Right(false);
    }
  }
  
  @override
  AsyncResult<int> getAvailableStorage() async {
    try {
      final available = await _downloadDataSource.getAvailableStorage();
      return Right(available);
    } catch (e, stack) {
      return Left(StorageFailure(
        message: 'Failed to get storage info: $e',
        stackTrace: stack,
      ));
    }
  }
  
  @override
  AsyncResult<bool> hasEnoughStorage() async {
    final availableResult = await getAvailableStorage();
    return availableResult.fold(
      (failure) => const Right(true), // Assume enough if we can't check
      (available) => Right(available > expectedModelSize * 1.1), // 10% buffer
    );
  }
  
  @override
  String get modelDownloadUrl => ModelConstants.modelDownloadUrl;
  
  @override
  int get expectedModelSize => ModelConstants.expectedModelSizeBytes;
}
