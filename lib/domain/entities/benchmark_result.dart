import 'package:equatable/equatable.dart';

import 'evaluation_result.dart';
import 'safety_result.dart';

/// Qualitative score for a benchmark dimension.
enum BenchmarkScore {
  good,
  fair,
  poor;

  String get label {
    switch (this) {
      case BenchmarkScore.good:
        return 'Good';
      case BenchmarkScore.fair:
        return 'Fair';
      case BenchmarkScore.poor:
        return 'Poor';
    }
  }

  double get numericValue {
    switch (this) {
      case BenchmarkScore.good:
        return 1.0;
      case BenchmarkScore.fair:
        return 0.5;
      case BenchmarkScore.poor:
        return 0.0;
    }
  }
}

/// A single dimension score within the benchmark rubric.
class BenchmarkDimension extends Equatable {
  /// Name of the dimension (e.g. "Relevance").
  final String name;

  /// Description of what is being measured.
  final String description;

  /// The score for this dimension.
  final BenchmarkScore score;

  /// A brief explanation of why this score was given.
  final String explanation;

  const BenchmarkDimension({
    required this.name,
    required this.description,
    required this.score,
    required this.explanation,
  });

  @override
  List<Object?> get props => [name, description, score, explanation];
}

/// Complete benchmark result including summary, evaluation scores, and safety info.
///
/// Produced by the [SummarizeTranscriptUseCase] pipeline after recording,
/// transcription, safety scan, summarization, and evaluation.
class BenchmarkResult extends Equatable {
  /// The original transcript from voice recording.
  final String transcript;

  /// Extracted key ideas from the transcript.
  final String keyIdeas;

  /// The generated summary.
  final String summary;

  /// Individual benchmark dimension scores (summarization quality rubric).
  final List<BenchmarkDimension> dimensions;

  /// Duration of the recording in seconds.
  final int recordingDurationSeconds;

  /// Total processing time in milliseconds.
  final int processingTimeMs;

  /// The prompt instruction that was used for summarization.
  final String promptUsed;

  /// When the benchmark was completed.
  final DateTime completedAt;

  /// Safety scan result. Non-null when the safety pipeline ran.
  final SafetyResult? safetyResult;

  /// Evaluation result (Clarity + Language scoring). Non-null when evaluation ran.
  final EvaluationResult? evaluationResult;

  const BenchmarkResult({
    required this.transcript,
    required this.keyIdeas,
    required this.summary,
    required this.dimensions,
    required this.recordingDurationSeconds,
    required this.processingTimeMs,
    required this.promptUsed,
    required this.completedAt,
    this.safetyResult,
    this.evaluationResult,
  });

  /// Whether the content was flagged as unsafe.
  bool get isSafetyFlagged =>
      safetyResult != null && !safetyResult!.isSafe;

  /// Whether evaluation scores are available and should be shown.
  bool get hasEvaluation =>
      evaluationResult != null && !evaluationResult!.safetyFlag;

  /// Overall score (average of dimension numeric values).
  double get overallScore {
    if (dimensions.isEmpty) return 0;
    return dimensions
            .map((d) => d.score.numericValue)
            .reduce((a, b) => a + b) /
        dimensions.length;
  }

  /// Overall qualitative label derived from [overallScore].
  String get overallLabel {
    final score = overallScore;
    if (score >= 0.75) return 'Good';
    if (score >= 0.4) return 'Fair';
    return 'Poor';
  }

  /// Word count of the transcript.
  int get transcriptWordCount =>
      transcript.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  /// Word count of the summary.
  int get summaryWordCount =>
      summary.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  /// Compression ratio (summary words / transcript words).
  double get compressionRatio {
    if (transcriptWordCount == 0) return 0;
    return summaryWordCount / transcriptWordCount;
  }

  /// Processing time in seconds (display-friendly).
  double get processingTimeSec => processingTimeMs / 1000.0;

  @override
  List<Object?> get props => [
        transcript,
        keyIdeas,
        summary,
        dimensions,
        recordingDurationSeconds,
        processingTimeMs,
        promptUsed,
        completedAt,
        safetyResult,
        evaluationResult,
      ];
}
