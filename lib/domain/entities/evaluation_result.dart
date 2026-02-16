import 'package:equatable/equatable.dart';

/// Structured evaluation result from the Evaluation & Safety Framework.
///
/// Contains clarity and language proficiency scores (0–10 each),
/// reasoning for each, safety flag, and overall feedback.
///
/// JSON structure:
/// ```json
/// {
///   "clarity_score": number,
///   "clarity_reasoning": string,
///   "language_score": number,
///   "language_reasoning": string,
///   "safety_flag": boolean,
///   "safety_notes": string,
///   "overall_feedback": string
/// }
/// ```
class EvaluationResult extends Equatable {
  /// Clarity of Thought score (0–10).
  final double clarityScore;

  /// Explanation for the clarity score.
  final String clarityReasoning;

  /// Language Proficiency score (0–10).
  final double languageScore;

  /// Explanation for the language score.
  final String languageReasoning;

  /// Whether the content was flagged as unsafe.
  ///
  /// When `true`, the scores should NOT be displayed — only the safety notes.
  final bool safetyFlag;

  /// Safety-related notes (e.g. reason for flagging, or "No issues detected").
  final String safetyNotes;

  /// Overall feedback combining all evaluation aspects.
  final String overallFeedback;

  const EvaluationResult({
    required this.clarityScore,
    required this.clarityReasoning,
    required this.languageScore,
    required this.languageReasoning,
    required this.safetyFlag,
    required this.safetyNotes,
    required this.overallFeedback,
  });

  /// Total combined score out of 20.
  double get totalScore => clarityScore + languageScore;

  /// Percentage of total possible score (0.0–1.0).
  double get totalPercentage => totalScore / 20.0;

  /// A qualitative label derived from total score.
  String get totalLabel {
    if (totalScore >= 18) return 'Excellent';
    if (totalScore >= 15) return 'Good';
    if (totalScore >= 12) return 'Above Average';
    if (totalScore >= 9) return 'Average';
    if (totalScore >= 6) return 'Below Average';
    return 'Needs Improvement';
  }

  /// Create a "safe but unable to evaluate" placeholder.
  factory EvaluationResult.safetyBlocked({
    required String safetyNotes,
  }) {
    return EvaluationResult(
      clarityScore: 0,
      clarityReasoning: 'Evaluation skipped due to safety concern.',
      languageScore: 0,
      languageReasoning: 'Evaluation skipped due to safety concern.',
      safetyFlag: true,
      safetyNotes: safetyNotes,
      overallFeedback:
          'Content was flagged by the safety preprocessor. '
          'Scores are not available.',
    );
  }

  /// Create a fallback when LLM output cannot be parsed.
  factory EvaluationResult.parseError({String? rawOutput}) {
    return EvaluationResult(
      clarityScore: 0,
      clarityReasoning: 'Could not parse evaluation output.',
      languageScore: 0,
      languageReasoning: 'Could not parse evaluation output.',
      safetyFlag: false,
      safetyNotes: 'No safety issues detected.',
      overallFeedback:
          'The model produced an unparseable response. '
          'Please try again.${rawOutput != null ? '\n\nRaw: $rawOutput' : ''}',
    );
  }

  @override
  List<Object?> get props => [
        clarityScore,
        clarityReasoning,
        languageScore,
        languageReasoning,
        safetyFlag,
        safetyNotes,
        overallFeedback,
      ];
}
