import 'package:equatable/equatable.dart';

import '../repositories/voice_repository.dart';
import '../entities/speech_to_text_engine.dart';
import '../services/stt_model_path_resolver.dart';
import '../../core/utils/result.dart';
import '../../core/error/failures.dart';
import 'usecase.dart';

/// Use case for speech-to-text conversion.
/// 
/// Wraps the voice repository to provide a clean API for the presentation layer.
/// Handles availability checks and error translation.
class SpeechToTextUseCase 
    extends StreamUseCase<SpeechToTextEvent, SpeechToTextParams> {
  final VoiceRepository _voiceRepository;
  final SttModelPathResolver _sttModelPathResolver;
  
  SpeechToTextUseCase({
    required VoiceRepository voiceRepository,
    required SttModelPathResolver sttModelPathResolver,
  })  : _voiceRepository = voiceRepository,
        _sttModelPathResolver = sttModelPathResolver;
  
  @override
  Stream<SpeechToTextEvent> call(SpeechToTextParams params) async* {
    final engine = params.engine;

    // Availability checks differ per engine.
    List<VoiceLanguage> languages = const [];
    if (engine == SpeechToTextEngine.androidSpeechRecognizer) {
      final availabilityResult = await _voiceRepository.isSpeechRecognitionAvailable();
      final isAvailable = availabilityResult.fold((_) => false, (v) => v);
      if (!isAvailable) {
        yield const SpeechToTextError(
          message: 'Speech recognition is not available on this device',
          isRecoverable: false,
        );
        return;
      }

      // Check language support (SpeechRecognizer only; Whisper supports multilingual via model).
      final languagesResult = await _voiceRepository.getAvailableRecognitionLanguages();
      languages = languagesResult.fold((_) => <VoiceLanguage>[], (langs) => langs);

      final languageSupported = languages.any(
        (lang) => lang.code == params.language || lang.baseCode == params.language,
      );

      if (!languageSupported && languages.isNotEmpty) {
        yield SpeechToTextError(
          message: 'Language "${params.language}" is not supported for speech recognition',
          isRecoverable: false,
        );
        return;
      }
    } else {
      final availabilityResult = await _voiceRepository.isWhisperAvailable();
      final isAvailable = availabilityResult.fold((_) => false, (v) => v);
      if (!isAvailable) {
        yield const SpeechToTextError(
          message: 'Whisper STT is not available in this build (native whisper.cpp missing)',
          isRecoverable: false,
        );
        return;
      }

      final modelId = params.whisperModelId;
      final modelPath = await _sttModelPathResolver.resolveWhisperModelPath(modelId);
      if (modelPath == null || modelPath.isEmpty) {
        yield const SpeechToTextError(
          message: 'Whisper model not downloaded. Download it in Settings first.',
          isRecoverable: false,
        );
        return;
      }

      // Load model if needed.
      final loadedResult = await _voiceRepository.isWhisperModelLoaded();
      final alreadyLoaded = loadedResult.fold((_) => false, (v) => v);
      if (!alreadyLoaded) {
        final loadResult = await _voiceRepository.loadWhisperModel(
          modelPath: modelPath,
          threads: params.whisperThreads,
        );
        final ok = loadResult.fold((_) => false, (v) => v);
        if (!ok) {
          yield const SpeechToTextError(
            message: 'Failed to load Whisper model',
            isRecoverable: false,
          );
          return;
        }
      }
    }

    // Signal that we're starting to listen
    yield const SpeechToTextListening();
    
    // Pick a concrete BCP-47 language tag if caller passed base code (e.g. "en")
    final effectiveLanguage = engine == SpeechToTextEngine.androidSpeechRecognizer
        ? _pickBestLanguageTag(
            requested: params.language,
            available: languages,
          )
        : params.language.replaceAll('_', '-');

    // Start recognition and forward results.
    // Prefer offline when possible (faster, no network needed).
    // If the offline pack is missing, the datasource auto-falls back to online.
    try {
      await for (final result in _voiceRepository.startRecognition(
        engine: engine,
        language: effectiveLanguage,
        continuous: params.continuous,
        preferOffline: true,
        offlineOnly: params.offlineOnly,
        whisperThreads: params.whisperThreads,
      )) {
        yield SpeechToTextResult(
          text: result.text,
          confidence: result.confidence,
          isFinal: result.isFinal,
          alternatives: result.alternatives,
          levelDb: result.levelDb,
        );
      }
      
      // Recognition ended normally
      yield const SpeechToTextStopped();
    } catch (e) {
      yield SpeechToTextError(
        message: 'Speech recognition error: $e',
        isRecoverable: true,
      );
    }
  }

  String _pickBestLanguageTag({
    required String requested,
    required List<VoiceLanguage> available,
  }) {
    // Already a full BCP-47 tag (e.g. "en-IN") — use as-is.
    if (requested.contains('-') || requested.contains('_')) {
      return requested.replaceAll('_', '-');
    }

    // Base code (e.g. "en") — prefer the device-default variant first.
    // The native side lists the device locale first, so the default
    // variant (e.g. en-IN on an Indian device) gets matched before en-US.
    final defaultMatch = available.cast<VoiceLanguage?>().firstWhere(
          (l) => l != null && l.baseCode == requested && l.isDefault,
          orElse: () => null,
        );
    if (defaultMatch != null) return defaultMatch.code;

    // Fallback: any variant of the requested base language.
    final anyMatch = available.cast<VoiceLanguage?>().firstWhere(
          (l) => l != null && l.baseCode == requested,
          orElse: () => null,
        );

    return anyMatch?.code ?? requested;
  }
  
  /// Stop ongoing recognition.
  Future<void> stop() async {
    await _voiceRepository.stopRecognition();
  }
  
  /// Cancel recognition without processing.
  Future<void> cancel() async {
    await _voiceRepository.cancelRecognition();
  }
  
  /// Check if currently listening.
  bool get isListening => _voiceRepository.isListening;
}

/// Parameters for speech-to-text.
class SpeechToTextParams extends Equatable {
  /// Language code for recognition (e.g., "en-US").
  final String language;
  
  /// Whether to continue listening for multiple utterances.
  final bool continuous;

  /// If true, never fall back to online recognition.
  final bool offlineOnly;

  /// Selected STT engine.
  final SpeechToTextEngine engine;

  /// Whisper model ID (required if engine == whisperCpp).
  final String whisperModelId;

  /// Threads to use for Whisper decode.
  final int whisperThreads;
  
  const SpeechToTextParams({
    required this.language,
    this.continuous = false,
    this.offlineOnly = false,
    this.engine = SpeechToTextEngine.androidSpeechRecognizer,
    this.whisperModelId = 'small',
    this.whisperThreads = 4,
  });
  
  @override
  List<Object?> get props => [
        language,
        continuous,
        offlineOnly,
        engine,
        whisperModelId,
        whisperThreads,
      ];
}

/// Events emitted during speech-to-text.
sealed class SpeechToTextEvent {
  const SpeechToTextEvent();
}

/// Speech recognition has started listening.
final class SpeechToTextListening extends SpeechToTextEvent {
  const SpeechToTextListening();
}

/// A recognition result (partial or final).
final class SpeechToTextResult extends SpeechToTextEvent {
  final String text;
  final double confidence;
  final bool isFinal;
  final List<String> alternatives;
  final double? levelDb;
  
  const SpeechToTextResult({
    required this.text,
    required this.confidence,
    required this.isFinal,
    this.alternatives = const [],
    this.levelDb,
  });
}

/// Speech recognition has stopped.
final class SpeechToTextStopped extends SpeechToTextEvent {
  const SpeechToTextStopped();
}

/// An error occurred during speech recognition.
final class SpeechToTextError extends SpeechToTextEvent {
  final String message;
  final bool isRecoverable;
  
  const SpeechToTextError({
    required this.message,
    required this.isRecoverable,
  });
}
