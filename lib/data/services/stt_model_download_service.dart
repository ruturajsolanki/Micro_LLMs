import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/utils/logger.dart';
import '../../domain/services/stt_model_catalog.dart';
import 'model_download_service.dart' show DownloadEvent, DownloadStarted, DownloadProgress, DownloadComplete, DownloadError, DownloadCancelled;

/// Service for downloading offline STT (Whisper) models.
class SttModelDownloadService with Loggable {
  HttpClient? _httpClient;
  bool _isCancelled = false;

  Future<String> getSttModelsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/stt_models');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  Future<String> getModelPath(String modelId) async {
    final dir = await getSttModelsDirectory();
    final model = SttModelCatalog.findById(modelId);
    if (model == null) throw Exception('STT model not found: $modelId');
    return '$dir/${model.fileName}';
  }

  Future<bool> isModelDownloaded(String modelId) async {
    final model = SttModelCatalog.findById(modelId);
    if (model == null) return false;
    final path = await getModelPath(modelId);
    final file = File(path);
    if (!await file.exists()) return false;
    final size = await file.length();
    return size >= model.sizeBytes * 0.90;
  }

  Stream<DownloadEvent> downloadModel(String modelId) async* {
    final model = SttModelCatalog.findById(modelId);
    if (model == null) {
      yield DownloadError(message: 'STT model not found: $modelId');
      return;
    }

    _isCancelled = false;

    final filePath = await getModelPath(modelId);
    final tempPath = '$filePath.download';
    final tempFile = File(tempPath);

    int downloadedBytes = 0;
    if (await tempFile.exists()) {
      downloadedBytes = await tempFile.length();
      logger.i('Resuming STT download from $downloadedBytes bytes');
    }

    yield DownloadStarted(modelId: modelId, totalBytes: model.sizeBytes, resumingFrom: downloadedBytes);

    try {
      _httpClient = HttpClient()..connectionTimeout = const Duration(seconds: 30);
      final request = await _httpClient!.getUrl(Uri.parse(model.downloadUrl));
      if (downloadedBytes > 0) {
        request.headers.add('Range', 'bytes=$downloadedBytes-');
      }
      final response = await request.close();

      if (response.statusCode != 200 && response.statusCode != 206) {
        yield DownloadError(message: 'Server returned ${response.statusCode}: ${response.reasonPhrase}');
        return;
      }

      int totalBytes = model.sizeBytes;
      final contentLength = response.headers.value('content-length');
      if (contentLength != null) {
        final serverSize = int.tryParse(contentLength);
        if (serverSize != null) {
          if (response.statusCode == 206) {
            totalBytes = downloadedBytes + serverSize;
          } else {
            totalBytes = serverSize;
            downloadedBytes = 0;
          }
        }
      }

      final sink = tempFile.openWrite(
        mode: downloadedBytes > 0 && response.statusCode == 206 ? FileMode.append : FileMode.write,
      );

      int received = downloadedBytes;
      DateTime last = DateTime.now();
      int lastBytes = received;

      try {
        await for (final chunk in response) {
          if (_isCancelled) {
            yield DownloadCancelled(downloadedBytes: received);
            break;
          }
          sink.add(chunk);
          received += chunk.length;

          final now = DateTime.now();
          if (now.difference(last).inMilliseconds > 120 || received - lastBytes > 1024 * 1024) {
            final bps = (received - lastBytes) / now.difference(last).inSeconds.clamp(1, 1000);
            yield DownloadProgress(
              downloadedBytes: received,
              totalBytes: totalBytes,
              bytesPerSecond: bps.toInt(),
            );
            last = now;
            lastBytes = received;
          }
        }

        await sink.flush();
        await sink.close();

        if (!_isCancelled) {
          final finalSize = await tempFile.length();
          if (finalSize < model.sizeBytes * 0.90) {
            yield DownloadError(message: 'Download incomplete: got $finalSize bytes');
            return;
          }
          await tempFile.rename(filePath);
          yield DownloadComplete(modelId: modelId, filePath: filePath, sizeBytes: finalSize);
        }
      } catch (e) {
        await sink.close();
        rethrow;
      }
    } catch (e, stack) {
      logger.e('STT download failed', error: e, stackTrace: stack);
      yield DownloadError(message: e.toString());
    } finally {
      _httpClient?.close(force: true);
      _httpClient = null;
    }
  }

  void cancelDownload() {
    _isCancelled = true;
    _httpClient?.close(force: true);
    _httpClient = null;
  }
}

