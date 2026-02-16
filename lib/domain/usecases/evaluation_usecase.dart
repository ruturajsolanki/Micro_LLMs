import 'dart:convert';

import '../entities/evaluation_result.dart';
import '../entities/inference_request.dart';
import '../repositories/llm_repository.dart';
import '../services/system_prompt_manager.dart';
import '../../core/utils/logger.dart';

/// Evaluates a transcript using a strict scoring rubric.
///
/// Scores two dimensions:
/// - **Clarity of Thought** (0–10)
/// - **Language Proficiency** (0–10)
///
/// Uses the evaluation system prompt from [SystemPromptManager], which is
/// centralized, versioned, and user-editable.
///
/// IMPORTANT: This use case must ONLY be called AFTER safety checks pass.
/// It does NOT perform any safety validation itself.
///
/// Scoring policy:
/// - Conservative scoring (when in doubt, score lower).
/// - 9–10 only for near-native / professional performance.
/// - No score inflation; no hallucinated mistakes.
/// - Evaluate ONLY what exists in the transcript.
class EvaluationUseCase {
  final LLMRepository _llmRepository;
  final SystemPromptManager _promptManager;

  EvaluationUseCase({
    required LLMRepository llmRepository,
    required SystemPromptManager promptManager,
  })  : _llmRepository = llmRepository,
        _promptManager = promptManager;

  /// Evaluate the given [transcript] and return an [EvaluationResult].
  ///
  /// Returns [EvaluationResult.parseError()] if the model output
  /// cannot be parsed into the expected JSON structure. This ensures
  /// no crash on malformed model output.
  ///
  /// Retry-safe: can be called multiple times with the same input.
  Future<EvaluationResult> call(String transcript) async {
    if (transcript.trim().isEmpty) {
      return EvaluationResult.parseError(
          rawOutput: 'Empty transcript provided.');
    }

    if (!_llmRepository.isModelLoaded) {
      AppLogger.e('EvaluationUseCase: LLM not loaded');
      return EvaluationResult.parseError(
          rawOutput: 'LLM model not loaded.');
    }

    try {
      final systemPrompt =
          _promptManager.getPrompt(SystemPromptKey.evaluation);

      final request = InferenceRequest(
        prompt:
            'Evaluate the following spoken transcript:\n\n$transcript',
        systemPrompt: systemPrompt,
        maxTokens: 512,
        temperature: 0.2, // Low temperature for consistent scoring
        stream: false,
        isolated: true,
      );

      final result = await _llmRepository.generate(request);

      return result.fold(
        (failure) {
          AppLogger.e('EvaluationUseCase LLM call failed: ${failure.message}');
          return EvaluationResult.parseError(
              rawOutput: 'LLM inference failed: ${failure.message}');
        },
        (response) {
          AppLogger.i('EvaluationUseCase raw LLM output:\n${response.text}');
          return _parseEvaluationOutput(response.text);
        },
      );
    } catch (e, stack) {
      AppLogger.e('EvaluationUseCase exception: $e\n$stack');
      return EvaluationResult.parseError(rawOutput: e.toString());
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // OUTPUT PARSING
  // ────────────────────────────────────────────────────────────────────────

  /// Parse raw LLM output into an [EvaluationResult].
  ///
  /// Exposed publicly so that the merged pipeline in
  /// [SummarizeTranscriptUseCase] can reuse this parsing logic without
  /// duplicating it.
  ///
  /// Handles:
  /// - Clean JSON output
  /// - JSON embedded in surrounding text
  /// - Partial / malformed JSON (falls back to regex then [EvaluationResult.parseError])
  EvaluationResult parseRawOutput(String rawOutput) {
    return _parseEvaluationOutput(rawOutput);
  }

  EvaluationResult _parseEvaluationOutput(String rawOutput) {
    try {
      final jsonStr = _extractJson(rawOutput);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      // Parse scores with clamping to 0–10
      final clarityScore = _parseScore(map['clarity_score']);
      final languageScore = _parseScore(map['language_score']);

      // Parse string fields with defaults
      final clarityReasoning =
          (map['clarity_reasoning'] as String?)?.trim() ??
              'No reasoning provided.';
      final languageReasoning =
          (map['language_reasoning'] as String?)?.trim() ??
              'No reasoning provided.';
      final safetyFlag = map['safety_flag'] as bool? ?? false;
      final safetyNotes =
          (map['safety_notes'] as String?)?.trim() ??
              'No safety issues detected.';
      final overallFeedback =
          (map['overall_feedback'] as String?)?.trim() ??
              'No feedback provided.';

      return EvaluationResult(
        clarityScore: clarityScore,
        clarityReasoning: clarityReasoning,
        languageScore: languageScore,
        languageReasoning: languageReasoning,
        safetyFlag: safetyFlag,
        safetyNotes: safetyNotes,
        overallFeedback: overallFeedback,
      );
    } catch (e) {
      AppLogger.e('Failed to parse evaluation output: $e');
      // Try regex-based fallback
      return _regexFallbackParse(rawOutput);
    }
  }

  /// Fallback parser that extracts scores from unstructured text.
  ///
  /// Handles cases where the LLM produces text like:
  /// "Clarity of Thought: 7/10 - The speaker..."
  EvaluationResult _regexFallbackParse(String rawOutput) {
    try {
      final clarityMatch = RegExp(
        r'clarity[^:]*:\s*(\d+(?:\.\d+)?)\s*(?:/\s*10)?',
        caseSensitive: false,
      ).firstMatch(rawOutput);

      final languageMatch = RegExp(
        r'language[^:]*:\s*(\d+(?:\.\d+)?)\s*(?:/\s*10)?',
        caseSensitive: false,
      ).firstMatch(rawOutput);

      if (clarityMatch == null && languageMatch == null) {
        return EvaluationResult.parseError(rawOutput: rawOutput);
      }

      final clarityScore = clarityMatch != null
          ? _clampScore(double.tryParse(clarityMatch.group(1)!) ?? 0)
          : 0.0;
      final languageScore = languageMatch != null
          ? _clampScore(double.tryParse(languageMatch.group(1)!) ?? 0)
          : 0.0;

      return EvaluationResult(
        clarityScore: clarityScore,
        clarityReasoning: 'Extracted from unstructured output.',
        languageScore: languageScore,
        languageReasoning: 'Extracted from unstructured output.',
        safetyFlag: false,
        safetyNotes: 'No safety issues detected.',
        overallFeedback:
            'Scores were extracted from a non-standard model response. '
            'Results may be less reliable.',
      );
    } catch (e) {
      return EvaluationResult.parseError(rawOutput: rawOutput);
    }
  }

  /// Parse a score value, handling int, double, and string representations.
  double _parseScore(dynamic value) {
    if (value == null) return 0;
    if (value is num) return _clampScore(value.toDouble());
    if (value is String) {
      return _clampScore(double.tryParse(value) ?? 0);
    }
    return 0;
  }

  /// Clamp a score to the valid range [0, 10].
  double _clampScore(double value) => value.clamp(0.0, 10.0);

  /// Extract JSON from potentially noisy LLM output.
  String _extractJson(String text) {
    final trimmed = text.trim();

    // Try to find the outermost JSON object
    int braceDepth = 0;
    int? jsonStart;

    for (int i = 0; i < trimmed.length; i++) {
      if (trimmed[i] == '{') {
        jsonStart ??= i;
        braceDepth++;
      } else if (trimmed[i] == '}') {
        braceDepth--;
        if (braceDepth == 0 && jsonStart != null) {
          return trimmed.substring(jsonStart, i + 1);
        }
      }
    }

    // Fallback: simple substring
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return trimmed.substring(start, end + 1);
    }

    return trimmed;
  }
}
