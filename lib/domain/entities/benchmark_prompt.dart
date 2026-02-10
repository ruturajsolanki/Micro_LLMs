import 'package:equatable/equatable.dart';

/// Benchmark mode determines the type of analysis applied.
enum BenchmarkMode {
  generalSummary,
  goalsAndActions,
  technicalSummary,
  evaluation;

  String get label {
    switch (this) {
      case BenchmarkMode.generalSummary:
        return 'General Summary';
      case BenchmarkMode.goalsAndActions:
        return 'Goals & Actions';
      case BenchmarkMode.technicalSummary:
        return 'Technical Summary';
      case BenchmarkMode.evaluation:
        return 'Content Evaluation';
    }
  }

  String get description {
    switch (this) {
      case BenchmarkMode.generalSummary:
        return 'Summarize the content clearly for a general audience';
      case BenchmarkMode.goalsAndActions:
        return 'Extract goals, concerns, and action items';
      case BenchmarkMode.technicalSummary:
        return 'Produce a technical summary';
      case BenchmarkMode.evaluation:
        return 'Evaluate coherence, relevance, and clarity';
    }
  }
}

/// A configurable prompt preset for benchmarking.
///
/// Prompts are centralized, versioned, user-editable, and testable.
/// Built-in presets cannot be deleted but can be overridden.
class BenchmarkPrompt extends Equatable {
  /// Unique identifier.
  final String id;

  /// Display name.
  final String name;

  /// The summarization instruction text sent to the LLM.
  final String instruction;

  /// Benchmark mode category.
  final BenchmarkMode mode;

  /// Whether this is a built-in preset (cannot be deleted).
  final bool isBuiltIn;

  /// Version number for tracking changes.
  final int version;

  /// When created.
  final DateTime createdAt;

  const BenchmarkPrompt({
    required this.id,
    required this.name,
    required this.instruction,
    required this.mode,
    this.isBuiltIn = false,
    this.version = 1,
    required this.createdAt,
  });

  BenchmarkPrompt copyWith({
    String? name,
    String? instruction,
    BenchmarkMode? mode,
    int? version,
  }) {
    return BenchmarkPrompt(
      id: id,
      name: name ?? this.name,
      instruction: instruction ?? this.instruction,
      mode: mode ?? this.mode,
      isBuiltIn: isBuiltIn,
      version: version ?? this.version,
      createdAt: createdAt,
    );
  }

  @override
  List<Object?> get props =>
      [id, name, instruction, mode, isBuiltIn, version, createdAt];

  /// Default built-in prompts.
  static List<BenchmarkPrompt> get defaults {
    final now = DateTime.now();
    return [
      BenchmarkPrompt(
        id: 'general',
        name: 'General Summary',
        instruction:
            'Summarize the following content clearly and concisely for a general audience. '
            'Preserve the key points and main ideas. Use clear, simple language.',
        mode: BenchmarkMode.generalSummary,
        isBuiltIn: true,
        createdAt: now,
      ),
      BenchmarkPrompt(
        id: 'goals',
        name: 'Goals & Actions',
        instruction: 'Analyze the following content and extract:\n'
            '1. Goals mentioned\n'
            '2. Concerns raised\n'
            '3. Action items identified\n'
            'Present each category clearly with bullet points.',
        mode: BenchmarkMode.goalsAndActions,
        isBuiltIn: true,
        createdAt: now,
      ),
      BenchmarkPrompt(
        id: 'technical',
        name: 'Technical Summary',
        instruction:
            'Produce a technical summary of the following content. '
            'Focus on specific details, methodologies, and technical concepts mentioned. '
            'Use precise language and maintain technical accuracy.',
        mode: BenchmarkMode.technicalSummary,
        isBuiltIn: true,
        createdAt: now,
      ),
      BenchmarkPrompt(
        id: 'evaluation',
        name: 'Content Evaluation',
        instruction: 'Evaluate the following content for:\n'
            '- Coherence: How well-structured is the content?\n'
            '- Relevance: Is the content focused and on-topic?\n'
            '- Clarity: How clearly are ideas expressed?\n'
            'Provide a brief assessment for each dimension.',
        mode: BenchmarkMode.evaluation,
        isBuiltIn: true,
        createdAt: now,
      ),
    ];
  }
}
