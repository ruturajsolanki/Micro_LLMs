part of 'voice_bloc.dart';

/// Base class for voice events.
sealed class VoiceEvent extends Equatable {
  const VoiceEvent();
  
  @override
  List<Object?> get props => [];
}

/// Start speech recognition.
final class VoiceRecognitionStarted extends VoiceEvent {
  final SpeechToTextEngine engine;
  final String language;
  final bool offlineOnly;
  final String whisperModelId;
  
  const VoiceRecognitionStarted({
    required this.engine,
    required this.language,
    this.offlineOnly = false,
    this.whisperModelId = 'small',
  });
  
  @override
  List<Object?> get props => [engine, language, offlineOnly, whisperModelId];
}

/// Stop speech recognition.
final class VoiceRecognitionStopped extends VoiceEvent {
  const VoiceRecognitionStopped();
}

/// Recognition session ended (internal).
///
/// This is emitted when the platform recognizer reports it has stopped
/// (or the stream completes). It must not call platform stop/cancel again.
final class VoiceRecognitionEnded extends VoiceEvent {
  const VoiceRecognitionEnded();
}

/// Recognition result received (internal event).
final class VoiceRecognitionResultReceived extends VoiceEvent {
  final String text;
  final bool isFinal;
  final double confidence;
  final double? levelDb;
  
  const VoiceRecognitionResultReceived({
    required this.text,
    required this.isFinal,
    required this.confidence,
    this.levelDb,
  });
  
  @override
  List<Object?> get props => [text, isFinal, confidence, levelDb];
}

/// Recognition failed (internal event).
final class VoiceRecognitionFailed extends VoiceEvent {
  final String error;
  
  const VoiceRecognitionFailed({required this.error});
  
  @override
  List<Object> get props => [error];
}

/// Start text-to-speech synthesis.
final class VoiceSynthesisStarted extends VoiceEvent {
  final TextToSpeechEngine engine;
  final String text;
  final String language;
  final String? elevenLabsVoiceId;
  
  const VoiceSynthesisStarted({
    required this.engine,
    required this.text,
    required this.language,
    this.elevenLabsVoiceId,
  });
  
  @override
  List<Object?> get props => [engine, text, language, elevenLabsVoiceId];
}

/// Stop text-to-speech synthesis.
final class VoiceSynthesisStopped extends VoiceEvent {
  const VoiceSynthesisStopped();
}

/// TTS completed callback from platform.
final class VoiceSynthesisCompleted extends VoiceEvent {
  const VoiceSynthesisCompleted();
}

/// TTS failed callback from platform.
final class VoiceSynthesisFailed extends VoiceEvent {
  final String error;

  const VoiceSynthesisFailed({required this.error});

  @override
  List<Object> get props => [error];
}
