import '../../domain/services/stt_model_path_resolver.dart';
import 'stt_model_download_service.dart';

class SttModelPathResolverImpl implements SttModelPathResolver {
  final SttModelDownloadService _downloadService;

  SttModelPathResolverImpl({required SttModelDownloadService downloadService})
      : _downloadService = downloadService;

  @override
  Future<String?> resolveWhisperModelPath(String modelId) async {
    final downloaded = await _downloadService.isModelDownloaded(modelId);
    if (!downloaded) return null;
    return _downloadService.getModelPath(modelId);
  }

  @override
  Future<bool> isWhisperModelDownloaded(String modelId) {
    return _downloadService.isModelDownloaded(modelId);
  }
}

