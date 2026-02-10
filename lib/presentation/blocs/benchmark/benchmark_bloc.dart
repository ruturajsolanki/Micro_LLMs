import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../domain/entities/benchmark_result.dart';
import '../../../domain/entities/benchmark_prompt.dart';
import '../../../domain/entities/speech_to_text_engine.dart';
import '../../../domain/usecases/summarize_transcript_usecase.dart';
import '../../../domain/usecases/speech_to_text_usecase.dart';
import '../../../data/datasources/benchmark_storage.dart';
import '../../../core/utils/logger.dart';

part 'benchmark_event.dart';
part 'benchmark_state.dart';

/// BLoC for the Voice Benchmarking & Summarization flow.
///
/// Manages the full lifecycle:
/// 1. Idle — user can configure prompt and start recording.
/// 2. Recording — STT accumulates transcript, timer ticks.
/// 3. Processing — pipeline runs extraction → summarization → evaluation.
/// 4. Result — structured output displayed.
class BenchmarkBloc extends Bloc<BenchmarkEvent, BenchmarkState> with Loggable {
  final SpeechToTextUseCase _speechToTextUseCase;
  final SummarizeTranscriptUseCase _summarizeTranscriptUseCase;
  final BenchmarkStorage _benchmarkStorage;

  StreamSubscription<SpeechToTextEvent>? _sttSubscription;
  StreamSubscription<SummarizationPipelineEvent>? _pipelineSubscription;

  Timer? _recordingTimer;
  int _recordingSeconds = 0;

  BenchmarkBloc({
    required SpeechToTextUseCase speechToTextUseCase,
    required SummarizeTranscriptUseCase summarizeTranscriptUseCase,
    required BenchmarkStorage benchmarkStorage,
  })  : _speechToTextUseCase = speechToTextUseCase,
        _summarizeTranscriptUseCase = summarizeTranscriptUseCase,
        _benchmarkStorage = benchmarkStorage,
        super(BenchmarkState.initial()) {
    on<BenchmarkStarted>(_onStarted);
    on<BenchmarkRecordingStarted>(_onRecordingStarted);
    on<BenchmarkRecordingStopped>(_onRecordingStopped);
    on<BenchmarkTranscriptUpdated>(_onTranscriptUpdated);
    on<BenchmarkRecordingTick>(_onRecordingTick);
    on<BenchmarkRecordingFailed>(_onRecordingFailed);
    on<BenchmarkPipelineStepStarted>(_onPipelineStepStarted);
    on<BenchmarkPipelineStepCompleted>(_onPipelineStepCompleted);
    on<BenchmarkPipelineCompleted>(_onPipelineCompleted);
    on<BenchmarkPipelineError>(_onPipelineError);
    on<BenchmarkPromptSelected>(_onPromptSelected);
    on<BenchmarkPromptsRefreshed>(_onPromptsRefreshed);
    on<BenchmarkEvaluationToggled>(_onEvaluationToggled);
    on<BenchmarkReset>(_onReset);
  }

  @override
  Future<void> close() {
    _sttSubscription?.cancel();
    _pipelineSubscription?.cancel();
    _recordingTimer?.cancel();
    return super.close();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Event Handlers
  // ──────────────────────────────────────────────────────────────────────────

  void _onStarted(BenchmarkStarted event, Emitter<BenchmarkState> emit) {
    final prompts = _benchmarkStorage.loadPrompts();
    final selectedId = _benchmarkStorage.getSelectedPromptId();
    final selectedPrompt = prompts.firstWhere(
      (p) => p.id == selectedId,
      orElse: () => prompts.first,
    );

    emit(state.copyWith(
      prompts: prompts,
      selectedPrompt: selectedPrompt,
    ));
  }

  Future<void> _onRecordingStarted(
    BenchmarkRecordingStarted event,
    Emitter<BenchmarkState> emit,
  ) async {
    _recordingSeconds = 0;

    emit(state.copyWith(
      status: BenchmarkStatus.recording,
      accumulatedTranscript: '',
      partialText: '',
      liveTranscript: '',
      recordingDurationSeconds: 0,
      errorMessage: null,
    ));

    // Start the elapsed-time timer (1-second ticks).
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _recordingSeconds++;
      add(BenchmarkRecordingTick(seconds: _recordingSeconds));
    });

    // Start STT in continuous mode for extended recording.
    await _sttSubscription?.cancel();

    _sttSubscription = _speechToTextUseCase(SpeechToTextParams(
      language: event.language,
      continuous: true,
      offlineOnly: event.offlineOnly,
      engine: event.engine,
      whisperModelId: event.whisperModelId,
    )).listen(
      (sttEvent) {
        switch (sttEvent) {
          case SpeechToTextListening():
            break;
          case SpeechToTextResult(:final text, :final isFinal):
            if (text.isNotEmpty) {
              add(BenchmarkTranscriptUpdated(text: text, isFinal: isFinal));
            }
          case SpeechToTextStopped():
            break;
          case SpeechToTextError(:final message):
            add(BenchmarkRecordingFailed(error: message));
        }
      },
      onError: (error) {
        add(BenchmarkRecordingFailed(error: error.toString()));
      },
    );
  }

  void _onRecordingStopped(
    BenchmarkRecordingStopped event,
    Emitter<BenchmarkState> emit,
  ) {
    _recordingTimer?.cancel();
    _sttSubscription?.cancel();
    _speechToTextUseCase.stop();

    final transcript = state.accumulatedTranscript.trim();

    if (transcript.isEmpty) {
      emit(state.copyWith(
        status: BenchmarkStatus.idle,
        errorMessage: 'No speech detected. Please try again.',
      ));
      return;
    }

    // Transition to processing.
    emit(state.copyWith(
      status: BenchmarkStatus.processing,
      completedSteps: [],
      currentStep: null,
    ));

    // Start the summarization + evaluation pipeline.
    _startPipeline(transcript);
  }

  void _startPipeline(String transcript) {
    _pipelineSubscription?.cancel();

    final params = SummarizeTranscriptParams(
      transcript: transcript,
      prompt: state.selectedPrompt,
      recordingDurationSeconds: state.recordingDurationSeconds,
      includeBenchmark: state.benchmarkEnabled,
    );

    _pipelineSubscription =
        _summarizeTranscriptUseCase(params).listen(
      (event) {
        switch (event) {
          case PipelineStepStarted(:final step):
            add(BenchmarkPipelineStepStarted(step: step));
          case PipelineStepCompleted(:final step, :final result):
            add(BenchmarkPipelineStepCompleted(step: step, result: result));
          case PipelineCompleted(:final result):
            add(BenchmarkPipelineCompleted(result: result));
          case PipelineError(:final message, :final failedStep):
            add(BenchmarkPipelineError(
                message: message, failedStep: failedStep));
        }
      },
      onError: (error) {
        add(BenchmarkPipelineError(message: error.toString()));
      },
    );
  }

  void _onTranscriptUpdated(
    BenchmarkTranscriptUpdated event,
    Emitter<BenchmarkState> emit,
  ) {
    if (event.isFinal) {
      // Append final result to accumulated text and clear partial.
      final existing = state.accumulatedTranscript;
      final updated =
          existing.isEmpty ? event.text : '$existing ${event.text}';
      emit(state.copyWith(
        accumulatedTranscript: updated,
        partialText: '',
        liveTranscript: updated,
      ));
    } else {
      // Update partial text (in-progress words) while keeping finals stable.
      final base = state.accumulatedTranscript;
      final live = base.isEmpty ? event.text : '$base ${event.text}';
      emit(state.copyWith(
        partialText: event.text,
        liveTranscript: live,
      ));
    }
  }

  void _onRecordingTick(
    BenchmarkRecordingTick event,
    Emitter<BenchmarkState> emit,
  ) {
    emit(state.copyWith(recordingDurationSeconds: event.seconds));
  }

  void _onRecordingFailed(
    BenchmarkRecordingFailed event,
    Emitter<BenchmarkState> emit,
  ) {
    _recordingTimer?.cancel();
    logger.e('Benchmark recording failed: ${event.error}');
    emit(state.copyWith(
      status: BenchmarkStatus.idle,
      errorMessage: event.error,
    ));
  }

  void _onPipelineStepStarted(
    BenchmarkPipelineStepStarted event,
    Emitter<BenchmarkState> emit,
  ) {
    emit(state.copyWith(currentStep: event.step));
  }

  void _onPipelineStepCompleted(
    BenchmarkPipelineStepCompleted event,
    Emitter<BenchmarkState> emit,
  ) {
    final completedSteps = [...state.completedSteps, event.step];
    emit(state.copyWith(completedSteps: completedSteps));
  }

  void _onPipelineCompleted(
    BenchmarkPipelineCompleted event,
    Emitter<BenchmarkState> emit,
  ) {
    AppLogger.i(
      'Benchmark pipeline completed in '
      '${event.result.processingTimeMs}ms',
    );
    emit(state.copyWith(
      status: BenchmarkStatus.result,
      result: event.result,
      currentStep: null,
    ));
  }

  void _onPipelineError(
    BenchmarkPipelineError event,
    Emitter<BenchmarkState> emit,
  ) {
    logger.e('Benchmark pipeline error: ${event.message}');
    emit(state.copyWith(
      status: BenchmarkStatus.idle,
      errorMessage: 'Processing failed: ${event.message}',
    ));
  }

  void _onPromptSelected(
    BenchmarkPromptSelected event,
    Emitter<BenchmarkState> emit,
  ) {
    final prompt = state.prompts.firstWhere(
      (p) => p.id == event.promptId,
      orElse: () => state.prompts.first,
    );

    _benchmarkStorage.setSelectedPromptId(event.promptId);

    emit(state.copyWith(selectedPrompt: prompt));
  }

  void _onPromptsRefreshed(
    BenchmarkPromptsRefreshed event,
    Emitter<BenchmarkState> emit,
  ) {
    final prompts = _benchmarkStorage.loadPrompts();
    final selectedId = _benchmarkStorage.getSelectedPromptId();
    final selectedPrompt = prompts.firstWhere(
      (p) => p.id == selectedId,
      orElse: () => prompts.first,
    );
    emit(state.copyWith(prompts: prompts, selectedPrompt: selectedPrompt));
  }

  void _onEvaluationToggled(
    BenchmarkEvaluationToggled event,
    Emitter<BenchmarkState> emit,
  ) {
    emit(state.copyWith(benchmarkEnabled: !state.benchmarkEnabled));
  }

  void _onReset(BenchmarkReset event, Emitter<BenchmarkState> emit) {
    _pipelineSubscription?.cancel();
    _sttSubscription?.cancel();
    _recordingTimer?.cancel();
    _speechToTextUseCase.stop();

    emit(state.copyWith(
      status: BenchmarkStatus.idle,
      accumulatedTranscript: '',
      liveTranscript: '',
      recordingDurationSeconds: 0,
      result: null,
      completedSteps: [],
      currentStep: null,
      errorMessage: null,
    ));
  }
}
