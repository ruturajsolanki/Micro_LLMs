import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/error/exceptions.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/model_info.dart';
import '../../domain/repositories/model_repository.dart';

/// Data source for model download operations.
/// 
/// Handles downloading the model file from the configured URL with:
/// - Progress tracking
/// - Resume support
/// - Integrity verification
/// - Cancellation
abstract class ModelDownloadDataSource {
  Future<String> getModelDirectory();
  Future<String> getModelPath();
  Future<bool> isModelDownloaded();
  Future<ModelInfo?> getModelInfo();
  Stream<ModelDownloadEvent> downloadModel(String url);
  Future<void> cancelDownload();
  Future<void> deleteModel();
  Future<bool> verifyChecksum(String expectedHash);
  Future<int> getAvailableStorage();
}

class ModelDownloadDataSourceImpl with Loggable implements ModelDownloadDataSource {
  Dio? _dio;
  CancelToken? _cancelToken;
  
  Dio get dio {
    _dio ??= Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 30),
      // Large receive buffer for streaming
      responseType: ResponseType.stream,
    ));
    return _dio!;
  }
  
  @override
  Future<String> getModelDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDir.path}/models');
    
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    
    return modelDir.path;
  }
  
  @override
  Future<String> getModelPath() async {
    final modelDir = await getModelDirectory();
    return '$modelDir/${ModelConstants.defaultModelFilename}';
  }
  
  @override
  Future<bool> isModelDownloaded() async {
    final modelPath = await getModelPath();
    final file = File(modelPath);
    
    if (!await file.exists()) return false;
    
    // Check file size is reasonable
    final size = await file.length();
    return size > 100 * 1024 * 1024; // At least 100MB
  }
  
  @override
  Future<ModelInfo?> getModelInfo() async {
    final modelPath = await getModelPath();
    final file = File(modelPath);
    
    if (!await file.exists()) return null;
    
    final size = await file.length();
    
    return ModelInfo(
      fileName: ModelConstants.defaultModelFilename,
      filePath: modelPath,
      sizeBytes: size,
      quantization: 'Q4_K_M',
      parameterCount: '2.7B',
      contextSize: ModelConstants.contextWindowSize,
    );
  }
  
  @override
  Stream<ModelDownloadEvent> downloadModel(String url) async* {
    final modelPath = await getModelPath();
    final tempPath = '$modelPath.tmp';
    _cancelToken = CancelToken();
    
    try {
      // Check for partial download to resume
      final tempFile = File(tempPath);
      int existingBytes = 0;
      if (await tempFile.exists()) {
        existingBytes = await tempFile.length();
        logger.i('Resuming download from $existingBytes bytes');
      }
      
      // Get file size
      final headResponse = await dio.head(url);
      final contentLength = int.tryParse(
        headResponse.headers.value('content-length') ?? '',
      ) ?? ModelConstants.expectedModelSizeBytes;
      
      yield DownloadStartedEvent(totalBytes: contentLength);
      
      // Set up download with range header for resume
      final options = Options(
        headers: existingBytes > 0 
            ? {'Range': 'bytes=$existingBytes-'}
            : null,
      );
      
      final response = await dio.get<ResponseBody>(
        url,
        options: options,
        cancelToken: _cancelToken,
      );
      
      // Open file for appending
      final file = await tempFile.open(
        mode: existingBytes > 0 ? FileMode.append : FileMode.write,
      );
      
      int downloadedBytes = existingBytes;
      DateTime lastProgressUpdate = DateTime.now();
      int lastDownloadedBytes = existingBytes;
      
      try {
        await for (final chunk in response.data!.stream) {
          if (_cancelToken?.isCancelled ?? false) {
            await file.close();
            yield const DownloadCancelledEvent();
            return;
          }
          
          await file.writeFrom(chunk);
          downloadedBytes += chunk.length;
          
          // Throttle progress updates to every 100ms
          final now = DateTime.now();
          if (now.difference(lastProgressUpdate).inMilliseconds >= 100) {
            final bytesPerSecond = ((downloadedBytes - lastDownloadedBytes) * 
                1000 / now.difference(lastProgressUpdate).inMilliseconds).round();
            
            yield DownloadProgressEvent(
              progress: DownloadProgress(
                downloadedBytes: downloadedBytes,
                totalBytes: contentLength,
                bytesPerSecond: bytesPerSecond,
                estimatedRemaining: bytesPerSecond > 0
                    ? Duration(
                        seconds: (contentLength - downloadedBytes) ~/ bytesPerSecond,
                      )
                    : null,
              ),
            );
            
            lastProgressUpdate = now;
            lastDownloadedBytes = downloadedBytes;
          }
        }
      } finally {
        await file.close();
      }
      
      // Move temp file to final location
      final finalFile = File(modelPath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tempFile.rename(modelPath);
      
      // Verify download
      logger.i('Download complete, verifying...');
      final modelInfo = await getModelInfo();
      
      if (modelInfo == null) {
        yield const DownloadFailedEvent(
          message: 'Failed to read downloaded model',
          code: 'VERIFICATION_FAILED',
        );
        return;
      }
      
      yield DownloadCompletedEvent(
        modelPath: modelPath,
        modelInfo: modelInfo,
      );
      
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        yield const DownloadCancelledEvent();
      } else {
        yield DownloadFailedEvent(
          message: 'Download failed: ${e.message}',
          code: 'NETWORK_ERROR',
        );
      }
    } catch (e, stack) {
      logger.e('Download error', error: e, stackTrace: stack);
      yield DownloadFailedEvent(
        message: 'Download failed: $e',
        code: 'UNKNOWN_ERROR',
      );
    }
  }
  
  @override
  Future<void> cancelDownload() async {
    _cancelToken?.cancel('User cancelled');
    _cancelToken = null;
    
    // Clean up temp file
    final modelPath = await getModelPath();
    final tempFile = File('$modelPath.tmp');
    if (await tempFile.exists()) {
      // Don't delete - keep for resume
      logger.i('Download cancelled, temp file kept for resume');
    }
  }
  
  @override
  Future<void> deleteModel() async {
    final modelPath = await getModelPath();
    
    final file = File(modelPath);
    if (await file.exists()) {
      await file.delete();
      logger.i('Model file deleted');
    }
    
    final tempFile = File('$modelPath.tmp');
    if (await tempFile.exists()) {
      await tempFile.delete();
      logger.i('Temp file deleted');
    }
  }
  
  @override
  Future<bool> verifyChecksum(String expectedHash) async {
    final modelPath = await getModelPath();
    final file = File(modelPath);
    
    if (!await file.exists()) return false;
    
    try {
      logger.i('Computing file checksum...');
      
      // Stream file to compute hash without loading entire file into memory
      final digest = await sha256.bind(file.openRead()).first;
      final actualHash = digest.toString();
      
      logger.d('Expected: $expectedHash');
      logger.d('Actual: $actualHash');
      
      return actualHash.toLowerCase() == expectedHash.toLowerCase();
    } catch (e) {
      logger.e('Checksum verification failed: $e');
      return false;
    }
  }
  
  @override
  Future<int> getAvailableStorage() async {
    try {
      final modelDir = await getModelDirectory();
      
      // On Android, use platform channel to get storage info
      // For now, use a simplified approach
      final dir = Directory(modelDir);
      final stat = await dir.stat();
      
      // This is a placeholder - actual implementation would use
      // platform-specific APIs to get available space
      // On Android: StatFs
      // On iOS: NSFileManager
      
      // Return a large value as placeholder
      return 10 * 1024 * 1024 * 1024; // 10GB placeholder
    } catch (e) {
      logger.e('Failed to get storage info: $e');
      return 0;
    }
  }
}
