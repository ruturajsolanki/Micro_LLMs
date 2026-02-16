import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../domain/entities/app_settings.dart';
import '../../../domain/entities/cloud_provider.dart';
import '../../../domain/entities/speech_to_text_engine.dart';
import '../../../domain/entities/text_to_speech_engine.dart';
import '../../../domain/repositories/settings_repository.dart';
import '../../../core/utils/logger.dart';

part 'settings_event.dart';
part 'settings_state.dart';

/// BLoC for managing application settings.
class SettingsBloc extends Bloc<SettingsEvent, SettingsState> with Loggable {
  final SettingsRepository _settingsRepository;
  
  SettingsBloc({
    required SettingsRepository settingsRepository,
  })  : _settingsRepository = settingsRepository,
        super(const SettingsState()) {
    on<SettingsLoadRequested>(_onLoadRequested);
    on<SettingsUpdated>(_onSettingsUpdated);
    on<SettingsResetRequested>(_onResetRequested);
    on<SourceLanguageChanged>(_onSourceLanguageChanged);
    on<TargetLanguageChanged>(_onTargetLanguageChanged);
    on<VoiceInputToggled>(_onVoiceInputToggled);
    on<VoiceOutputToggled>(_onVoiceOutputToggled);
    on<VoiceSttOfflineOnlyToggled>(_onVoiceSttOfflineOnlyToggled);
    on<SpeechToTextEngineChanged>(_onSpeechToTextEngineChanged);
    on<WhisperModelChanged>(_onWhisperModelChanged);
    on<TextToSpeechEngineChanged>(_onTextToSpeechEngineChanged);
    on<ElevenLabsVoiceChanged>(_onElevenLabsVoiceChanged);
    on<TemperatureChanged>(_onTemperatureChanged);
    on<ThemeChanged>(_onThemeChanged);
    on<SelectedModelChanged>(_onSelectedModelChanged);
    on<UseCloudProcessingToggled>(_onUseCloudProcessingToggled);
    on<CloudLLMProviderChanged>(_onCloudLLMProviderChanged);
    on<CloudSttProviderChanged>(_onCloudSttProviderChanged);
  }
  
  Future<void> _onLoadRequested(
    SettingsLoadRequested event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(status: SettingsStatus.loading));
    
    final result = await _settingsRepository.loadSettings();
    
    result.fold(
      (failure) {
        emit(state.copyWith(
          status: SettingsStatus.error,
          errorMessage: failure.message,
        ));
      },
      (settings) {
        emit(state.copyWith(
          status: SettingsStatus.loaded,
          settings: settings,
        ));
      },
    );
  }
  
  Future<void> _onSettingsUpdated(
    SettingsUpdated event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(status: SettingsStatus.saving));
    
    final result = await _settingsRepository.saveSettings(event.settings);
    
    result.fold(
      (failure) {
        emit(state.copyWith(
          status: SettingsStatus.error,
          errorMessage: failure.message,
        ));
      },
      (_) {
        emit(state.copyWith(
          status: SettingsStatus.loaded,
          settings: event.settings,
        ));
      },
    );
  }
  
  Future<void> _onResetRequested(
    SettingsResetRequested event,
    Emitter<SettingsState> emit,
  ) async {
    emit(state.copyWith(status: SettingsStatus.saving));
    
    final result = await _settingsRepository.resetToDefaults();
    
    result.fold(
      (failure) {
        emit(state.copyWith(
          status: SettingsStatus.error,
          errorMessage: failure.message,
        ));
      },
      (_) {
        emit(state.copyWith(
          status: SettingsStatus.loaded,
          settings: const AppSettings(),
        ));
      },
    );
  }
  
  Future<void> _onSourceLanguageChanged(
    SourceLanguageChanged event,
    Emitter<SettingsState> emit,
  ) async {
    final newSettings = state.settings.copyWith(
      sourceLanguage: event.language,
    );
    add(SettingsUpdated(settings: newSettings));
  }
  
  Future<void> _onTargetLanguageChanged(
    TargetLanguageChanged event,
    Emitter<SettingsState> emit,
  ) async {
    final newSettings = state.settings.copyWith(
      targetLanguage: event.language,
    );
    add(SettingsUpdated(settings: newSettings));
  }
  
  Future<void> _onVoiceInputToggled(
    VoiceInputToggled event,
    Emitter<SettingsState> emit,
  ) async {
    final newSettings = state.settings.copyWith(
      voiceInputEnabled: !state.settings.voiceInputEnabled,
    );
    add(SettingsUpdated(settings: newSettings));
  }
  
  Future<void> _onVoiceOutputToggled(
    VoiceOutputToggled event,
    Emitter<SettingsState> emit,
  ) async {
    final newSettings = state.settings.copyWith(
      voiceOutputEnabled: !state.settings.voiceOutputEnabled,
    );
    add(SettingsUpdated(settings: newSettings));
  }

  Future<void> _onVoiceSttOfflineOnlyToggled(
    VoiceSttOfflineOnlyToggled event,
    Emitter<SettingsState> emit,
  ) async {
    final newSettings = state.settings.copyWith(
      voiceSttOfflineOnly: !state.settings.voiceSttOfflineOnly,
    );
    add(SettingsUpdated(settings: newSettings));
  }

  Future<void> _onSpeechToTextEngineChanged(
    SpeechToTextEngineChanged event,
    Emitter<SettingsState> emit,
  ) async {
    final newSettings = state.settings.copyWith(
      speechToTextEngine: event.engine,
    );
    add(SettingsUpdated(settings: newSettings));
  }

  Future<void> _onWhisperModelChanged(
    WhisperModelChanged event,
    Emitter<SettingsState> emit,
  ) async {
    final newSettings = state.settings.copyWith(
      whisperModelId: event.modelId,
    );
    add(SettingsUpdated(settings: newSettings));
  }

  Future<void> _onTextToSpeechEngineChanged(
    TextToSpeechEngineChanged event,
    Emitter<SettingsState> emit,
  ) async {
    final newSettings = state.settings.copyWith(
      textToSpeechEngine: event.engine,
    );
    add(SettingsUpdated(settings: newSettings));
  }

  Future<void> _onElevenLabsVoiceChanged(
    ElevenLabsVoiceChanged event,
    Emitter<SettingsState> emit,
  ) async {
    final newSettings = state.settings.copyWith(
      elevenLabsVoiceId: event.voiceId,
    );
    add(SettingsUpdated(settings: newSettings));
  }
  
  Future<void> _onTemperatureChanged(
    TemperatureChanged event,
    Emitter<SettingsState> emit,
  ) async {
    final newSettings = state.settings.copyWith(
      temperature: event.temperature,
    );
    add(SettingsUpdated(settings: newSettings));
  }
  
  Future<void> _onThemeChanged(
    ThemeChanged event,
    Emitter<SettingsState> emit,
  ) async {
    final newSettings = state.settings.copyWith(
      themePreference: event.theme,
    );
    add(SettingsUpdated(settings: newSettings));
  }

  Future<void> _onSelectedModelChanged(
    SelectedModelChanged event,
    Emitter<SettingsState> emit,
  ) async {
    final newSettings = state.settings.copyWith(
      selectedModelPath: event.modelPath,
    );
    add(SettingsUpdated(settings: newSettings));
  }

  Future<void> _onUseCloudProcessingToggled(
    UseCloudProcessingToggled event,
    Emitter<SettingsState> emit,
  ) async {
    final newSettings = state.settings.copyWith(
      useCloudProcessing: !state.settings.useCloudProcessing,
    );
    add(SettingsUpdated(settings: newSettings));
  }

  Future<void> _onCloudLLMProviderChanged(
    CloudLLMProviderChanged event,
    Emitter<SettingsState> emit,
  ) async {
    final newSettings = state.settings.copyWith(
      cloudLLMProvider: event.provider,
    );
    add(SettingsUpdated(settings: newSettings));
  }

  Future<void> _onCloudSttProviderChanged(
    CloudSttProviderChanged event,
    Emitter<SettingsState> emit,
  ) async {
    final newSettings = state.settings.copyWith(
      cloudSttProvider: event.provider,
    );
    add(SettingsUpdated(settings: newSettings));
  }
}
