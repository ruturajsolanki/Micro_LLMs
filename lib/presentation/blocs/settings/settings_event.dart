part of 'settings_bloc.dart';

/// Base class for settings events.
sealed class SettingsEvent extends Equatable {
  const SettingsEvent();
  
  @override
  List<Object?> get props => [];
}

/// Load settings from storage.
final class SettingsLoadRequested extends SettingsEvent {
  const SettingsLoadRequested();
}

/// Update all settings.
final class SettingsUpdated extends SettingsEvent {
  final AppSettings settings;
  
  const SettingsUpdated({required this.settings});
  
  @override
  List<Object> get props => [settings];
}

/// Reset settings to defaults.
final class SettingsResetRequested extends SettingsEvent {
  const SettingsResetRequested();
}

/// Change source language.
final class SourceLanguageChanged extends SettingsEvent {
  final String language;
  
  const SourceLanguageChanged({required this.language});
  
  @override
  List<Object> get props => [language];
}

/// Change target language.
final class TargetLanguageChanged extends SettingsEvent {
  final String language;
  
  const TargetLanguageChanged({required this.language});
  
  @override
  List<Object> get props => [language];
}

/// Toggle voice input.
final class VoiceInputToggled extends SettingsEvent {
  const VoiceInputToggled();
}

/// Toggle voice output.
final class VoiceOutputToggled extends SettingsEvent {
  const VoiceOutputToggled();
}

/// Toggle offline-only speech recognition (no online fallback).
final class VoiceSttOfflineOnlyToggled extends SettingsEvent {
  const VoiceSttOfflineOnlyToggled();
}

/// Change STT engine.
final class SpeechToTextEngineChanged extends SettingsEvent {
  final SpeechToTextEngine engine;

  const SpeechToTextEngineChanged({required this.engine});

  @override
  List<Object> get props => [engine];
}

/// Change Whisper model selection.
final class WhisperModelChanged extends SettingsEvent {
  final String modelId;

  const WhisperModelChanged({required this.modelId});

  @override
  List<Object> get props => [modelId];
}

/// Change TTS engine.
final class TextToSpeechEngineChanged extends SettingsEvent {
  final TextToSpeechEngine engine;

  const TextToSpeechEngineChanged({required this.engine});

  @override
  List<Object> get props => [engine];
}

/// Change ElevenLabs voice id.
final class ElevenLabsVoiceChanged extends SettingsEvent {
  final String voiceId;

  const ElevenLabsVoiceChanged({required this.voiceId});

  @override
  List<Object> get props => [voiceId];
}

/// Change temperature setting.
final class TemperatureChanged extends SettingsEvent {
  final double temperature;
  
  const TemperatureChanged({required this.temperature});
  
  @override
  List<Object> get props => [temperature];
}

/// Change theme preference.
final class ThemeChanged extends SettingsEvent {
  final ThemePreference theme;
  
  const ThemeChanged({required this.theme});
  
  @override
  List<Object> get props => [theme];
}

/// Change selected model path (null = default).
final class SelectedModelChanged extends SettingsEvent {
  final String? modelPath;

  const SelectedModelChanged({required this.modelPath});

  @override
  List<Object?> get props => [modelPath];
}
