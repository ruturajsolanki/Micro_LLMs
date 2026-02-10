part of 'benchmark_bloc.dart';

/// Base class for benchmark events.
sealed class BenchmarkEvent extends Equatable {
  const BenchmarkEvent();

  @override
  List<Object?> get props => [];
}

/// Initialize the benchmark page with prompts and settings.
final class BenchmarkStarted extends BenchmarkEvent {
  const BenchmarkStarted();
}

/// Start recording voice for benchmark.
final class BenchmarkRecordingStarted extends BenchmarkEvent {
  final SpeechToTextEngine engine;
  final String language;
  final bool offlineOnly;
  final String whisperModelId;

  const BenchmarkRecordingStarted({
    required this.engine,
    required this.language,
    this.offlineOnly = false,
    this.whisperModelId = 'small',
  });

  @override
  List<Object?> get props => [engine, language, offlineOnly, whisperModelId];
}

/// Stop recording and begin the processing pipeline.
final class BenchmarkRecordingStopped extends BenchmarkEvent {
  const BenchmarkRecordingStopped();
}

/// Transcript text updated during recording (internal).
final class BenchmarkTranscriptUpdated extends BenchmarkEvent {
  final String text;
  final bool isFinal;

  const BenchmarkTranscriptUpdated({
    required this.text,
    required this.isFinal,
  });

  @override
  List<Object?> get props => [text, isFinal];
}

/// Recording timer tick (internal).
final class BenchmarkRecordingTick extends BenchmarkEvent {
  final int seconds;
  const BenchmarkRecordingTick({required this.seconds});

  @override
  List<Object?> get props => [seconds];
}

/// Recording failed (internal).
final class BenchmarkRecordingFailed extends BenchmarkEvent {
  final String error;
  const BenchmarkRecordingFailed({required this.error});

  @override
  List<Object> get props => [error];
}

/// Pipeline step started (internal).
final class BenchmarkPipelineStepStarted extends BenchmarkEvent {
  final PipelineStep step;
  const BenchmarkPipelineStepStarted({required this.step});

  @override
  List<Object> get props => [step];
}

/// Pipeline step completed (internal).
final class BenchmarkPipelineStepCompleted extends BenchmarkEvent {
  final PipelineStep step;
  final String result;
  const BenchmarkPipelineStepCompleted({
    required this.step,
    required this.result,
  });

  @override
  List<Object> get props => [step, result];
}

/// Entire pipeline completed (internal).
final class BenchmarkPipelineCompleted extends BenchmarkEvent {
  final BenchmarkResult result;
  const BenchmarkPipelineCompleted({required this.result});

  @override
  List<Object> get props => [result];
}

/// Pipeline error (internal).
final class BenchmarkPipelineError extends BenchmarkEvent {
  final String message;
  final PipelineStep? failedStep;
  const BenchmarkPipelineError({required this.message, this.failedStep});

  @override
  List<Object?> get props => [message, failedStep];
}

/// User selected a different prompt preset.
final class BenchmarkPromptSelected extends BenchmarkEvent {
  final String promptId;
  const BenchmarkPromptSelected({required this.promptId});

  @override
  List<Object> get props => [promptId];
}

/// Prompts were updated (e.g. after editing in PromptEditorPage).
final class BenchmarkPromptsRefreshed extends BenchmarkEvent {
  const BenchmarkPromptsRefreshed();
}

/// Toggle benchmark evaluation on/off.
final class BenchmarkEvaluationToggled extends BenchmarkEvent {
  const BenchmarkEvaluationToggled();
}

/// Reset to idle state.
final class BenchmarkReset extends BenchmarkEvent {
  const BenchmarkReset();
}
