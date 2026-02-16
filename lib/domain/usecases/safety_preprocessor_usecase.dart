import 'dart:convert';

import '../entities/safety_result.dart';
import '../entities/inference_request.dart';
import '../repositories/llm_repository.dart';
import '../services/system_prompt_manager.dart';
import '../services/prompt_security_layer.dart';
import '../../core/utils/logger.dart';

/// Pre-processes a transcript for safety BEFORE any evaluation or scoring.
///
/// Safety pipeline order:
/// 1. **Prompt injection check** — via [PromptSecurityLayer]
/// 2. **Content safety scan** — local keyword + LLM-based analysis
///
/// If ANY layer detects unsafe content, a structured [SafetyResult] with
/// `isSafe == false` is returned, and the caller MUST NOT proceed to scoring.
///
/// Follows Clean Architecture: no UI logic, no side effects, stateless.
class SafetyPreprocessorUseCase {
  final LLMRepository _llmRepository;
  final SystemPromptManager _promptManager;
  final PromptSecurityLayer _securityLayer;

  SafetyPreprocessorUseCase({
    required LLMRepository llmRepository,
    required SystemPromptManager promptManager,
    required PromptSecurityLayer securityLayer,
  })  : _llmRepository = llmRepository,
        _promptManager = promptManager,
        _securityLayer = securityLayer;

  /// Run safety checks on [transcript].
  ///
  /// Returns [SafetyResult.clean()] if all checks pass.
  /// Returns [SafetyResult.blocked(...)] with violations if unsafe.
  ///
  /// The [useLlmForInjection] flag controls whether the more expensive
  /// LLM-based injection scan is used (defaults to false for speed).
  ///
  /// The [useLlmForContent] flag controls whether the LLM-based content
  /// safety scan is used (defaults to false for speed). The local regex
  /// scan already covers common unsafe patterns. Set to true for maximum
  /// safety coverage at the cost of an extra ~10s LLM call.
  Future<SafetyResult> call(
    String transcript, {
    bool useLlmForInjection = false,
    bool useLlmForContent = false,
  }) async {
    if (transcript.trim().isEmpty) {
      return SafetyResult.clean();
    }

    // ── Step 1: Prompt injection detection ──
    final injectionResult = await _securityLayer.scan(
      transcript,
      useLlm: useLlmForInjection,
    );
    if (!injectionResult.isSafe) {
      AppLogger.w('Safety: prompt injection detected');
      return injectionResult;
    }

    // ── Step 2: Local keyword pre-scan ──
    final localResult = _localContentScan(transcript);
    if (!localResult.isSafe) {
      AppLogger.w('Safety: local content scan flagged content');
      return localResult;
    }

    // ── Step 3 (optional): LLM-based content safety scan ──
    // Skipped by default for speed. The local scan covers the most
    // common unsafe patterns; the LLM scan adds ~10s per call.
    if (useLlmForContent && _llmRepository.isModelLoaded) {
      final llmResult = await _llmContentScan(transcript);
      if (!llmResult.isSafe) {
        AppLogger.w('Safety: LLM content scan flagged content');
        return llmResult;
      }
    }

    return SafetyResult.clean();
  }

  // ────────────────────────────────────────────────────────────────────────
  // LOCAL KEYWORD SCAN
  // ────────────────────────────────────────────────────────────────────────

  /// Fast local scan for obviously unsafe content.
  ///
  /// Uses regex patterns for common profanity and unsafe phrases.
  /// Intentionally has a high threshold to avoid false positives on
  /// legitimate speech-to-text output.
  SafetyResult _localContentScan(String text) {
    final normalized = text.toLowerCase();
    final violations = <SafetyViolation>[];

    // Self-harm keywords (high priority, check first)
    for (final pattern in _selfHarmPatterns) {
      if (pattern.hasMatch(normalized)) {
        violations.add(const SafetyViolation(
          type: SafetyViolationType.selfHarm,
          explanation:
              'Content contains references to self-harm or harmful behavior.',
          severity: 'high',
        ));
        break; // One violation per category is sufficient
      }
    }

    // Hate speech patterns
    for (final pattern in _hateSpeechPatterns) {
      if (pattern.hasMatch(normalized)) {
        violations.add(const SafetyViolation(
          type: SafetyViolationType.hateSpeech,
          explanation:
              'Content contains language targeting individuals or groups.',
          severity: 'high',
        ));
        break;
      }
    }

    // Illegal instruction patterns
    for (final pattern in _illegalPatterns) {
      if (pattern.hasMatch(normalized)) {
        violations.add(const SafetyViolation(
          type: SafetyViolationType.illegalInstructions,
          explanation:
              'Content contains references to illegal activities or instructions.',
          severity: 'high',
        ));
        break;
      }
    }

    if (violations.isEmpty) return SafetyResult.clean();

    return SafetyResult.blocked(
      violations: violations,
      summary:
          'Content flagged for ${violations.map((v) => v.type.label).join(", ")}.',
    );
  }

  // Patterns are intentionally broad but require context to reduce false positives.
  // In a production app these would be more sophisticated (ML-based).

  static final List<RegExp> _selfHarmPatterns = [
    RegExp(r'(how\s+to|ways\s+to|methods?\s+(of|for))\s+(kill|hurt|harm)\s+(myself|yourself|oneself)',
        caseSensitive: false),
    RegExp(r'(i\s+want\s+to|going\s+to|plan\s+to)\s+(kill|end|harm)\s+(myself|my\s+life)',
        caseSensitive: false),
    RegExp(r'commit\s+suicide', caseSensitive: false),
    RegExp(r'(encourage|promote)\s+(self[- ]?harm|suicide|cutting)',
        caseSensitive: false),
  ];

  static final List<RegExp> _hateSpeechPatterns = [
    RegExp(r'(kill|eliminate|exterminate|eradicate)\s+(all\s+)?(jews|muslims|christians|blacks|whites|asians|gays|transgenders?)',
        caseSensitive: false),
    RegExp(r'(death\s+to|destroy)\s+(all\s+)?(jews|muslims|christians|blacks|whites|asians|immigrants)',
        caseSensitive: false),
    RegExp(r'(racial|ethnic)\s+cleansing', caseSensitive: false),
  ];

  static final List<RegExp> _illegalPatterns = [
    RegExp(r'how\s+to\s+(make|build|create|construct)\s+(a\s+)?(bomb|explosive|weapon|gun)',
        caseSensitive: false),
    RegExp(r'how\s+to\s+(hack|break\s+into|exploit)\s+(a\s+)?(bank|system|server|account)',
        caseSensitive: false),
    RegExp(r'how\s+to\s+(cook|make|synthesize|produce)\s+(meth|cocaine|heroin|fentanyl)',
        caseSensitive: false),
  ];

  // ────────────────────────────────────────────────────────────────────────
  // LLM-BASED CONTENT SAFETY SCAN
  // ────────────────────────────────────────────────────────────────────────

  Future<SafetyResult> _llmContentScan(String transcript) async {
    try {
      final systemPrompt =
          _promptManager.getPrompt(SystemPromptKey.globalSafety);

      final request = InferenceRequest(
        prompt: 'Analyze this transcript for safety:\n\n$transcript',
        systemPrompt: systemPrompt,
        maxTokens: 256,
        temperature: 0.1,
        stream: false,
        isolated: true,
      );

      final result = await _llmRepository.generate(request);

      return result.fold(
        (failure) {
          AppLogger.e('LLM safety scan failed: ${failure.message}');
          // Fail open — if LLM scan fails, rely on local scan (already passed).
          return SafetyResult.clean();
        },
        (response) => _parseSafetyOutput(response.text),
      );
    } catch (e) {
      AppLogger.e('LLM safety scan exception: $e');
      return SafetyResult.clean(); // Fail open
    }
  }

  SafetyResult _parseSafetyOutput(String rawOutput) {
    try {
      final jsonStr = _extractJson(rawOutput);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      final isSafe = map['is_safe'] as bool? ?? true;
      if (isSafe) return SafetyResult.clean();

      final rawViolations = map['violations'] as List<dynamic>? ?? [];
      final violations = rawViolations.map((v) {
        final vm = v as Map<String, dynamic>;
        return SafetyViolation(
          type: _parseViolationType(vm['type'] as String? ?? ''),
          explanation: vm['explanation'] as String? ?? 'Unsafe content detected.',
          severity: vm['severity'] as String? ?? 'high',
        );
      }).toList();

      final summary =
          map['summary'] as String? ?? 'Content flagged by safety scan.';

      return SafetyResult.blocked(
        violations: violations,
        summary: summary,
      );
    } catch (e) {
      AppLogger.e('Failed to parse safety scan output: $e');
      return SafetyResult.clean(); // Fail open
    }
  }

  SafetyViolationType _parseViolationType(String raw) {
    final normalized = raw.toLowerCase().replaceAll('_', '');
    if (normalized.contains('vulgar') || normalized.contains('profan')) {
      return SafetyViolationType.vulgarity;
    }
    if (normalized.contains('hate')) return SafetyViolationType.hateSpeech;
    if (normalized.contains('selfharm') || normalized.contains('self harm') ||
        normalized.contains('suicide')) {
      return SafetyViolationType.selfHarm;
    }
    if (normalized.contains('explicit') || normalized.contains('sexual')) {
      return SafetyViolationType.explicitContent;
    }
    if (normalized.contains('illegal') || normalized.contains('weapon') ||
        normalized.contains('drug')) {
      return SafetyViolationType.illegalInstructions;
    }
    if (normalized.contains('injection') || normalized.contains('prompt')) {
      return SafetyViolationType.promptInjection;
    }
    return SafetyViolationType.vulgarity; // fallback
  }

  String _extractJson(String text) {
    final trimmed = text.trim();
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return trimmed.substring(start, end + 1);
    }
    return trimmed;
  }
}
