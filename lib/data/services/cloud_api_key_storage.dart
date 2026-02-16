import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/utils/logger.dart';

/// Securely stores and retrieves cloud API keys.
///
/// A default Groq key is embedded in the app. If the user hasn't set their
/// own key, the default is returned by [getGroqApiKey]. If the default key
/// stops working (quota / revoked), the app prompts the user to enter their
/// own via the API-setup page.
class CloudApiKeyStorage {
  static const String _groqKeyName = 'cloud_groq_api_key';
  static const String _geminiKeyName = 'cloud_gemini_api_key';

  /// Built-in Groq API key used out-of-the-box.
  static const String _defaultGroqKey =
      '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';

  final FlutterSecureStorage _secureStorage;

  const CloudApiKeyStorage({required FlutterSecureStorage secureStorage})
      : _secureStorage = secureStorage;

  // ── Groq ──────────────────────────────────────────────────────────

  /// Returns the user-configured Groq key, falling back to the built-in
  /// default if no custom key has been saved.
  Future<String?> getGroqApiKey() async {
    try {
      final userKey = await _secureStorage.read(key: _groqKeyName);
      if (userKey != null && userKey.isNotEmpty) return userKey;
      return _defaultGroqKey;
    } catch (e) {
      AppLogger.e('CloudApiKeyStorage: failed to read Groq key: $e');
      return _defaultGroqKey;
    }
  }

  /// Returns only the user-set key (ignores the default).
  Future<String?> getUserGroqApiKey() async {
    try {
      return await _secureStorage.read(key: _groqKeyName);
    } catch (e) {
      return null;
    }
  }

  /// Whether the current effective key is the built-in default.
  Future<bool> isUsingDefaultGroqKey() async {
    final userKey = await getUserGroqApiKey();
    return userKey == null || userKey.isEmpty;
  }

  Future<void> setGroqApiKey(String apiKey) async {
    await _secureStorage.write(key: _groqKeyName, value: apiKey);
  }

  Future<void> deleteGroqApiKey() async {
    await _secureStorage.delete(key: _groqKeyName);
  }

  Future<bool> hasGroqApiKey() async {
    final key = await getGroqApiKey();
    return key != null && key.isNotEmpty;
  }

  /// The embedded default key string (for display / info purposes).
  String get defaultGroqKey => _defaultGroqKey;

  // ── Gemini ────────────────────────────────────────────────────────

  Future<String?> getGeminiApiKey() async {
    try {
      return await _secureStorage.read(key: _geminiKeyName);
    } catch (e) {
      AppLogger.e('CloudApiKeyStorage: failed to read Gemini key: $e');
      return null;
    }
  }

  Future<void> setGeminiApiKey(String apiKey) async {
    await _secureStorage.write(key: _geminiKeyName, value: apiKey);
  }

  Future<void> deleteGeminiApiKey() async {
    await _secureStorage.delete(key: _geminiKeyName);
  }

  Future<bool> hasGeminiApiKey() async {
    final key = await getGeminiApiKey();
    return key != null && key.isNotEmpty;
  }

  // ── Convenience ───────────────────────────────────────────────────

  /// Always returns true because the default Groq key is embedded.
  Future<bool> hasAnyApiKey() async {
    return true;
  }
}
