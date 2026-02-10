import 'dart:async';

import 'package:equatable/equatable.dart';

import '../entities/benchmark_result.dart';
import '../entities/benchmark_prompt.dart';
import '../entities/inference_request.dart';
import '../repositories/llm_repository.dart';
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
  extractingKeyIdeas,
  summarizing,
  evaluating;

  String get label {
    switch (this) {
      case PipelineStep.transcribing:
        return 'Transcribing audio…';
      case PipelineStep.extractingKeyIdeas:
        return 'Extracting key ideas…';
      case PipelineStep.summarizing:
        return 'Summarizing content…';
      case PipelineStep.evaluating:
        return 'Evaluating relevance…';
    }
  }
}

/// Use case that runs the full summarization + benchmark pipeline.
///
/// Pipeline:
/// 1. Transcription (already done during recording — marked complete quickly)
/// 2. Key idea extraction (LLM call)
/// 3. Summarization (LLM call with user-configurable prompt)
/// 4. Benchmark evaluation (LLM call with rubric)
///
/// Each step emits progress events so the UI can display step-by-step status.
/// All LLM calls use `isolated: true` to avoid polluting the chat context.
class SummarizeTranscriptUseCase {
  final LLMRepository _llmRepository;

  SummarizeTranscriptUseCase({required LLMRepository llmRepository})
      : _llmRepository = llmRepository;

  /// Run the pipeline on the given transcript.
  Stream<SummarizationPipelineEvent> call(
      SummarizeTranscriptParams params) async* {
    final stopwatch = Stopwatch()..start();

    // Step 1: Transcription (already done during recording)
    yield const PipelineStepStarted(PipelineStep.transcribing);
    await Future.delayed(const Duration(milliseconds: 400));
    yield PipelineStepCompleted(PipelineStep.transcribing, params.transcript);

    // Step 2: Extract key ideas
    yield const PipelineStepStarted(PipelineStep.extractingKeyIdeas);
    final keyIdeasResult = await _runLLMStep(
      systemPrompt:
          'You are an expert content analyst. Extract the key ideas, themes, '
          'and important points from the given text. Be concise and use bullet points.',
      userPrompt:
          'Extract the key ideas from the following text:\n\n${params.transcript}',
      maxTokens: 384,
    );

    if (keyIdeasResult == null) {
      yield const PipelineError(
        'Failed to extract key ideas',
        failedStep: PipelineStep.extractingKeyIdeas,
      );
      return;
    }
    yield PipelineStepCompleted(
        PipelineStep.extractingKeyIdeas, keyIdeasResult);

    // Step 3: Summarize using the selected prompt
    yield const PipelineStepStarted(PipelineStep.summarizing);
    final summaryResult = await _runLLMStep(
      systemPrompt: params.prompt.instruction,
      userPrompt: 'Content to process:\n\n${params.transcript}',
      maxTokens: 512,
    );

    if (summaryResult == null) {
      yield const PipelineError(
        'Failed to generate summary',
        failedStep: PipelineStep.summarizing,
      );
      return;
    }
    yield PipelineStepCompleted(PipelineStep.summarizing, summaryResult);

    // Step 4 (optional): Evaluate with rubric
    List<BenchmarkDimension> dimensions = const [];

    if (params.includeBenchmark) {
      yield const PipelineStepStarted(PipelineStep.evaluating);
      final evalResult = await _runLLMStep(
        systemPrompt:
            '''You are a quality evaluator. Score the following summary against its source text.
Rate each dimension as exactly one of: Good, Fair, or Poor.
For each dimension, provide a one-sentence explanation.

Dimensions:
1. Relevance - Does the summary reflect the main ideas?
2. Coverage - Are important points included?
3. Coherence - Is the summary logically structured?
4. Conciseness - Is it appropriately brief?
5. Faithfulness - No hallucinated information?

Format your response EXACTLY as:
Relevance: [Good/Fair/Poor] - [explanation]
Coverage: [Good/Fair/Poor] - [explanation]
Coherence: [Good/Fair/Poor] - [explanation]
Conciseness: [Good/Fair/Poor] - [explanation]
Faithfulness: [Good/Fair/Poor] - [explanation]''',
        userPrompt:
            'Original text:\n${params.transcript}\n\nSummary to evaluate:\n$summaryResult',
        maxTokens: 384,
        temperature: 0.3,
      );

      if (evalResult == null) {
        yield const PipelineError(
          'Failed to evaluate benchmark',
          failedStep: PipelineStep.evaluating,
        );
        return;
      }
      yield PipelineStepCompleted(PipelineStep.evaluating, evalResult);

      // Parse evaluation into structured dimensions
      dimensions = _parseEvaluation(evalResult);
    }

    stopwatch.stop();

    // Emit final result
    yield PipelineCompleted(BenchmarkResult(
      transcript: params.transcript,
      keyIdeas: keyIdeasResult,
      summary: summaryResult,
      dimensions: dimensions,
      recordingDurationSeconds: params.recordingDurationSeconds,
      processingTimeMs: stopwatch.elapsedMilliseconds,
      promptUsed: params.prompt.instruction,
      completedAt: DateTime.now(),
    ));
  }

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
      (response) => response.text.trim(),
    );
  }

  /// Parse the LLM evaluation output into structured [BenchmarkDimension]s.
  List<BenchmarkDimension> _parseEvaluation(String evalText) {
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

      // Try to parse "Name: Score - explanation"
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

/// Parameters for the summarization pipeline.
class SummarizeTranscriptParams extends Equatable {
  /// The transcript text to summarize.
  final String transcript;

  /// The prompt configuration to use.
  final BenchmarkPrompt prompt;

  /// Duration of the recording in seconds.
  final int recordingDurationSeconds;

  /// Whether to run the benchmark evaluation step.
  ///
  /// When false, the pipeline stops after summarization and skips the
  /// rubric evaluation (saving an LLM call and reducing processing time).
  final bool includeBenchmark;

  const SummarizeTranscriptParams({
    required this.transcript,
    required this.prompt,
    required this.recordingDurationSeconds,
    this.includeBenchmark = true,
  });

  @override
  List<Object?> get props =>
      [transcript, prompt, recordingDurationSeconds, includeBenchmark];
}
