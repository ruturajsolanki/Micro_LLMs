part of 'benchmark_bloc.dart';

/// Top-level status of the benchmark flow.
enum BenchmarkStatus {
  /// Ready to start recording.
  idle,

  /// Currently recording voice input.
  recording,

  /// Processing through the summarization pipeline.
  processing,

  /// Results are available.
  result,
}

/// State for the benchmark flow.
///
/// Tracks the full lifecycle: idle → recording → processing → result.
class BenchmarkState extends Equatable {
  static const Object _unset = Object();

  /// Current flow status.
  final BenchmarkStatus status;

  /// All available prompt presets.
  final List<BenchmarkPrompt> prompts;

  /// The currently selected prompt preset.
  final BenchmarkPrompt selectedPrompt;

  /// Accumulated final (confirmed) transcript text from STT.
  final String accumulatedTranscript;

  /// Current partial (in-progress) text from STT — not yet confirmed.
  /// Displayed in a lighter/italic style to show it may still change.
  final String partialText;

  /// Live transcript (final + partial combined) for display during recording.
  final String liveTranscript;

  /// Current recording duration in seconds.
  final int recordingDurationSeconds;

  /// Pipeline steps that have been completed.
  final List<PipelineStep> completedSteps;

  /// The pipeline step currently in progress.
  final PipelineStep? currentStep;

  /// Final benchmark result, set when pipeline completes.
  final BenchmarkResult? result;

  /// Whether benchmark evaluation scoring is enabled.
  ///
  /// When false, the pipeline skips the rubric evaluation step and only
  /// produces a summary + key ideas (faster, fewer LLM calls).
  final bool benchmarkEnabled;

  /// Error message, if any.
  final String? errorMessage;

  const BenchmarkState({
    required this.status,
    required this.prompts,
    required this.selectedPrompt,
    this.accumulatedTranscript = '',
    this.partialText = '',
    this.liveTranscript = '',
    this.recordingDurationSeconds = 0,
    this.completedSteps = const [],
    this.currentStep,
    this.result,
    this.benchmarkEnabled = false,
    this.errorMessage,
  });

  factory BenchmarkState.initial() {
    final defaults = BenchmarkPrompt.defaults;
    return BenchmarkState(
      status: BenchmarkStatus.idle,
      prompts: defaults,
      selectedPrompt: defaults.first,
    );
  }

  BenchmarkState copyWith({
    BenchmarkStatus? status,
    List<BenchmarkPrompt>? prompts,
    BenchmarkPrompt? selectedPrompt,
    String? accumulatedTranscript,
    String? partialText,
    String? liveTranscript,
    int? recordingDurationSeconds,
    List<PipelineStep>? completedSteps,
    Object? currentStep = _unset,
    Object? result = _unset,
    bool? benchmarkEnabled,
    Object? errorMessage = _unset,
  }) {
    return BenchmarkState(
      status: status ?? this.status,
      prompts: prompts ?? this.prompts,
      selectedPrompt: selectedPrompt ?? this.selectedPrompt,
      accumulatedTranscript:
          accumulatedTranscript ?? this.accumulatedTranscript,
      partialText: partialText ?? this.partialText,
      liveTranscript: liveTranscript ?? this.liveTranscript,
      recordingDurationSeconds:
          recordingDurationSeconds ?? this.recordingDurationSeconds,
      completedSteps: completedSteps ?? this.completedSteps,
      currentStep: identical(currentStep, _unset)
          ? this.currentStep
          : currentStep as PipelineStep?,
      result: identical(result, _unset)
          ? this.result
          : result as BenchmarkResult?,
      benchmarkEnabled: benchmarkEnabled ?? this.benchmarkEnabled,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }

  bool get isIdle => status == BenchmarkStatus.idle;
  bool get isRecording => status == BenchmarkStatus.recording;
  bool get isProcessing => status == BenchmarkStatus.processing;
  bool get hasResult => status == BenchmarkStatus.result && result != null;

  /// Formatted recording duration (MM:SS).
  String get formattedDuration {
    final minutes = recordingDurationSeconds ~/ 60;
    final seconds = recordingDurationSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Word count of the combined live transcript (for display).
  int get wordCount {
    final text = liveTranscript.trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).length;
  }

  @override
  List<Object?> get props => [
        status,
        prompts,
        selectedPrompt,
        accumulatedTranscript,
        partialText,
        liveTranscript,
        recordingDurationSeconds,
        completedSteps,
        currentStep,
        result,
        benchmarkEnabled,
        errorMessage,
      ];
}
