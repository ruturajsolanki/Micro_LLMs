import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../domain/usecases/speech_to_text_usecase.dart';
import '../../../domain/usecases/text_to_speech_usecase.dart';
import '../../../domain/repositories/voice_repository.dart';
import '../../../domain/entities/speech_to_text_engine.dart';
import '../../../domain/entities/text_to_speech_engine.dart';
import '../../../core/utils/logger.dart';

part 'voice_event.dart';
part 'voice_state.dart';

/// BLoC for managing voice operations (STT/TTS).
class VoiceBloc extends Bloc<VoiceEvent, VoiceState> with Loggable {
  final SpeechToTextUseCase _speechToTextUseCase;
  final TextToSpeechUseCase _textToSpeechUseCase;
  
  StreamSubscription<SpeechToTextEvent>? _sttSubscription;
  StreamSubscription<SpeechSynthesisEvent>? _ttsSubscription;
  
  VoiceBloc({
    required SpeechToTextUseCase speechToTextUseCase,
    required TextToSpeechUseCase textToSpeechUseCase,
  })  : _speechToTextUseCase = speechToTextUseCase,
        _textToSpeechUseCase = textToSpeechUseCase,
        super(const VoiceState()) {
    on<VoiceRecognitionStarted>(_onRecognitionStarted);
    on<VoiceRecognitionStopped>(_onRecognitionStopped);
    on<VoiceRecognitionEnded>(_onRecognitionEnded);
    on<VoiceRecognitionResultReceived>(_onRecognitionResultReceived);
    on<VoiceRecognitionFailed>(_onRecognitionFailed);
    on<VoiceSynthesisStarted>(_onSynthesisStarted);
    on<VoiceSynthesisStopped>(_onSynthesisStopped);
    on<VoiceSynthesisCompleted>(_onSynthesisCompleted);
    on<VoiceSynthesisFailed>(_onSynthesisFailed);

    // Subscribe once to platform TTS callbacks so we can:
    // - return to idle on completion
    // - support turn-taking in "voice call mode"
    _ttsSubscription = _textToSpeechUseCase.events.listen((e) {
      switch (e) {
        case SpeechSynthesisCompleted():
          add(const VoiceSynthesisCompleted());
        case SpeechSynthesisError(:final message):
          add(VoiceSynthesisFailed(error: message));
      }
    });
  }
  
  @override
  Future<void> close() {
    _sttSubscription?.cancel();
    _ttsSubscription?.cancel();
    return super.close();
  }
  
  Future<void> _onRecognitionStarted(
    VoiceRecognitionStarted event,
    Emitter<VoiceState> emit,
  ) async {
    emit(state.copyWith(
      sttStatus: VoiceSttStatus.listening,
      recognizedText: '',
      errorMessage: null,
    ));
    
    await _sttSubscription?.cancel();
    
    _sttSubscription = _speechToTextUseCase(SpeechToTextParams(
      language: event.language,
      offlineOnly: event.offlineOnly,
      engine: event.engine,
      whisperModelId: event.whisperModelId,
      whisperThreads: 4,
    )).listen(
      (sttEvent) {
        switch (sttEvent) {
          case SpeechToTextListening():
            // Already emitted above
            break;
          case SpeechToTextResult(:final text, :final isFinal, :final confidence, :final levelDb):
            add(VoiceRecognitionResultReceived(
              text: text,
              isFinal: isFinal,
              confidence: confidence,
              levelDb: levelDb,
            ));
          case SpeechToTextStopped():
            add(const VoiceRecognitionEnded());
          case SpeechToTextError(:final message):
            add(VoiceRecognitionFailed(error: message));
        }
      },
      onError: (error) {
        add(VoiceRecognitionFailed(error: error.toString()));
      },
    );
  }
  
  Future<void> _onRecognitionStopped(
    VoiceRecognitionStopped event,
    Emitter<VoiceState> emit,
  ) async {
    await _sttSubscription?.cancel();
    await _speechToTextUseCase.stop();
    
    emit(state.copyWith(sttStatus: VoiceSttStatus.idle));
  }

  void _onRecognitionEnded(
    VoiceRecognitionEnded event,
    Emitter<VoiceState> emit,
  ) {
    // Only transition to idle if we were in a non-terminal state.
    if (state.sttStatus == VoiceSttStatus.listening ||
        state.sttStatus == VoiceSttStatus.processing) {
      emit(state.copyWith(sttStatus: VoiceSttStatus.idle));
    }
  }
  
  void _onRecognitionResultReceived(
    VoiceRecognitionResultReceived event,
    Emitter<VoiceState> emit,
  ) {
    // Level-only updates (no text)
    if (event.text.isEmpty && event.levelDb != null) {
      emit(state.copyWith(
        sttStatus: VoiceSttStatus.listening,
        inputLevelDb: event.levelDb,
      ));
      return;
    }

    emit(state.copyWith(
      sttStatus: event.isFinal ? VoiceSttStatus.idle : VoiceSttStatus.listening,
      recognizedText: event.text,
      lastConfidence: event.confidence,
      inputLevelDb: event.levelDb,
    ));
  }
  
  void _onRecognitionFailed(
    VoiceRecognitionFailed event,
    Emitter<VoiceState> emit,
  ) {
    logger.e('Voice recognition failed: ${event.error}');
    emit(state.copyWith(
      sttStatus: VoiceSttStatus.error,
      errorMessage: event.error,
    ));
  }
  
  Future<void> _onSynthesisStarted(
    VoiceSynthesisStarted event,
    Emitter<VoiceState> emit,
  ) async {
    emit(state.copyWith(ttsStatus: VoiceTtsStatus.speaking));
    
    final result = await _textToSpeechUseCase(TextToSpeechParams(
      text: event.text,
      language: event.language,
      engine: event.engine,
      elevenLabsVoiceId: event.elevenLabsVoiceId,
    ));
    
    result.fold(
      (failure) {
        logger.e('TTS failed: ${failure.message}');
        emit(state.copyWith(
          ttsStatus: VoiceTtsStatus.error,
          errorMessage: failure.message,
        ));
      },
      (_) {
        // TTS will callback when complete
        // For now, assume it starts successfully
      },
    );
  }
  
  Future<void> _onSynthesisStopped(
    VoiceSynthesisStopped event,
    Emitter<VoiceState> emit,
  ) async {
    await _textToSpeechUseCase.stop();
    emit(state.copyWith(ttsStatus: VoiceTtsStatus.idle));
  }

  void _onSynthesisCompleted(
    VoiceSynthesisCompleted event,
    Emitter<VoiceState> emit,
  ) {
    emit(state.copyWith(ttsStatus: VoiceTtsStatus.idle));
  }

  void _onSynthesisFailed(
    VoiceSynthesisFailed event,
    Emitter<VoiceState> emit,
  ) {
    emit(state.copyWith(
      ttsStatus: VoiceTtsStatus.error,
      errorMessage: event.error,
    ));
  }
}
