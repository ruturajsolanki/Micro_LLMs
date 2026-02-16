part of 'v2_session_bloc.dart';

enum V2SessionStatus {
  /// Checking cloud connectivity.
  checking,

  /// No API key configured — need setup.
  needsSetup,

  /// Ready to record.
  ready,

  /// Recording audio.
  recording,

  /// Uploading audio and transcribing via cloud STT.
  transcribing,

  /// Running evaluation/summarization via cloud LLM.
  evaluating,

  /// Results are available.
  completed,

  /// An error occurred.
  error,
}

class V2SessionState extends Equatable {
  final V2SessionStatus status;

  /// Whether the cloud is reachable.
  final bool cloudReady;

  /// Active cloud LLM provider.
  final CloudLLMProvider llmProvider;

  /// Active cloud STT provider.
  final CloudSttProvider sttProvider;

  /// Recording duration in seconds.
  final int recordingSeconds;

  /// Transcribed text from STT.
  final String? transcript;

  /// Evaluation result (scores, feedback).
  final EvaluationResult? evaluationResult;

  /// Full benchmark result (includes summary, key ideas, etc.).
  final BenchmarkResult? benchmarkResult;

  /// Error message.
  final String? errorMessage;

  /// Processing step label (for UI progress).
  final String? processingStep;

  /// Audio source: 'mic' or 'upload'.
  final String audioSource;

  /// If upload, the original file name.
  final String? uploadedFileName;

  const V2SessionState({
    this.status = V2SessionStatus.checking,
    this.cloudReady = false,
    this.llmProvider = CloudLLMProvider.groq,
    this.sttProvider = CloudSttProvider.groqWhisper,
    this.recordingSeconds = 0,
    this.transcript,
    this.evaluationResult,
    this.benchmarkResult,
    this.errorMessage,
    this.processingStep,
    this.audioSource = 'mic',
    this.uploadedFileName,
  });

  V2SessionState copyWith({
    V2SessionStatus? status,
    bool? cloudReady,
    CloudLLMProvider? llmProvider,
    CloudSttProvider? sttProvider,
    int? recordingSeconds,
    String? transcript,
    EvaluationResult? evaluationResult,
    BenchmarkResult? benchmarkResult,
    String? errorMessage,
    String? processingStep,
    String? audioSource,
    String? uploadedFileName,
  }) {
    return V2SessionState(
      status: status ?? this.status,
      cloudReady: cloudReady ?? this.cloudReady,
      llmProvider: llmProvider ?? this.llmProvider,
      sttProvider: sttProvider ?? this.sttProvider,
      recordingSeconds: recordingSeconds ?? this.recordingSeconds,
      transcript: transcript ?? this.transcript,
      evaluationResult: evaluationResult ?? this.evaluationResult,
      benchmarkResult: benchmarkResult ?? this.benchmarkResult,
      errorMessage: errorMessage ?? this.errorMessage,
      processingStep: processingStep ?? this.processingStep,
      audioSource: audioSource ?? this.audioSource,
      uploadedFileName: uploadedFileName ?? this.uploadedFileName,
    );
  }

  @override
  List<Object?> get props => [
        status,
        cloudReady,
        llmProvider,
        sttProvider,
        recordingSeconds,
        transcript,
        evaluationResult,
        benchmarkResult,
        errorMessage,
        processingStep,
        audioSource,
        uploadedFileName,
      ];
}
