import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../repositories/voice_repository.dart';
import '../entities/text_to_speech_engine.dart';
import '../../core/utils/result.dart';
import '../../core/error/failures.dart';
import 'usecase.dart';

/// Use case for text-to-speech synthesis.
/// 
/// Provides a clean interface for the presentation layer to synthesize speech.
class TextToSpeechUseCase extends UseCase<void, TextToSpeechParams> {
  final VoiceRepository _voiceRepository;
  
  TextToSpeechUseCase({
    required VoiceRepository voiceRepository,
  }) : _voiceRepository = voiceRepository;
  
  @override
  AsyncResult<void> call(TextToSpeechParams params) async {
    // Engine-specific availability checks.
    if (params.engine == TextToSpeechEngine.androidTts) {
      final availabilityResult = await _voiceRepository.isTextToSpeechAvailable();
      final isAvailable = availabilityResult.fold((_) => false, (a) => a);
      if (!isAvailable) {
        return Left(VoiceFailure.ttsUnavailable());
      }
    } else {
      final keyResult = await _voiceRepository.getElevenLabsApiKey();
      final hasKey = keyResult.fold((_) => false, (k) => (k?.trim().isNotEmpty ?? false));
      if (!hasKey) {
        return const Left(VoiceFailure(
          message: 'ElevenLabs API key is not set. Add it in Settings → Voice.',
          type: VoiceFailureType.synthesisError,
        ));
      }
    }
    
    // Validate input
    if (params.text.trim().isEmpty) {
      return const Left(VoiceFailure(
        message: 'Text to speak cannot be empty',
        type: VoiceFailureType.synthesisError,
      ));
    }

    // Language support check is only meaningful for Android TTS.
    String effectiveLanguage = params.language.replaceAll('_', '-');
    if (params.engine == TextToSpeechEngine.androidTts) {
      final languagesResult =
          await _voiceRepository.getAvailableSynthesisLanguages();
      final languages = languagesResult.fold(
        (failure) => <VoiceLanguage>[],
        (langs) => langs,
      );

      final languageSupported = languages.any(
        (lang) => lang.code == params.language || lang.baseCode == params.language,
      );

      if (!languageSupported && languages.isNotEmpty) {
        return Left(VoiceFailure.languageNotSupported(params.language));
      }

      effectiveLanguage = _pickBestLanguageTag(
        requested: params.language,
        available: languages,
      );
    }

    return _voiceRepository.synthesize(
      engine: params.engine,
      text: params.text,
      language: effectiveLanguage,
      elevenLabsVoiceId: params.elevenLabsVoiceId,
      pitch: params.pitch,
      rate: params.rate,
    );
  }

  String _pickBestLanguageTag({
    required String requested,
    required List<VoiceLanguage> available,
  }) {
    if (requested.contains('-') || requested.contains('_')) {
      return requested.replaceAll('_', '-');
    }

    final match = available.cast<VoiceLanguage?>().firstWhere(
          (l) => l != null && l.baseCode == requested,
          orElse: () => null,
        );

    return match?.code ?? requested;
  }
  
  /// Stop ongoing synthesis.
  Future<void> stop() async {
    await _voiceRepository.stopSynthesis();
  }

  /// Platform TTS lifecycle events (complete/error).
  Stream<SpeechSynthesisEvent> get events => _voiceRepository.synthesisEvents;
  
  /// Check if currently speaking.
  bool get isSpeaking => _voiceRepository.isSpeaking;
}

/// Parameters for text-to-speech.
class TextToSpeechParams extends Equatable {
  /// Text to synthesize.
  final String text;
  
  /// Language code (e.g., "en-US").
  final String language;
  
  /// Pitch multiplier (0.5-2.0).
  final double pitch;
  
  /// Speech rate multiplier (0.5-2.0).
  final double rate;

  /// Which TTS engine to use.
  final TextToSpeechEngine engine;

  /// ElevenLabs voice id (required when engine == elevenLabs).
  final String? elevenLabsVoiceId;
  
  const TextToSpeechParams({
    required this.text,
    required this.language,
    this.pitch = 1.0,
    this.rate = 1.0,
    this.engine = TextToSpeechEngine.androidTts,
    this.elevenLabsVoiceId,
  });
  
  @override
  List<Object?> get props => [text, language, pitch, rate, engine, elevenLabsVoiceId];
}
