import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injection.dart';
import '../../domain/entities/benchmark_result.dart';
import '../../domain/entities/benchmark_prompt.dart';
import '../../domain/entities/evaluation_result.dart';
import '../../domain/entities/safety_result.dart';
import '../../domain/usecases/summarize_transcript_usecase.dart';
import '../blocs/benchmark/benchmark_bloc.dart';
import '../blocs/settings/settings_bloc.dart';
import '../theme/ui_tokens.dart';
import 'prompt_editor_page.dart';

/// Main page for the Voice Benchmarking & Summarization feature.
///
/// Manages four UI states with smooth animated transitions:
/// 1. Idle — breathing record button, prompt selector, description
/// 2. Recording — pulsing rings, blinking dot, timer, live transcript, stop button
/// 3. Processing — step-by-step progress with animated check marks
/// 4. Result — staggered slide-up entrance for every card
class BenchmarkPage extends StatelessWidget {
  const BenchmarkPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<BenchmarkBloc>(
      create: (_) => sl<BenchmarkBloc>()..add(const BenchmarkStarted()),
      child: const _BenchmarkView(),
    );
  }
}

class _BenchmarkView extends StatelessWidget {
  const _BenchmarkView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Benchmark'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Edit prompts',
            onPressed: () => _openPromptEditor(context),
          ),
        ],
      ),
      body: BlocConsumer<BenchmarkBloc, BenchmarkState>(
        listener: (context, state) {
          if (state.errorMessage != null && state.errorMessage!.isNotEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        builder: (context, state) {
          return AnimatedSwitcher(
            duration: UiTokens.durSlow,
            switchInCurve: UiTokens.curveStandard,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: UiTokens.curveStandard,
                  )),
                  child: child,
                ),
              );
            },
            child: switch (state.status) {
              BenchmarkStatus.idle => _IdleView(key: const ValueKey('idle')),
              BenchmarkStatus.recording =>
                _RecordingView(key: const ValueKey('recording')),
              BenchmarkStatus.processing =>
                _ProcessingView(key: const ValueKey('processing')),
              BenchmarkStatus.result =>
                _ResultView(key: const ValueKey('result')),
              BenchmarkStatus.safetyBlocked =>
                _SafetyBlockedView(key: const ValueKey('safety')),
            },
          );
        },
      ),
    );
  }

  void _openPromptEditor(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PromptEditorPage()),
    );
    if (context.mounted) {
      context.read<BenchmarkBloc>().add(const BenchmarkPromptsRefreshed());
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// IDLE STATE
// ════════════════════════════════════════════════════════════════════════════

class _IdleView extends StatelessWidget {
  const _IdleView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<BenchmarkBloc>().state;

    return SafeArea(
      child: Padding(
        padding: UiTokens.pagePadding,
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: UiTokens.s32),

                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primary.withOpacity(0.1),
                  ),
                  child: Icon(
                    Icons.mic_none_rounded,
                    size: 40,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: UiTokens.s24),

                // Title
                Text(
                  'Voice Benchmark',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: UiTokens.s8),

                // Description
                Text(
                  'Record 2–3 minutes of speech to benchmark\n'
                  'the model\'s summarization quality.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: UiTokens.s32),

                // Prompt selector
                _PromptSelector(
                  prompts: state.prompts,
                  selected: state.selectedPrompt,
                  onSelected: (id) {
                    context
                        .read<BenchmarkBloc>()
                        .add(BenchmarkPromptSelected(promptId: id));
                  },
                ),
                const SizedBox(height: UiTokens.s20),

                // Benchmark toggle
                _BenchmarkToggle(
                  enabled: state.benchmarkEnabled,
                  onToggled: () {
                    context
                        .read<BenchmarkBloc>()
                        .add(const BenchmarkEvaluationToggled());
                  },
                ),
                const SizedBox(height: UiTokens.s8),

                // Transcript evaluation toggle (Clarity + Language)
                _EvaluationToggle(
                  enabled: state.evaluationEnabled,
                  onToggled: () {
                    context
                        .read<BenchmarkBloc>()
                        .add(const BenchmarkTranscriptEvalToggled());
                  },
                ),
                const SizedBox(height: UiTokens.s32),

                // Breathing record button
                _BreathingRecordButton(
                  onPressed: () {
                    final settings =
                        context.read<SettingsBloc>().state.settings;
                    context.read<BenchmarkBloc>().add(
                          BenchmarkRecordingStarted(
                            engine: settings.speechToTextEngine,
                            language: settings.sourceLanguage,
                            offlineOnly: settings.voiceSttOfflineOnly,
                            whisperModelId: settings.whisperModelId,
                          ),
                        );
                  },
                ),
                const SizedBox(height: UiTokens.s16),
                Text(
                  'Tap to start recording',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.45),
                  ),
                ),
                const SizedBox(height: UiTokens.s32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// RECORDING STATE
// ════════════════════════════════════════════════════════════════════════════

class _RecordingView extends StatelessWidget {
  const _RecordingView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<BenchmarkBloc>().state;

    return SafeArea(
      child: Padding(
        padding: UiTokens.pagePadding,
        child: Column(
          children: [
            const SizedBox(height: UiTokens.s8),

            // Compact recording indicator + timer row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _PulsingRecordIndicator(size: 72),
                const SizedBox(width: UiTokens.s16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.formattedDuration,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const _BlinkingListeningLabel(),
                  ],
                ),
              ],
            ),
            const SizedBox(height: UiTokens.s16),

            // Live transcript box (the main attraction)
            Expanded(
              child: _LiveTranscriptBox(
                confirmedText: state.accumulatedTranscript,
                partialText: state.partialText,
                wordCount: state.wordCount,
              ),
            ),
            const SizedBox(height: UiTokens.s16),

            // Stop button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  context
                      .read<BenchmarkBloc>()
                      .add(const BenchmarkRecordingStopped());
                },
                icon: const Icon(Icons.stop_rounded),
                label: const Text('Stop Recording'),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(UiTokens.r12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: UiTokens.s8),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// LIVE TRANSCRIPT BOX
// ════════════════════════════════════════════════════════════════════════════

/// Shows a polished live transcript during recording with:
/// - "LIVE" badge and word count header
/// - Confirmed words in normal weight, partial words in italic/lighter
/// - Blinking cursor at the end
/// - Auto-scroll to bottom
class _LiveTranscriptBox extends StatefulWidget {
  final String confirmedText;
  final String partialText;
  final int wordCount;

  const _LiveTranscriptBox({
    required this.confirmedText,
    required this.partialText,
    required this.wordCount,
  });

  @override
  State<_LiveTranscriptBox> createState() => _LiveTranscriptBoxState();
}

class _LiveTranscriptBoxState extends State<_LiveTranscriptBox> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant _LiveTranscriptBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-scroll when text changes.
    if (widget.confirmedText != oldWidget.confirmedText ||
        widget.partialText != oldWidget.partialText) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isEmpty =>
      widget.confirmedText.isEmpty && widget.partialText.isEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(UiTokens.r16),
        border: Border.all(color: cs.onSurface.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header: LIVE badge + word counter ──
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: UiTokens.s16,
              vertical: UiTokens.s8,
            ),
            decoration: BoxDecoration(
              color: cs.onSurface.withOpacity(0.03),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(UiTokens.r16),
              ),
            ),
            child: Row(
              children: [
                // "LIVE" pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.error.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cs.error,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'LIVE',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.error,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Word counter
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: child,
                  ),
                  child: Text(
                    '${widget.wordCount} word${widget.wordCount == 1 ? '' : 's'}',
                    key: ValueKey<int>(widget.wordCount),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.45),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Transcript body ──
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                UiTokens.s16,
                UiTokens.s8,
                UiTokens.s16,
                UiTokens.s16,
              ),
              child: _isEmpty
                  ? _buildPlaceholder(theme, cs)
                  : _buildTranscript(theme, cs),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(ThemeData theme, ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.mic_none_rounded,
            size: 36,
            color: cs.onSurface.withOpacity(0.18),
          ),
          const SizedBox(height: UiTokens.s8),
          Text(
            'Speak now — your words will appear here…',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface.withOpacity(0.35),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscript(ThemeData theme, ColorScheme cs) {
    return SingleChildScrollView(
      controller: _scrollController,
      child: RichText(
        text: TextSpan(
          children: [
            // Confirmed (final) text — normal weight
            if (widget.confirmedText.isNotEmpty)
              TextSpan(
                text: widget.confirmedText,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: cs.onSurface.withOpacity(0.85),
                  height: 1.6,
                ),
              ),
            // Separator space between confirmed & partial
            if (widget.confirmedText.isNotEmpty &&
                widget.partialText.isNotEmpty)
              const TextSpan(text: ' '),
            // Partial (in-progress) text — italic, lighter
            if (widget.partialText.isNotEmpty)
              TextSpan(
                text: widget.partialText,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: cs.primary.withOpacity(0.7),
                  fontStyle: FontStyle.italic,
                  height: 1.6,
                ),
              ),
            // Blinking cursor
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _BlinkingCursor(color: cs.primary),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// BLINKING CURSOR
// ════════════════════════════════════════════════════════════════════════════

/// A thin blinking line that appears at the end of the live transcript,
/// giving the feeling of a real-time typing experience.
class _BlinkingCursor extends StatefulWidget {
  final Color color;
  const _BlinkingCursor({required this.color});

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 2,
        height: 18,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PROCESSING STATE
// ════════════════════════════════════════════════════════════════════════════

class _ProcessingView extends StatelessWidget {
  const _ProcessingView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<BenchmarkBloc>().state;

    final visibleSteps = PipelineStep.values
        .where((step) {
          if (step == PipelineStep.evaluating) return state.benchmarkEnabled;
          if (step == PipelineStep.evaluatingTranscript) {
            return state.evaluationEnabled;
          }
          return true;
        })
        .toList();

    return SafeArea(
      child: Padding(
        padding: UiTokens.pagePadding,
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: UiTokens.s32),

                // Animated gradient spinner
                const _GradientSpinner(),
                const SizedBox(height: UiTokens.s24),

                Text(
                  'Processing…',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: UiTokens.s8),
                Text(
                  'This may take a moment.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: UiTokens.s32),

                // Step-by-step progress with animated icons
                ...visibleSteps.map(
                  (step) => _AnimatedPipelineStepRow(
                    step: step,
                    isCompleted: state.completedSteps.contains(step),
                    isCurrent: state.currentStep == step,
                  ),
                ),
                const SizedBox(height: UiTokens.s32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pipeline step row with animated icon transitions.
class _AnimatedPipelineStepRow extends StatefulWidget {
  final PipelineStep step;
  final bool isCompleted;
  final bool isCurrent;

  const _AnimatedPipelineStepRow({
    required this.step,
    required this.isCompleted,
    required this.isCurrent,
  });

  @override
  State<_AnimatedPipelineStepRow> createState() =>
      _AnimatedPipelineStepRowState();
}

class _AnimatedPipelineStepRowState extends State<_AnimatedPipelineStepRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _checkController;
  late Animation<double> _scaleAnim;
  bool _wasCompleted = false;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnim = CurvedAnimation(
      parent: _checkController,
      curve: Curves.elasticOut,
    );
    if (widget.isCompleted) {
      _checkController.value = 1.0;
      _wasCompleted = true;
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedPipelineStepRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCompleted && !_wasCompleted) {
      _wasCompleted = true;
      _checkController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _checkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;

    final Widget leading;
    final double textOpacity;

    if (widget.isCompleted) {
      leading = ScaleTransition(
        scale: _scaleAnim,
        child: Icon(Icons.check_circle, color: primary, size: 22),
      );
      textOpacity = 0.7;
    } else if (widget.isCurrent) {
      leading = SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          valueColor: AlwaysStoppedAnimation(primary),
        ),
      );
      textOpacity = 1.0;
    } else {
      leading = Icon(
        Icons.radio_button_unchecked,
        color: onSurface.withOpacity(0.25),
        size: 22,
      );
      textOpacity = 0.35;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            child: SizedBox(
              key: ValueKey(
                widget.isCompleted
                    ? 'done'
                    : widget.isCurrent
                        ? 'active'
                        : 'pending',
              ),
              width: 22,
              height: 22,
              child: leading,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: UiTokens.durMed,
              style: theme.textTheme.bodyLarge!.copyWith(
                color: onSurface.withOpacity(textOpacity),
                fontWeight:
                    widget.isCurrent ? FontWeight.w600 : FontWeight.w500,
              ),
              child: Text(widget.step.label),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SAFETY BLOCKED STATE
// ════════════════════════════════════════════════════════════════════════════

class _SafetyBlockedView extends StatelessWidget {
  const _SafetyBlockedView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = context.watch<BenchmarkBloc>().state;
    final safetyResult = state.safetyResult;

    return SafeArea(
      child: Padding(
        padding: UiTokens.pagePadding,
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: UiTokens.s32),

                // Warning icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.error.withOpacity(0.1),
                  ),
                  child: Icon(
                    Icons.shield_outlined,
                    size: 40,
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: UiTokens.s24),

                Text(
                  'Content Flagged',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: UiTokens.s8),

                Text(
                  'The safety preprocessor detected potentially unsafe content.\n'
                  'Scoring has been skipped.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: UiTokens.s24),

                // Safety details card
                if (safetyResult != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(UiTokens.s16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(UiTokens.r16),
                      border: Border.all(
                        color: theme.colorScheme.error.withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Safety Report',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: UiTokens.s12),
                        Text(
                          safetyResult.summary,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.5,
                          ),
                        ),
                        if (safetyResult.violations.isNotEmpty) ...[
                          const SizedBox(height: UiTokens.s12),
                          ...safetyResult.violations.map(
                            (v) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.error
                                          .withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      v.severity.toUpperCase(),
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: theme.colorScheme.error,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          v.type.label,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          v.explanation,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: theme
                                                .colorScheme.onSurface
                                                .withOpacity(0.6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: UiTokens.s32),

                // Action buttons
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      context
                          .read<BenchmarkBloc>()
                          .add(const BenchmarkReset());
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try Again'),
                  ),
                ),
                const SizedBox(height: UiTokens.s32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// RESULT STATE (staggered entrance)
// ════════════════════════════════════════════════════════════════════════════

class _ResultView extends StatefulWidget {
  const _ResultView({super.key});

  @override
  State<_ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<_ResultView>
    with SingleTickerProviderStateMixin {
  late AnimationController _staggerController;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _staggerController.dispose();
    super.dispose();
  }

  /// Build a slide-up + fade animation for a given [index] in the stagger.
  Animation<double> _entryAnimation(int index, int total) {
    final start = (index / total).clamp(0.0, 0.7);
    final end = ((index + 1) / total).clamp(start + 0.15, 1.0);
    return CurvedAnimation(
      parent: _staggerController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = context.watch<BenchmarkBloc>().state.result;

    if (result == null) return const SizedBox.shrink();

    final hasBenchmark = result.dimensions.isNotEmpty;
    final hasEvaluation = result.hasEvaluation;
    final isSafetyFlagged = result.isSafetyFlagged;

    // Count items for stagger timing
    int itemCount = 6; // header, subtitle, metrics, summary, key ideas, buttons
    if (isSafetyFlagged) itemCount += 1;
    if (hasEvaluation) itemCount += 3; // title + clarity card + language card
    if (hasBenchmark) itemCount += 1 + result.dimensions.length;
    int idx = 0;

    return SafeArea(
      child: ListView(
        padding: UiTokens.pagePadding,
        children: [
          // Header
          _StaggerEntry(
            animation: _entryAnimation(idx++, itemCount),
            child: Row(
              children: [
                Expanded(
                  child:
                      Text('Results', style: theme.textTheme.headlineSmall),
                ),
                if (hasBenchmark && !isSafetyFlagged)
                  _OverallBadge(label: result.overallLabel),
              ],
            ),
          ),

          _StaggerEntry(
            animation: _entryAnimation(idx++, itemCount),
            child: Padding(
              padding: const EdgeInsets.only(top: UiTokens.s4),
              child: Text(
                'Recorded ${_formatDuration(result.recordingDurationSeconds)} · '
                'Processed in ${result.processingTimeSec.toStringAsFixed(1)}s',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: UiTokens.s24),

          // Safety warning (if flagged but pipeline still completed)
          if (isSafetyFlagged) ...[
            _StaggerEntry(
              animation: _entryAnimation(idx++, itemCount),
              child: _SafetyWarningBanner(
                safetyResult: result.safetyResult!,
              ),
            ),
            const SizedBox(height: UiTokens.s16),
          ],

          // Evaluation scores (Clarity + Language) — only shown if not safety flagged
          if (hasEvaluation && !isSafetyFlagged) ...[
            _StaggerEntry(
              animation: _entryAnimation(idx++, itemCount),
              child: _EvaluationHeader(
                evaluation: result.evaluationResult!,
              ),
            ),
            const SizedBox(height: UiTokens.s12),
            _StaggerEntry(
              animation: _entryAnimation(idx++, itemCount),
              child: _EvaluationScoreCard(
                title: 'Clarity of Thought',
                score: result.evaluationResult!.clarityScore,
                reasoning: result.evaluationResult!.clarityReasoning,
                icon: Icons.psychology_outlined,
              ),
            ),
            const SizedBox(height: UiTokens.s8),
            _StaggerEntry(
              animation: _entryAnimation(idx++, itemCount),
              child: _EvaluationScoreCard(
                title: 'Language Proficiency',
                score: result.evaluationResult!.languageScore,
                reasoning: result.evaluationResult!.languageReasoning,
                icon: Icons.translate_outlined,
              ),
            ),
            const SizedBox(height: UiTokens.s16),

            // Overall feedback
            if (result.evaluationResult!.overallFeedback.isNotEmpty)
              _StaggerEntry(
                animation: _entryAnimation(idx - 1, itemCount),
                child: _ResultSection(
                  title: 'Evaluation Feedback',
                  content: result.evaluationResult!.overallFeedback,
                ),
              ),
            const SizedBox(height: UiTokens.s16),
          ],

          // Metrics row
          _StaggerEntry(
            animation: _entryAnimation(idx++, itemCount),
            child: _MetricsRow(result: result),
          ),
          const SizedBox(height: UiTokens.s24),

          // Summary
          _StaggerEntry(
            animation: _entryAnimation(idx++, itemCount),
            child: _ResultSection(title: 'Summary', content: result.summary),
          ),
          const SizedBox(height: UiTokens.s16),

          // Key ideas
          _StaggerEntry(
            animation: _entryAnimation(idx++, itemCount),
            child:
                _ResultSection(title: 'Key Ideas', content: result.keyIdeas),
          ),
          const SizedBox(height: UiTokens.s16),

          // Benchmark scores (only when evaluation was run and not safety flagged)
          if (hasBenchmark && !isSafetyFlagged) ...[
            _StaggerEntry(
              animation: _entryAnimation(idx++, itemCount),
              child: Text('Summary Quality Scores',
                  style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: UiTokens.s12),
            ...result.dimensions.map(
              (dim) {
                final anim = _entryAnimation(idx++, itemCount);
                return _StaggerEntry(
                  animation: anim,
                  child: _DimensionCard(dimension: dim),
                );
              },
            ),
            const SizedBox(height: UiTokens.s16),
          ],

          // Transcript (collapsed by default)
          _CollapsibleSection(
            title: 'Original Transcript',
            content: result.transcript,
          ),
          const SizedBox(height: UiTokens.s24),

          // Action buttons
          _StaggerEntry(
            animation: _entryAnimation(idx.clamp(0, itemCount - 1), itemCount),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      context
                          .read<BenchmarkBloc>()
                          .add(const BenchmarkReset());
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('New Benchmark'),
                  ),
                ),
                const SizedBox(width: UiTokens.s12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const PromptEditorPage()),
                      );
                    },
                    icon: const Icon(Icons.tune),
                    label: const Text('Edit Prompts'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: UiTokens.s32),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}

/// Slide-up + fade wrapper used to stagger-animate result items.
class _StaggerEntry extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _StaggerEntry({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Opacity(
          opacity: animation.value,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - animation.value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// REUSABLE WIDGETS
// ════════════════════════════════════════════════════════════════════════════

/// Prompt selector chips.
class _PromptSelector extends StatelessWidget {
  final List<BenchmarkPrompt> prompts;
  final BenchmarkPrompt selected;
  final ValueChanged<String> onSelected;

  const _PromptSelector({
    required this.prompts,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: prompts.map((p) {
        final isSelected = p.id == selected.id;
        return ChoiceChip(
          label: Text(p.name),
          selected: isSelected,
          onSelected: (_) => onSelected(p.id),
        );
      }).toList(),
    );
  }
}

/// Toggle to enable/disable benchmark evaluation scoring.
class _BenchmarkToggle extends StatelessWidget {
  final bool enabled;
  final VoidCallback onToggled;

  const _BenchmarkToggle({
    required this.enabled,
    required this.onToggled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(UiTokens.r12),
        border: Border.all(
          color: theme.colorScheme.onSurface.withOpacity(0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.speed_outlined,
            size: 18,
            color: theme.colorScheme.onSurface.withOpacity(0.55),
          ),
          const SizedBox(width: 8),
          Text(
            'Include benchmark scoring',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 28,
            child: Switch.adaptive(
              value: enabled,
              onChanged: (_) => onToggled(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Toggle to enable/disable transcript evaluation (Clarity + Language scoring).
class _EvaluationToggle extends StatelessWidget {
  final bool enabled;
  final VoidCallback onToggled;

  const _EvaluationToggle({
    required this.enabled,
    required this.onToggled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(UiTokens.r12),
        border: Border.all(
          color: theme.colorScheme.onSurface.withOpacity(0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.school_outlined,
            size: 18,
            color: theme.colorScheme.onSurface.withOpacity(0.55),
          ),
          const SizedBox(width: 8),
          Text(
            'Clarity & Language scoring',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 28,
            child: Switch.adaptive(
              value: enabled,
              onChanged: (_) => onToggled(),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// EVALUATION SCORE CARD
// ────────────────────────────────────────────────────────────────────────────

/// Displays a single evaluation dimension (Clarity or Language) with score bar.
class _EvaluationScoreCard extends StatelessWidget {
  final String title;
  final double score;
  final String reasoning;
  final IconData icon;

  const _EvaluationScoreCard({
    required this.title,
    required this.score,
    required this.reasoning,
    required this.icon,
  });

  Color _scoreColor(double score) {
    if (score >= 8) return Colors.green;
    if (score >= 6) return Colors.lightGreen;
    if (score >= 4) return Colors.orange;
    if (score >= 2) return Colors.deepOrange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _scoreColor(score);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(UiTokens.s16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(UiTokens.r16),
        border: Border.all(
          color: theme.colorScheme.onSurface.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
              // Score display
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${score.toStringAsFixed(1)}/10',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: UiTokens.s12),
          // Score bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: score / 10.0,
              minHeight: 6,
              backgroundColor: color.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: UiTokens.s12),
          Text(
            reasoning,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.65),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Header for the evaluation section showing total score.
class _EvaluationHeader extends StatelessWidget {
  final EvaluationResult evaluation;

  const _EvaluationHeader({required this.evaluation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            'Transcript Evaluation',
            style: theme.textTheme.titleMedium,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: theme.colorScheme.primary.withOpacity(0.3),
            ),
          ),
          child: Text(
            '${evaluation.totalScore.toStringAsFixed(1)}/20 · ${evaluation.totalLabel}',
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

/// Safety warning banner shown in results when safety flag is set.
class _SafetyWarningBanner extends StatelessWidget {
  final SafetyResult safetyResult;

  const _SafetyWarningBanner({required this.safetyResult});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(UiTokens.s16),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withOpacity(0.06),
        borderRadius: BorderRadius.circular(UiTokens.r12),
        border: Border.all(
          color: theme.colorScheme.error.withOpacity(0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Safety Warning',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  safetyResult.summary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.65),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// BREATHING RECORD BUTTON (idle state)
// ────────────────────────────────────────────────────────────────────────────

/// Record button with a subtle, continuous breathing glow animation.
class _BreathingRecordButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _BreathingRecordButton({required this.onPressed});

  @override
  State<_BreathingRecordButton> createState() =>
      _BreathingRecordButtonState();
}

class _BreathingRecordButtonState extends State<_BreathingRecordButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _glowAnim = Tween<double>(begin: 0.15, end: 0.40).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: widget.onPressed,
      child: AnimatedBuilder(
        animation: _glowAnim,
        builder: (context, child) {
          return Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary,
              boxShadow: [
                BoxShadow(
                  color: primary.withOpacity(_glowAnim.value),
                  blurRadius: 28 + _glowAnim.value * 16,
                  spreadRadius: 2 + _glowAnim.value * 6,
                ),
              ],
            ),
            child: child,
          );
        },
        child: const Icon(
          Icons.mic_rounded,
          size: 42,
          color: Colors.white,
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// PULSING RECORD INDICATOR (recording state)
// ────────────────────────────────────────────────────────────────────────────

/// Pulsing concentric circles indicating active recording.
class _PulsingRecordIndicator extends StatefulWidget {
  /// Overall size of the pulsing area. Defaults to 130.
  final double size;
  const _PulsingRecordIndicator({this.size = 130});

  @override
  State<_PulsingRecordIndicator> createState() =>
      _PulsingRecordIndicatorState();
}

class _PulsingRecordIndicatorState extends State<_PulsingRecordIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;

    final s = widget.size;
    final innerSize = s * 0.4; // proportional inner circle
    final iconSize = s * 0.215;

    return SizedBox(
      width: s,
      height: s,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _PulsePainter(
              progress: _controller.value,
              color: color,
            ),
            child: child,
          );
        },
        child: Center(
          child: Container(
            width: innerSize,
            height: innerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.25),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              Icons.mic_rounded,
              color: Colors.white,
              size: iconSize,
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  final double progress;
  final Color color;

  _PulsePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    for (int i = 0; i < 3; i++) {
      final phase = (progress + i * 0.33) % 1.0;
      final radius = 26.0 + phase * 38.0;
      final opacity = (1.0 - phase).clamp(0.0, 0.32);

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withOpacity(opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      old.progress != progress || old.color != color;
}

// ────────────────────────────────────────────────────────────────────────────
// BLINKING "LISTENING" LABEL (recording state)
// ────────────────────────────────────────────────────────────────────────────

/// "Listening..." label with a blinking red dot.
class _BlinkingListeningLabel extends StatefulWidget {
  const _BlinkingListeningLabel();

  @override
  State<_BlinkingListeningLabel> createState() =>
      _BlinkingListeningLabelState();
}

class _BlinkingListeningLabelState extends State<_BlinkingListeningLabel>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: _controller,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: errorColor,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Listening…',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: errorColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// GRADIENT SPINNER (processing state)
// ────────────────────────────────────────────────────────────────────────────

/// A continuously rotating gradient arc spinner.
class _GradientSpinner extends StatefulWidget {
  const _GradientSpinner();

  @override
  State<_GradientSpinner> createState() => _GradientSpinnerState();
}

class _GradientSpinnerState extends State<_GradientSpinner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return SizedBox(
      width: 56,
      height: 56,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _GradientArcPainter(
              progress: _controller.value,
              color: primary,
            ),
          );
        },
      ),
    );
  }
}

class _GradientArcPainter extends CustomPainter {
  final double progress;
  final Color color;

  _GradientArcPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final startAngle = progress * 2 * math.pi;
    const sweepAngle = 1.2 * math.pi;

    final paint = Paint()
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: [color.withOpacity(0.0), color],
        tileMode: TileMode.clamp,
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect.deflate(2),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_GradientArcPainter old) =>
      old.progress != progress || old.color != color;
}

// ════════════════════════════════════════════════════════════════════════════
// RESULT WIDGETS
// ════════════════════════════════════════════════════════════════════════════

/// Overall quality badge.
class _OverallBadge extends StatelessWidget {
  final String label;

  const _OverallBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final color = switch (label) {
      'Good' => Colors.green,
      'Fair' => Colors.orange,
      _ => Colors.red,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

/// Metrics summary row (word count, compression, etc.).
class _MetricsRow extends StatelessWidget {
  final BenchmarkResult result;

  const _MetricsRow({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withOpacity(0.55);

    return Row(
      children: [
        _MetricChip(
            label: 'Words',
            value: '${result.transcriptWordCount}',
            color: muted),
        const SizedBox(width: 8),
        _MetricChip(
            label: 'Summary',
            value: '${result.summaryWordCount} words',
            color: muted),
        const SizedBox(width: 8),
        _MetricChip(
            label: 'Ratio',
            value: '${(result.compressionRatio * 100).toStringAsFixed(0)}%',
            color: muted),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(UiTokens.r12),
          border: Border.all(
            color: theme.colorScheme.onSurface.withOpacity(0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: theme.textTheme.labelMedium?.copyWith(color: color)),
            const SizedBox(height: 2),
            Text(value, style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

/// A titled section showing text content.
class _ResultSection extends StatelessWidget {
  final String title;
  final String content;

  const _ResultSection({
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(UiTokens.s16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(UiTokens.r16),
        border: Border.all(
          color: theme.colorScheme.onSurface.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: UiTokens.s8),
          Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// A single benchmark dimension score card.
class _DimensionCard extends StatelessWidget {
  final BenchmarkDimension dimension;

  const _DimensionCard({required this.dimension});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scoreColor = switch (dimension.score) {
      BenchmarkScore.good => Colors.green,
      BenchmarkScore.fair => Colors.orange,
      BenchmarkScore.poor => Colors.red,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(UiTokens.r12),
          border: Border.all(
            color: theme.colorScheme.onSurface.withOpacity(0.08),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: scoreColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                dimension.score.label,
                style: TextStyle(
                  color: scoreColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dimension.name,
                    style: theme.textTheme.titleMedium?.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dimension.explanation,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Collapsible section for long content (e.g. transcript).
class _CollapsibleSection extends StatefulWidget {
  final String title;
  final String content;

  const _CollapsibleSection({
    required this.title,
    required this.content,
  });

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(UiTokens.r16),
        border: Border.all(
          color: theme.colorScheme.onSurface.withOpacity(0.08),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(UiTokens.r16),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(UiTokens.s16),
              child: Row(
                children: [
                  Expanded(
                    child:
                        Text(widget.title, style: theme.textTheme.titleMedium),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: UiTokens.durMed,
                    child: const Icon(Icons.expand_more, size: 22),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                  UiTokens.s16, 0, UiTokens.s16, UiTokens.s16),
              child: Text(
                widget.content,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: UiTokens.durMed,
          ),
        ],
      ),
    );
  }
}
