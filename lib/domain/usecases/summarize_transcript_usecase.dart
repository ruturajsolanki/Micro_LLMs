import 'dart:async';

import 'package:equatable/equatable.dart';

import '../entities/benchmark_result.dart';
import '../entities/benchmark_prompt.dart';
import '../entities/evaluation_result.dart';
import '../entities/safety_result.dart';
import '../entities/inference_request.dart';
import '../repositories/llm_repository.dart';
import 'safety_preprocessor_usecase.dart';
import 'evaluation_usecase.dart';
import '../../core/utils/logger.dart';

/// Events emitted during the summarization pipeline.
sealed class SummarizationPipelineEvent {
  const SummarizationPipelineEvent();
}

/// A pipeline step has started.
final class PipelineStepStarted extends SummarizationPipelineEvent {
  final PipelineStep step;
  const PipelineStepStarted(this.step);
}

/// A pipeline step has completed.
final class PipelineStepCompleted extends SummarizationPipelineEvent {
  final PipelineStep step;
  final String result;
  const PipelineStepCompleted(this.step, this.result);
}

/// The entire pipeline has completed successfully.
final class PipelineCompleted extends SummarizationPipelineEvent {
  final BenchmarkResult result;
  const PipelineCompleted(this.result);
}

/// The pipeline was halted due to a safety violation.
final class PipelineSafetyBlocked extends SummarizationPipelineEvent {
  final SafetyResult safetyResult;
  const PipelineSafetyBlocked(this.safetyResult);
}

/// A pipeline error occurred.
final class PipelineError extends SummarizationPipelineEvent {
  final String message;
  final PipelineStep? failedStep;
  const PipelineError(this.message, {this.failedStep});
}

/// Steps in the summarization pipeline.
///
/// These are shown in the UI as step-by-step progress to reassure the user.
enum PipelineStep {
  transcribing,
  safetyScan,
  extractingKeyIdeas,
  summarizing,
  evaluating,
  evaluatingTranscript;

  String get label {
    switch (this) {
      case PipelineStep.transcribing:
        return 'Transcribing audio…';
      case PipelineStep.safetyScan:
        return 'Running safety checks…';
      case PipelineStep.extractingKeyIdeas:
        return 'Extracting key ideas…';
      case PipelineStep.summarizing:
        return 'Summarizing content…';
      case PipelineStep.evaluating:
        return 'Evaluating summary quality…';
      case PipelineStep.evaluatingTranscript:
        return 'Scoring clarity & language…';
    }
  }
}

/// Use case that runs the full summarization + evaluation + safety pipeline.
///
/// **Optimized pipeline** — merges independent LLM tasks into fewer calls
/// to minimize on-device inference wall-clock time (llama.cpp can only run
/// one inference at a time).
///
/// Pipeline (ordered):
/// 1. Transcription (already done during recording — marked complete quickly)
/// 2. **Safety scan** (local-only by default, ~instant)
/// 3. **Merged LLM Call 1**: Key idea extraction + Summarization
/// 4. **Merged LLM Call 2**: Summary quality benchmark + Transcript evaluation
///
/// Safety runs BEFORE evaluation. If safety fails, pipeline halts.
///
/// Each step emits progress events so the UI can display step-by-step status.
/// All LLM calls use `isolated: true` to avoid polluting the chat context.
class SummarizeTranscriptUseCase {
  final LLMRepository _llmRepository;
  final SafetyPreprocessorUseCase _safetyPreprocessor;
  final EvaluationUseCase _evaluationUseCase;

  SummarizeTranscriptUseCase({
    required LLMRepository llmRepository,
    required SafetyPreprocessorUseCase safetyPreprocessor,
    required EvaluationUseCase evaluationUseCase,
  })  : _llmRepository = llmRepository,
        _safetyPreprocessor = safetyPreprocessor,
        _evaluationUseCase = evaluationUseCase;

  /// Run the pipeline on the given transcript.
  Stream<SummarizationPipelineEvent> call(
      SummarizeTranscriptParams params) async* {
    final stopwatch = Stopwatch()..start();

    // Step 1: Transcription (already done during recording)
    yield const PipelineStepStarted(PipelineStep.transcribing);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    yield PipelineStepCompleted(PipelineStep.transcribing, params.transcript);

    // Step 2: Safety scan — local-only by default (instant, no LLM call)
    yield const PipelineStepStarted(PipelineStep.safetyScan);
    SafetyResult? safetyResult;
    try {
      safetyResult = await _safetyPreprocessor(
        params.transcript,
        useLlmForContent: false, // Skip LLM scan for speed
      );
    } catch (e) {
      AppLogger.e('Safety scan threw: $e');
      safetyResult = SafetyResult.clean();
    }

    if (!safetyResult.isSafe) {
      yield PipelineStepCompleted(
          PipelineStep.safetyScan, 'Content flagged: ${safetyResult.summary}');
      yield PipelineSafetyBlocked(safetyResult);
      return; // HALT — do NOT proceed to scoring
    }
    yield PipelineStepCompleted(PipelineStep.safetyScan, 'Passed');

    // ──────────────────────────────────────────────────────────────────────
    // MERGED LLM CALL 1: Key Ideas + Summary (single call, ~15s)
    // ──────────────────────────────────────────────────────────────────────
    yield const PipelineStepStarted(PipelineStep.extractingKeyIdeas);

    final mergedResult = await _runMergedKeyIdeasAndSummary(
      transcript: params.transcript,
      promptInstruction: params.prompt.instruction,
    );

    if (mergedResult == null) {
      yield const PipelineError(
        'Failed to extract key ideas and summary',
        failedStep: PipelineStep.extractingKeyIdeas,
      );
      return;
    }

    final keyIdeasResult = mergedResult.keyIdeas;
    final summaryResult = mergedResult.summary;

    yield PipelineStepCompleted(
        PipelineStep.extractingKeyIdeas, keyIdeasResult);
    yield const PipelineStepStarted(PipelineStep.summarizing);
    yield PipelineStepCompleted(PipelineStep.summarizing, summaryResult);

    // ──────────────────────────────────────────────────────────────────────
    // MERGED LLM CALL 2: Summary Quality + Transcript Evaluation (~15s)
    // Only runs if at least one evaluation type is enabled.
    // ──────────────────────────────────────────────────────────────────────
    List<BenchmarkDimension> dimensions = const [];
    EvaluationResult? evaluationResult;

    final needsBenchmark = params.includeBenchmark;
    final needsEvaluation = params.includeEvaluation;

    if (needsBenchmark || needsEvaluation) {
      if (needsBenchmark) {
        yield const PipelineStepStarted(PipelineStep.evaluating);
      }
      if (needsEvaluation) {
        yield const PipelineStepStarted(PipelineStep.evaluatingTranscript);
      }

      final evalMerged = await _runMergedEvaluation(
        transcript: params.transcript,
        summary: summaryResult,
        includeBenchmark: needsBenchmark,
        includeTranscriptEval: needsEvaluation,
      );

      if (evalMerged != null) {
        dimensions = evalMerged.dimensions;
        evaluationResult = evalMerged.evaluationResult;
      }

      if (needsBenchmark) {
        yield PipelineStepCompleted(
          PipelineStep.evaluating,
          dimensions.isEmpty ? 'Completed' : 'Scored ${dimensions.length} dimensions',
        );
      }
      if (needsEvaluation && evaluationResult != null) {
        yield PipelineStepCompleted(
          PipelineStep.evaluatingTranscript,
          'Clarity: ${evaluationResult.clarityScore}/10, '
          'Language: ${evaluationResult.languageScore}/10',
        );
      } else if (needsEvaluation) {
        evaluationResult = EvaluationResult.parseError(
            rawOutput: 'Evaluation could not be parsed.');
        yield PipelineStepCompleted(
          PipelineStep.evaluatingTranscript,
          'Evaluation completed with fallback',
        );
      }
    }

    stopwatch.stop();

    yield PipelineCompleted(BenchmarkResult(
      transcript: params.transcript,
      keyIdeas: keyIdeasResult,
      summary: summaryResult,
      dimensions: dimensions,
      recordingDurationSeconds: params.recordingDurationSeconds,
      processingTimeMs: stopwatch.elapsedMilliseconds,
      promptUsed: params.prompt.instruction,
      completedAt: DateTime.now(),
      safetyResult: safetyResult,
      evaluationResult: evaluationResult,
    ));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MERGED LLM CALL 1: Key Ideas + Summary
  // ══════════════════════════════════════════════════════════════════════════

  Future<_KeyIdeasAndSummary?> _runMergedKeyIdeasAndSummary({
    required String transcript,
    required String promptInstruction,
  }) async {
    final result = await _runLLMStep(
      systemPrompt:
          'You are an expert content analyst and summarizer. '
          'Perform BOTH tasks below on the given transcript. '
          'Separate them with the exact markers shown.\n\n'
          'TASK 1 — KEY IDEAS:\n'
          '$promptInstruction\n'
          'List the key ideas, themes, and important points as concise bullet points.\n\n'
          'TASK 2 — SUMMARY:\n'
          'Write a clear, well-structured summary of the content.\n\n'
          'FORMAT your response EXACTLY as:\n'
          '===KEY_IDEAS===\n'
          '(bullet points here)\n'
          '===SUMMARY===\n'
          '(summary text here)',
      userPrompt: transcript,
      maxTokens: 512,
      temperature: 0.4,
    );

    if (result == null) return null;

    return _parseKeyIdeasAndSummary(result);
  }

  _KeyIdeasAndSummary _parseKeyIdeasAndSummary(String raw) {
    // Try structured parsing with markers
    final keyIdeasMarker = RegExp(r'===\s*KEY[_ ]?IDEAS\s*===', caseSensitive: false);
    final summaryMarker = RegExp(r'===\s*SUMMARY\s*===', caseSensitive: false);

    final kiMatch = keyIdeasMarker.firstMatch(raw);
    final sumMatch = summaryMarker.firstMatch(raw);

    if (kiMatch != null && sumMatch != null && sumMatch.start > kiMatch.end) {
      final keyIdeas = raw.substring(kiMatch.end, sumMatch.start).trim();
      final summary = raw.substring(sumMatch.end).trim();
      if (keyIdeas.isNotEmpty && summary.isNotEmpty) {
        return _KeyIdeasAndSummary(keyIdeas: keyIdeas, summary: summary);
      }
    }

    // Fallback: split roughly in half by looking for common delimiters
    final lines = raw.split('\n');
    final midpoint = lines.length ~/ 2;

    // Look for a natural break (empty line, header, etc.)
    int splitAt = midpoint;
    for (int i = midpoint - 2; i <= midpoint + 2 && i < lines.length; i++) {
      if (i >= 0 && lines[i].trim().isEmpty) {
        splitAt = i;
        break;
      }
    }

    final keyIdeas = lines.take(splitAt).join('\n').trim();
    final summary = lines.skip(splitAt).join('\n').trim();

    return _KeyIdeasAndSummary(
      keyIdeas: keyIdeas.isNotEmpty ? keyIdeas : raw,
      summary: summary.isNotEmpty ? summary : raw,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MERGED LLM CALL 2: Summary Quality + Transcript Evaluation
  // ══════════════════════════════════════════════════════════════════════════

  Future<_MergedEvaluationResult?> _runMergedEvaluation({
    required String transcript,
    required String summary,
    required bool includeBenchmark,
    required bool includeTranscriptEval,
  }) async {
    final promptParts = <String>[
      'You are a strict evaluator. Perform the requested evaluations below.',
    ];

    if (includeBenchmark) {
      promptParts.add(
        'TASK A — SUMMARY QUALITY:\n'
        'Rate each dimension as Good, Fair, or Poor with a brief explanation.\n'
        'Dimensions: Relevance, Coverage, Coherence, Conciseness, Faithfulness.\n'
        'Format:\n'
        'Relevance: [Good/Fair/Poor] - [explanation]\n'
        'Coverage: [Good/Fair/Poor] - [explanation]\n'
        'Coherence: [Good/Fair/Poor] - [explanation]\n'
        'Conciseness: [Good/Fair/Poor] - [explanation]\n'
        'Faithfulness: [Good/Fair/Poor] - [explanation]',
      );
    }

    if (includeTranscriptEval) {
      promptParts.add(
        'TASK B — TRANSCRIPT SCORING (be VERY strict, most speakers score 3-6):\n'
        'Score the ORIGINAL TRANSCRIPT (not the summary) on TWO parameters.\n'
        'If speaker repeats, rambles, or lacks structure → Clarity ≤5. '
        'If grammar errors, wrong tenses, broken sentences → Language ≤5.\n\n'
        'Clarity of Thought (1-10): intro→main points→conclusion, elaboration, no repetition.\n'
        '9-10: professional | 7-8: good, minor gaps | 5-6: moderate, disjointed | 3-4: poor, random | 1-2: incoherent\n\n'
        'Language Proficiency (1-10): grammar, tenses, vocabulary, fluency, no fillers.\n'
        '9-10: excellent | 7-8: good, minor errors | 5-6: noticeable errors | 3-4: frequent mistakes | 1-2: very limited\n\n'
        'Format as JSON:\n'
        '{"clarity_score":<n>,"clarity_reasoning":"<cite problems>","language_score":<n>,'
        '"language_reasoning":"<cite errors>","safety_flag":false,'
        '"safety_notes":"None","overall_feedback":"<honest 2-3 sentences>"}',
      );
    }

    if (includeBenchmark && includeTranscriptEval) {
      promptParts.add(
        'Separate the two tasks with: ===TASK_B===',
      );
    }

    final userPrompt = StringBuffer();
    if (includeBenchmark) {
      userPrompt.writeln('ORIGINAL TRANSCRIPT:\n$transcript\n');
      userPrompt.writeln('SUMMARY TO EVALUATE:\n$summary');
    } else {
      userPrompt.writeln('TRANSCRIPT TO EVALUATE:\n$transcript');
    }

    final result = await _runLLMStep(
      systemPrompt: promptParts.join('\n\n'),
      userPrompt: userPrompt.toString(),
      maxTokens: 512,
      temperature: 0.3,
    );

    if (result == null) return null;

    return _parseMergedEvaluation(
      result,
      includeBenchmark: includeBenchmark,
      includeTranscriptEval: includeTranscriptEval,
    );
  }

  _MergedEvaluationResult _parseMergedEvaluation(
    String raw, {
    required bool includeBenchmark,
    required bool includeTranscriptEval,
  }) {
    List<BenchmarkDimension> dimensions = const [];
    EvaluationResult? evaluationResult;

    if (includeBenchmark && includeTranscriptEval) {
      // Split on task marker
      final marker = RegExp(r'===\s*TASK[_ ]?B\s*===', caseSensitive: false);
      final match = marker.firstMatch(raw);

      if (match != null) {
        final taskA = raw.substring(0, match.start).trim();
        final taskB = raw.substring(match.end).trim();
        dimensions = _parseBenchmarkDimensions(taskA);
        evaluationResult = _evaluationUseCase.parseRawOutput(taskB);
      } else {
        // No marker found — try to extract JSON for eval, rest for benchmark
        dimensions = _parseBenchmarkDimensions(raw);
        evaluationResult = _evaluationUseCase.parseRawOutput(raw);
      }
    } else if (includeBenchmark) {
      dimensions = _parseBenchmarkDimensions(raw);
    } else if (includeTranscriptEval) {
      evaluationResult = _evaluationUseCase.parseRawOutput(raw);
    }

    return _MergedEvaluationResult(
      dimensions: dimensions,
      evaluationResult: evaluationResult,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // COMMON HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  /// Run a single LLM inference step and return the full text result.
  ///
  /// Uses `isolated: true` so benchmark calls don't pollute the chat KV-cache.
  Future<String?> _runLLMStep({
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 512,
    double temperature = 0.5,
  }) async {
    if (!_llmRepository.isModelLoaded) {
      AppLogger.e('LLM not loaded during benchmark pipeline');
      return null;
    }

    final request = InferenceRequest(
      prompt: userPrompt,
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
      temperature: temperature,
      stream: false,
      isolated: true,
    );

    final result = await _llmRepository.generate(request);
    return result.fold(
      (failure) {
        AppLogger.e('LLM pipeline step failed: ${failure.message}');
        return null;
      },
      (response) {
        AppLogger.i('Pipeline LLM raw output (${response.completionTokens} tokens, '
            '${response.totalTimeMs}ms):\n${response.text.trim()}');
        return response.text.trim();
      },
    );
  }

  /// Parse the LLM evaluation output into structured [BenchmarkDimension]s.
  List<BenchmarkDimension> _parseBenchmarkDimensions(String evalText) {
    final dimensions = <BenchmarkDimension>[];

    final dimensionDefs = {
      'Relevance': 'Did the summary reflect the main ideas?',
      'Coverage': 'Were important points missed?',
      'Coherence': 'Is the summary logically structured?',
      'Conciseness': 'Is it appropriately brief?',
      'Faithfulness': 'No hallucinated information?',
    };

    for (final entry in dimensionDefs.entries) {
      final name = entry.key;
      final description = entry.value;

      final regex = RegExp(
        '${RegExp.escape(name)}\\s*:\\s*(Good|Fair|Poor)\\s*[-–—]?\\s*(.*)',
        caseSensitive: false,
      );

      final match = regex.firstMatch(evalText);

      BenchmarkScore score;
      String explanation;

      if (match != null) {
        final scoreStr = match.group(1)?.toLowerCase() ?? 'fair';
        score = switch (scoreStr) {
          'good' => BenchmarkScore.good,
          'poor' => BenchmarkScore.poor,
          _ => BenchmarkScore.fair,
        };
        explanation = match.group(2)?.trim() ?? 'No explanation provided.';
        if (explanation.isEmpty) explanation = 'No explanation provided.';
      } else {
        score = BenchmarkScore.fair;
        explanation = 'Could not parse evaluation for this dimension.';
      }

      dimensions.add(BenchmarkDimension(
        name: name,
        description: description,
        score: score,
        explanation: explanation,
      ));
    }

    return dimensions;
  }

  /// Cancel the current pipeline.
  void cancel() {
    _llmRepository.cancelGeneration();
  }
}

/// Result of the merged key ideas + summary LLM call.
class _KeyIdeasAndSummary {
  final String keyIdeas;
  final String summary;
  const _KeyIdeasAndSummary({required this.keyIdeas, required this.summary});
}

/// Result of the merged evaluation LLM call.
class _MergedEvaluationResult {
  final List<BenchmarkDimension> dimensions;
  final EvaluationResult? evaluationResult;
  const _MergedEvaluationResult({
    required this.dimensions,
    this.evaluationResult,
  });
}

/// Parameters for the summarization pipeline.
class SummarizeTranscriptParams extends Equatable {
  /// The transcript text to summarize.
  final String transcript;

  /// The prompt configuration to use.
  final BenchmarkPrompt prompt;

  /// Duration of the recording in seconds.
  final int recordingDurationSeconds;

  /// Whether to run the summary quality benchmark evaluation step.
  ///
  /// When false, the pipeline skips the rubric evaluation (saving an LLM call).
  final bool includeBenchmark;

  /// Whether to run the Clarity + Language transcript evaluation step.
  ///
  /// When false, the pipeline skips transcript scoring (saving an LLM call).
  final bool includeEvaluation;

  const SummarizeTranscriptParams({
    required this.transcript,
    required this.prompt,
    required this.recordingDurationSeconds,
    this.includeBenchmark = true,
    this.includeEvaluation = true,
  });

  @override
  List<Object?> get props => [
        transcript,
        prompt,
        recordingDurationSeconds,
        includeBenchmark,
        includeEvaluation,
      ];
}
