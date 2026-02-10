import 'package:equatable/equatable.dart';
import '../../core/constants/app_constants.dart';
import 'speech_to_text_engine.dart';
import 'text_to_speech_engine.dart';

/// Application settings entity.
/// 
/// Encapsulates all user-configurable settings. Settings are persisted
/// locally and never sent over the network.
class AppSettings extends Equatable {
  /// Source language for user input.
  final String sourceLanguage;
  
  /// Target language for translations.
  final String targetLanguage;
  
  /// Whether voice input is enabled.
  final bool voiceInputEnabled;
  
  /// Whether voice output (TTS) is enabled.
  final bool voiceOutputEnabled;

  /// If true, speech-to-text will never fall back to online recognition.
  ///
  /// This prevents "network error" when the device is offline, but requires
  /// an offline speech pack to be installed for the selected language on
  /// the device's speech recognizer.
  final bool voiceSttOfflineOnly;

  /// Which STT engine to use.
  ///
  /// Note: `SpeechToTextEngine.whisperCpp` is true offline STT (no network, no SpeechRecognizer).
  final SpeechToTextEngine speechToTextEngine;

  /// Selected Whisper model ID (e.g., "small", "base").
  ///
  /// The actual file path is resolved from this ID in the data layer.
  final String whisperModelId;

  /// Which TTS engine to use.
  final TextToSpeechEngine textToSpeechEngine;

  /// ElevenLabs voice id (used when textToSpeechEngine == elevenLabs).
  final String elevenLabsVoiceId;
  
  /// LLM temperature (0.0 = deterministic, 1.0 = creative).
  final double temperature;
  
  /// Context window size override (null = use model default).
  final int? contextWindowSize;
  
  /// Maximum tokens to generate per response.
  final int maxGenerationTokens;
  
  /// Number of threads for inference.
  final int inferenceThreads;
  
  /// Whether to auto-detect input language.
  final bool autoDetectLanguage;
  
  /// Theme mode preference.
  final ThemePreference themePreference;
  
  /// Selected model file path (null = use default model).
  final String? selectedModelPath;

  /// Whether to show token count in UI.
  final bool showTokenCount;
  
  /// Whether to keep screen on during inference.
  final bool keepScreenOn;
  
  const AppSettings({
    this.sourceLanguage = LanguageConstants.defaultSourceLanguage,
    this.targetLanguage = LanguageConstants.defaultTargetLanguage,
    this.voiceInputEnabled = false,
    this.voiceOutputEnabled = false,
    this.voiceSttOfflineOnly = true,
    this.speechToTextEngine = SpeechToTextEngine.androidSpeechRecognizer,
    this.whisperModelId = 'small',
    this.textToSpeechEngine = TextToSpeechEngine.androidTts,
    this.elevenLabsVoiceId = 'JBFqnCBsd6RMkjVDRZzb',
    this.temperature = 0.7,
    this.contextWindowSize,
    this.maxGenerationTokens = ModelConstants.maxGenerationTokens,
    this.inferenceThreads = ModelConstants.maxInferenceThreads,
    this.autoDetectLanguage = true,
    this.themePreference = ThemePreference.system,
    this.selectedModelPath,
    this.showTokenCount = false,
    this.keepScreenOn = true,
  });
  
  /// Default settings.
  factory AppSettings.defaults() => const AppSettings();
  
  /// Create a copy with updated fields.
  AppSettings copyWith({
    String? sourceLanguage,
    String? targetLanguage,
    bool? voiceInputEnabled,
    bool? voiceOutputEnabled,
    bool? voiceSttOfflineOnly,
    SpeechToTextEngine? speechToTextEngine,
    String? whisperModelId,
    TextToSpeechEngine? textToSpeechEngine,
    String? elevenLabsVoiceId,
    double? temperature,
    int? contextWindowSize,
    int? maxGenerationTokens,
    int? inferenceThreads,
    bool? autoDetectLanguage,
    ThemePreference? themePreference,
    String? selectedModelPath,
    bool? showTokenCount,
    bool? keepScreenOn,
  }) {
    return AppSettings(
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      voiceInputEnabled: voiceInputEnabled ?? this.voiceInputEnabled,
      voiceOutputEnabled: voiceOutputEnabled ?? this.voiceOutputEnabled,
      voiceSttOfflineOnly: voiceSttOfflineOnly ?? this.voiceSttOfflineOnly,
      speechToTextEngine: speechToTextEngine ?? this.speechToTextEngine,
      whisperModelId: whisperModelId ?? this.whisperModelId,
      textToSpeechEngine: textToSpeechEngine ?? this.textToSpeechEngine,
      elevenLabsVoiceId: elevenLabsVoiceId ?? this.elevenLabsVoiceId,
      temperature: temperature ?? this.temperature,
      contextWindowSize: contextWindowSize ?? this.contextWindowSize,
      maxGenerationTokens: maxGenerationTokens ?? this.maxGenerationTokens,
      inferenceThreads: inferenceThreads ?? this.inferenceThreads,
      autoDetectLanguage: autoDetectLanguage ?? this.autoDetectLanguage,
      themePreference: themePreference ?? this.themePreference,
      selectedModelPath: selectedModelPath ?? this.selectedModelPath,
      showTokenCount: showTokenCount ?? this.showTokenCount,
      keepScreenOn: keepScreenOn ?? this.keepScreenOn,
    );
  }
  
  /// Validate settings are within acceptable ranges.
  bool get isValid {
    return temperature >= 0.0 &&
        temperature <= 2.0 &&
        maxGenerationTokens > 0 &&
        maxGenerationTokens <= 2048 &&
        inferenceThreads >= 1 &&
        inferenceThreads <= 8 &&
        LanguageConstants.supportedLanguages.containsKey(sourceLanguage) &&
        LanguageConstants.supportedLanguages.containsKey(targetLanguage);
  }
  
  /// Get source language display name.
  String get sourceLanguageDisplayName =>
      LanguageConstants.supportedLanguages[sourceLanguage] ?? sourceLanguage;
  
  /// Get target language display name.
  String get targetLanguageDisplayName =>
      LanguageConstants.supportedLanguages[targetLanguage] ?? targetLanguage;
  
  @override
  List<Object?> get props => [
    sourceLanguage,
    targetLanguage,
    voiceInputEnabled,
    voiceOutputEnabled,
    voiceSttOfflineOnly,
    speechToTextEngine,
    whisperModelId,
    textToSpeechEngine,
    elevenLabsVoiceId,
    temperature,
    contextWindowSize,
    maxGenerationTokens,
    inferenceThreads,
    autoDetectLanguage,
    themePreference,
    selectedModelPath,
    showTokenCount,
    keepScreenOn,
  ];
}

/// Theme preference options.
enum ThemePreference {
  /// Follow system theme.
  system,
  
  /// Always use light theme.
  light,
  
  /// Always use dark theme.
  dark,
}

/// Extension for ThemePreference display.
extension ThemePreferenceExtension on ThemePreference {
  String get displayName {
    switch (this) {
      case ThemePreference.system:
        return 'System';
      case ThemePreference.light:
        return 'Light';
      case ThemePreference.dark:
        return 'Dark';
    }
  }
}
