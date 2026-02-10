import '../../core/utils/result.dart';
import '../entities/speech_to_text_engine.dart';
import '../entities/text_to_speech_engine.dart';

/// Repository interface for voice operations (STT/TTS).
/// 
/// Abstracts the platform-specific voice APIs (Android SpeechRecognizer,
/// TextToSpeech) behind a unified interface.
abstract class VoiceRepository {
  /// Check if speech-to-text is available on this device.
  AsyncResult<bool> isSpeechRecognitionAvailable();
  
  /// Check if text-to-speech is available on this device.
  AsyncResult<bool> isTextToSpeechAvailable();
  
  /// Get list of available STT languages.
  AsyncResult<List<VoiceLanguage>> getAvailableRecognitionLanguages();
  
  /// Get list of available TTS languages.
  AsyncResult<List<VoiceLanguage>> getAvailableSynthesisLanguages();
  
  /// Start speech recognition.
  /// 
  /// Returns a stream of recognition results. The stream will emit:
  /// - Partial results as the user speaks
  /// - Final result when speech ends
  /// 
  /// Parameters:
  /// - [language]: Language code for recognition (e.g., "en-US")
  /// - [continuous]: Whether to keep listening for multiple utterances
  /// - [preferOffline]: Prefer offline recognition if available
  /// - [offlineOnly]: If true, never fall back to online recognition
  Stream<SpeechRecognitionResult> startRecognition({
    required SpeechToTextEngine engine,
    required String language,
    bool continuous = false,
    bool preferOffline = true,
    bool offlineOnly = false,
    int whisperThreads = 4,
  });

  /// Check if whisper.cpp STT is available in this build.
  AsyncResult<bool> isWhisperAvailable();

  /// Ensure a Whisper model is loaded (no-op if already loaded).
  AsyncResult<bool> loadWhisperModel({
    required String modelPath,
    required int threads,
  });

  /// Unload Whisper model to free RAM.
  Future<void> unloadWhisperModel();

  /// Returns true if Whisper model is loaded.
  AsyncResult<bool> isWhisperModelLoaded();
  
  /// Stop ongoing speech recognition.
  Future<void> stopRecognition();
  
  /// Cancel speech recognition without processing.
  Future<void> cancelRecognition();
  
  /// Synthesize text to speech.
  /// 
  /// Returns when speech synthesis starts. Use [stopSynthesis] to stop.
  /// 
  /// Parameters:
  /// - [text]: Text to synthesize
  /// - [language]: Language code for synthesis (e.g., "en-US")
  /// - [pitch]: Pitch multiplier (0.5-2.0, default 1.0)
  /// - [rate]: Speech rate multiplier (0.5-2.0, default 1.0)
  AsyncResult<void> synthesize({
    required TextToSpeechEngine engine,
    required String text,
    required String language,
    String? elevenLabsVoiceId,
    double pitch = 1.0,
    double rate = 1.0,
  });
  
  /// Stop ongoing speech synthesis.
  Future<void> stopSynthesis();

  /// Store ElevenLabs API key securely (device keystore-backed).
  AsyncResult<void> setElevenLabsApiKey(String apiKey);

  /// Read ElevenLabs API key (null if not set).
  AsyncResult<String?> getElevenLabsApiKey();

  /// Stream of TTS lifecycle callbacks from the platform.
  ///
  /// Why:
  /// - Enables "voice call mode" turn-taking (auto-listen after TTS completes)
  /// - Lets UI accurately reflect speaking state
  Stream<SpeechSynthesisEvent> get synthesisEvents;
  
  /// Check if speech synthesis is currently active.
  bool get isSpeaking;
  
  /// Check if speech recognition is currently active.
  bool get isListening;
}

/// Speech synthesis lifecycle events from the platform.
sealed class SpeechSynthesisEvent {
  const SpeechSynthesisEvent();
}

/// Fired when the platform reports TTS has completed.
final class SpeechSynthesisCompleted extends SpeechSynthesisEvent {
  const SpeechSynthesisCompleted();
}

/// Fired when the platform reports a TTS error.
final class SpeechSynthesisError extends SpeechSynthesisEvent {
  final String message;

  const SpeechSynthesisError(this.message);
}

/// Result of speech recognition.
class SpeechRecognitionResult {
  /// The recognized text.
  final String text;
  
  /// Confidence level (0.0-1.0).
  final double confidence;
  
  /// Whether this is a final result or partial.
  final bool isFinal;
  
  /// Alternative transcriptions.
  final List<String> alternatives;

  /// Optional input level (RMS dB) for UI animations.
  /// This is device/engine-specific and may be null.
  final double? levelDb;
  
  const SpeechRecognitionResult({
    required this.text,
    required this.confidence,
    required this.isFinal,
    this.alternatives = const [],
    this.levelDb,
  });
  
  /// Returns true if confidence is high enough to use.
  bool get isReliable => confidence > 0.7;
  
  @override
  String toString() =>
      'SpeechRecognitionResult(text: $text, confidence: $confidence, isFinal: $isFinal, levelDb: $levelDb)';
}

/// Represents a language available for voice operations.
class VoiceLanguage {
  /// Language code (e.g., "en-US").
  final String code;
  
  /// Display name (e.g., "English (United States)").
  final String displayName;
  
  /// Whether this is the device's default language.
  final bool isDefault;
  
  const VoiceLanguage({
    required this.code,
    required this.displayName,
    this.isDefault = false,
  });
  
  /// Get the base language code (e.g., "en" from "en-US").
  String get baseCode => code.split('-').first;
  
  @override
  String toString() => 'VoiceLanguage($code)';
}

/// Events for voice operation status.
enum VoiceStatus {
  /// Idle, ready to start.
  idle,
  
  /// Listening for speech input.
  listening,
  
  /// Processing speech input.
  processing,
  
  /// Speaking (TTS active).
  speaking,
  
  /// Error occurred.
  error,
}
