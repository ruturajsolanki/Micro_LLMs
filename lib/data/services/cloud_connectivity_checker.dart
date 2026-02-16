import '../../core/utils/logger.dart';
import '../../domain/entities/cloud_provider.dart';
import 'cloud_api_key_storage.dart';
import 'groq_api_service.dart';
import 'gemini_api_service.dart';

/// Result of a cloud connectivity check.
class CloudStatus {
  final bool hasApiKey;
  final bool isReachable;
  final String? error;

  const CloudStatus({
    required this.hasApiKey,
    required this.isReachable,
    this.error,
  });

  bool get isReady => hasApiKey && isReachable;
}

/// Validates API keys and checks cloud service reachability.
class CloudConnectivityChecker {
  final CloudApiKeyStorage _keyStorage;
  final GroqApiService _groqApi;
  final GeminiApiService _geminiApi;

  const CloudConnectivityChecker({
    required CloudApiKeyStorage keyStorage,
    required GroqApiService groqApi,
    required GeminiApiService geminiApi,
  })  : _keyStorage = keyStorage,
        _groqApi = groqApi,
        _geminiApi = geminiApi;

  /// Check if the given cloud LLM provider is ready to use.
  Future<CloudStatus> checkProvider(CloudLLMProvider provider) async {
    switch (provider) {
      case CloudLLMProvider.groq:
        return _checkGroq();
      case CloudLLMProvider.gemini:
        return _checkGemini();
    }
  }

  /// Check if at least one cloud provider is ready.
  Future<CloudStatus> checkAny() async {
    final groq = await _checkGroq();
    if (groq.isReady) return groq;
    return _checkGemini();
  }

  Future<CloudStatus> _checkGroq() async {
    final key = await _keyStorage.getGroqApiKey();
    if (key == null || key.isEmpty) {
      return const CloudStatus(hasApiKey: false, isReachable: false);
    }

    try {
      final valid = await _groqApi.validateApiKey(key);
      return CloudStatus(hasApiKey: true, isReachable: valid);
    } catch (e) {
      AppLogger.e('CloudConnectivityChecker: Groq check failed: $e');
      return CloudStatus(
        hasApiKey: true,
        isReachable: false,
        error: e.toString(),
      );
    }
  }

  Future<CloudStatus> _checkGemini() async {
    final key = await _keyStorage.getGeminiApiKey();
    if (key == null || key.isEmpty) {
      return const CloudStatus(hasApiKey: false, isReachable: false);
    }

    try {
      final valid = await _geminiApi.validateApiKey(key);
      return CloudStatus(hasApiKey: true, isReachable: valid);
    } catch (e) {
      AppLogger.e('CloudConnectivityChecker: Gemini check failed: $e');
      return CloudStatus(
        hasApiKey: true,
        isReachable: false,
        error: e.toString(),
      );
    }
  }
}
