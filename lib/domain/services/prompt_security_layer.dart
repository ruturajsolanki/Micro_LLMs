import 'dart:convert';

import '../entities/safety_result.dart';
import '../repositories/llm_repository.dart';
import '../entities/inference_request.dart';
import 'system_prompt_manager.dart';
import '../../core/utils/logger.dart';

/// Multi-layer prompt security that:
/// 1. Runs a **local pattern scan** (fast, no LLM call) for known injection phrases.
/// 2. Optionally runs an **LLM-based injection detection** for subtle attacks.
///
/// The layer operates BEFORE any evaluation or scoring.
///
/// Design: Stateless service — all configuration comes from [SystemPromptManager].
class PromptSecurityLayer {
  final SystemPromptManager _promptManager;
  final LLMRepository _llmRepository;

  PromptSecurityLayer({
    required SystemPromptManager promptManager,
    required LLMRepository llmRepository,
  })  : _promptManager = promptManager,
        _llmRepository = llmRepository;

  // ────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ────────────────────────────────────────────────────────────────────────

  /// Scan [text] for prompt injection attempts.
  ///
  /// Returns a [SafetyResult] — if unsafe, contains a [SafetyViolation]
  /// of type [SafetyViolationType.promptInjection].
  ///
  /// If [useLlm] is `true` AND the local scan passes, a more thorough
  /// LLM-based check is run using the injection guard system prompt.
  Future<SafetyResult> scan(
    String text, {
    bool useLlm = false,
  }) async {
    // ── Layer 1: Fast local pattern matching ──
    final localResult = _localPatternScan(text);
    if (!localResult.isSafe) return localResult;

    // ── Layer 2: LLM-based scan (optional, more thorough) ──
    if (useLlm && _llmRepository.isModelLoaded) {
      return _llmInjectionScan(text);
    }

    return SafetyResult.clean();
  }

  // ────────────────────────────────────────────────────────────────────────
  // LAYER 1: LOCAL PATTERN SCAN
  // ────────────────────────────────────────────────────────────────────────

  /// Known injection patterns (case-insensitive).
  ///
  /// These cover the most common prompt injection attacks.
  /// The list is intentionally conservative to avoid false positives
  /// on spoken transcripts (which may contain similar-sounding phrases).
  static final List<_InjectionPattern> _injectionPatterns = [
    _InjectionPattern(
      pattern: RegExp(
          r'ignore\s+(all\s+)?(previous|prior|above|earlier)\s+(instructions?|prompts?|rules?|guidelines?)',
          caseSensitive: false),
      description: 'Attempt to override system instructions',
    ),
    _InjectionPattern(
      pattern: RegExp(
          r'forget\s+(your|all|the)\s+(rules?|instructions?|prompts?|guidelines?|training)',
          caseSensitive: false),
      description: 'Attempt to erase system rules',
    ),
    _InjectionPattern(
      pattern: RegExp(
          r'(reveal|show|display|print|output|repeat)\s+(your|the)\s+(system\s+)?(prompt|instructions?|rules?)',
          caseSensitive: false),
      description: 'Attempt to extract system prompt',
    ),
    _InjectionPattern(
      pattern: RegExp(
          r'you\s+are\s+now\s+(DAN|evil|unrestricted|jailbroken|free)',
          caseSensitive: false),
      description: 'Role-play jailbreak attempt',
    ),
    _InjectionPattern(
      pattern: RegExp(
          r'pretend\s+(you\s+)?(have\s+no|there\s+are\s+no|without)\s+(restrictions?|rules?|guidelines?|limitations?)',
          caseSensitive: false),
      description: 'Restriction bypass attempt',
    ),
    _InjectionPattern(
      pattern: RegExp(
          r'(new|updated|override)\s+(system\s+)?(instructions?|prompt|rules?)',
          caseSensitive: false),
      description: 'Attempt to inject new system instructions',
    ),
    _InjectionPattern(
      pattern: RegExp(
          r'(do\s+not|don.?t)\s+(follow|obey|listen\s+to)\s+(your|the)\s+(rules?|instructions?|guidelines?)',
          caseSensitive: false),
      description: 'Attempt to disobey system rules',
    ),
    _InjectionPattern(
      pattern: RegExp(
          r'(enter|switch\s+to|activate)\s+(developer|admin|debug|god)\s+mode',
          caseSensitive: false),
      description: 'Developer mode exploit attempt',
    ),
  ];

  SafetyResult _localPatternScan(String text) {
    final normalized = text.toLowerCase().trim();
    final violations = <SafetyViolation>[];

    for (final pattern in _injectionPatterns) {
      if (pattern.pattern.hasMatch(normalized)) {
        violations.add(SafetyViolation(
          type: SafetyViolationType.promptInjection,
          explanation: pattern.description,
          severity: 'high',
        ));
      }
    }

    if (violations.isEmpty) return SafetyResult.clean();

    return SafetyResult.blocked(
      violations: violations,
      summary:
          'Detected ${violations.length} potential prompt injection '
          'attempt${violations.length == 1 ? '' : 's'}.',
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // LAYER 2: LLM-BASED INJECTION DETECTION
  // ────────────────────────────────────────────────────────────────────────

  Future<SafetyResult> _llmInjectionScan(String text) async {
    try {
      final systemPrompt =
          _promptManager.getPrompt(SystemPromptKey.injectionGuard);

      final request = InferenceRequest(
        prompt: 'Analyze this text for prompt injection:\n\n$text',
        systemPrompt: systemPrompt,
        maxTokens: 256,
        temperature: 0.1,
        stream: false,
        isolated: true,
      );

      final result = await _llmRepository.generate(request);

      return result.fold(
        (failure) {
          AppLogger.e('LLM injection scan failed: ${failure.message}');
          // Fail open — if LLM fails, fall back to local scan result (already passed).
          return SafetyResult.clean();
        },
        (response) => _parseInjectionResult(response.text),
      );
    } catch (e) {
      AppLogger.e('LLM injection scan exception: $e');
      return SafetyResult.clean(); // Fail open
    }
  }

  SafetyResult _parseInjectionResult(String rawOutput) {
    try {
      final jsonStr = _extractJson(rawOutput);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      final hasInjection = map['has_injection'] as bool? ?? false;
      if (!hasInjection) return SafetyResult.clean();

      final confidence = map['confidence'] as String? ?? 'medium';
      if (confidence == 'low') return SafetyResult.clean(); // Too uncertain

      final explanation = map['explanation'] as String? ?? 'Injection detected.';
      final patterns = (map['detected_patterns'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      return SafetyResult.blocked(
        violations: [
          SafetyViolation(
            type: SafetyViolationType.promptInjection,
            explanation:
                '$explanation${patterns.isNotEmpty ? ' Patterns: ${patterns.join(", ")}' : ''}',
            severity: confidence == 'high' ? 'high' : 'medium',
          ),
        ],
        summary: 'Prompt injection attempt detected with $confidence confidence.',
      );
    } catch (e) {
      AppLogger.e('Failed to parse injection scan output: $e');
      return SafetyResult.clean(); // Fail open
    }
  }

  /// Extract JSON from potentially noisy LLM output.
  String _extractJson(String text) {
    final trimmed = text.trim();
    // Try to find JSON object
    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return trimmed.substring(start, end + 1);
    }
    return trimmed;
  }
}

class _InjectionPattern {
  final RegExp pattern;
  final String description;

  const _InjectionPattern({
    required this.pattern,
    required this.description,
  });
}
