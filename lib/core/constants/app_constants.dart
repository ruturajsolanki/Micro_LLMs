/// Application-wide constants.
/// 
/// Centralized to ensure consistency and easy modification.
/// All values are compile-time constants where possible for performance.
library;

/// Model configuration constants.
/// 
/// Default: Qwen2.5-1.5B-Instruct - excellent balance of quality & mobile performance
/// - 1.5B parameters, ~1GB file size (Q4_K_M quantization)
/// - Multilingual: English, Chinese, Japanese, Korean, Spanish, French, German, Russian, Arabic
/// - Needs ~3GB available RAM (works on most phones with 4GB+ total RAM)
/// - Much better quality than tiny models, still mobile-friendly
abstract final class ModelConstants {
  /// Default model filename stored in app sandbox.
  static const String defaultModelFilename = 'qwen2.5-1.5b-instruct-q4_k_m.gguf';
  
  /// Model download URL (HuggingFace).
  /// Qwen2.5-1.5B: Best balance of quality, size, and multilingual support.
  static const String modelDownloadUrl = 
      'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf';
  
  /// Expected model file size in bytes (~1GB).
  /// Used for download progress and validation.
  static const int expectedModelSizeBytes = 1050000000; // ~1GB
  
  /// SHA256 hash of the model file for integrity verification.
  static const String modelSha256 = ''; // Will be computed on first download
  
  /// Context window size in tokens.
  /// Qwen2.5 supports up to 32K, limited to 2048 for memory.
  static const int contextWindowSize = 2048;
  
  /// Maximum tokens to generate per response.
  static const int maxGenerationTokens = 512;
  
  /// Number of CPU threads for inference.
  /// Auto-detected at runtime, but capped for thermal management.
  static const int maxInferenceThreads = 4;
  
  /// Batch size for prompt processing.
  /// Smaller batches = less memory, slower processing.
  static const int promptBatchSize = 512;
  
  /// Memory threshold (bytes) below which we refuse to run inference.
  /// Prevents OOM crashes on low-memory devices.
  static const int minAvailableMemoryBytes = 512 * 1024 * 1024; // 512MB
  
  /// Minimum RAM required for the default model (Qwen2.5-1.5B).
  static const int minRequiredRamBytes = 3 * 1024 * 1024 * 1024; // 3GB
}

/// Prompt template constants.
/// 
/// Phi-2 uses a specific prompt format for best results.
/// These templates are loaded from assets but defaults are here.
abstract final class PromptConstants {
  /// System prompt establishing assistant behavior.
  /// Note: Qwen models need explicit language instructions.
  static const String systemPrompt = '''
You are a helpful AI assistant. You MUST respond in English only unless specifically asked to translate or respond in another language. Be helpful, accurate, and concise.
''';

  /// System prompt with explicit language instruction.
  static String systemPromptWithLanguage(String language) => '''
You are a helpful AI assistant. You MUST respond in $language only. Be helpful, accurate, and concise.
''';

  /// Template for translation requests.
  static const String translationTemplate = '''
Translate the following text from {source_lang} to {target_lang}.
Only output the translation, nothing else.

Text: {text}

Translation:''';

  /// Template for explanation requests.
  static const String explanationTemplate = '''
Explain the following {source_lang} text in {target_lang}.
Provide meaning, usage context, and any cultural notes if relevant.

Text: {text}

Explanation:''';

  /// Phi-2 instruction format.
  static const String instructionPrefix = 'Instruct: ';
  static const String outputPrefix = 'Output: ';
}

/// Supported languages for UI and translation.
abstract final class LanguageConstants {
  static const Map<String, String> supportedLanguages = {
    'en': 'English',
    'es': 'Spanish',
    'fr': 'French',
    'de': 'German',
    'it': 'Italian',
    'pt': 'Portuguese',
    'zh': 'Chinese',
    'ja': 'Japanese',
    'ko': 'Korean',
    'ar': 'Arabic',
    'hi': 'Hindi',
    'ru': 'Russian',
  };
  
  static const String defaultSourceLanguage = 'en';
  static const String defaultTargetLanguage = 'es';
}

/// Storage keys for secure and regular storage.
abstract final class StorageConstants {
  /// Hive box names
  static const String settingsBox = 'settings';
  static const String conversationBox = 'conversations';
  static const String modelMetadataBox = 'model_metadata';
  
  /// Secure storage keys
  static const String encryptionKeyKey = 'encryption_key';
  static const String modelChecksumKey = 'model_checksum';
  
  /// Settings keys
  static const String sourceLanguageKey = 'source_language';
  static const String targetLanguageKey = 'target_language';
  static const String voiceEnabledKey = 'voice_enabled';
  static const String contextWindowKey = 'context_window';
  static const String temperatureKey = 'temperature';
}

/// UI-related constants.
abstract final class UIConstants {
  static const double maxChatBubbleWidth = 0.8; // 80% of screen width
  static const int messageCharacterLimit = 4000;
  static const Duration typingIndicatorDelay = Duration(milliseconds: 100);
  static const Duration snackBarDuration = Duration(seconds: 3);
}
