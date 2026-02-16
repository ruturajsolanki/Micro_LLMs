import 'package:equatable/equatable.dart';

/// Categories of unsafe content detected by [SafetyPreprocessorUseCase].
enum SafetyViolationType {
  vulgarity,
  hateSpeech,
  selfHarm,
  explicitContent,
  illegalInstructions,
  promptInjection;

  String get label {
    switch (this) {
      case SafetyViolationType.vulgarity:
        return 'Vulgarity / Profanity';
      case SafetyViolationType.hateSpeech:
        return 'Hate Speech';
      case SafetyViolationType.selfHarm:
        return 'Self-Harm References';
      case SafetyViolationType.explicitContent:
        return 'Explicit Content';
      case SafetyViolationType.illegalInstructions:
        return 'Illegal Instructions';
      case SafetyViolationType.promptInjection:
        return 'Prompt Injection Attempt';
    }
  }
}

/// Result of the safety preprocessing step.
///
/// If [isSafe] is `false`, [violations] describes what was detected and
/// the pipeline must NOT proceed to scoring.
class SafetyResult extends Equatable {
  /// Whether the transcript passed all safety checks.
  final bool isSafe;

  /// List of detected violations (empty when safe).
  final List<SafetyViolation> violations;

  /// Human-readable summary of the safety analysis.
  final String summary;

  const SafetyResult({
    required this.isSafe,
    this.violations = const [],
    required this.summary,
  });

  /// Convenience: a clean pass.
  factory SafetyResult.clean() {
    return const SafetyResult(
      isSafe: true,
      violations: [],
      summary: 'No safety issues detected.',
    );
  }

  /// Convenience: blocked content.
  factory SafetyResult.blocked({
    required List<SafetyViolation> violations,
    required String summary,
  }) {
    return SafetyResult(
      isSafe: false,
      violations: violations,
      summary: summary,
    );
  }

  @override
  List<Object?> get props => [isSafe, violations, summary];
}

/// A single safety violation with type and explanation.
class SafetyViolation extends Equatable {
  /// Category of the violation.
  final SafetyViolationType type;

  /// Explanation of what was detected (without repeating the offending content).
  final String explanation;

  /// Severity: 'high', 'medium', 'low'.
  final String severity;

  const SafetyViolation({
    required this.type,
    required this.explanation,
    this.severity = 'high',
  });

  @override
  List<Object?> get props => [type, explanation, severity];
}
