import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injection.dart';
import '../../data/datasources/audio_recorder_service.dart';
import '../blocs/v2_session/v2_session_bloc.dart';
import '../theme/ui_tokens.dart';

/// V2 cloud-first home page.
///
/// Single-screen flow: cloud check → mic → record → transcribe → evaluate → results.
class V2HomePage extends StatelessWidget {
  const V2HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          sl<V2SessionBloc>()..add(const V2CloudCheckRequested()),
      child: const _V2HomeView(),
    );
  }
}

class _V2HomeView extends StatelessWidget {
  const _V2HomeView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MicroLLM V2'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Session History',
            onPressed: () => Navigator.pushNamed(context, '/v2-history'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
          IconButton(
            icon: const Icon(Icons.lock_open_rounded, size: 20),
            tooltip: 'Unlock V1',
            onPressed: () => _showPinDialog(context),
          ),
        ],
      ),
      body: BlocBuilder<V2SessionBloc, V2SessionState>(
        builder: (context, state) {
          return AnimatedSwitcher(
            duration: UiTokens.durMed,
            child: _buildBody(context, state),
          );
        },
      ),
    );
  }

  void _showPinDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlock V1 Interface'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter PIN',
            counterText: '',
          ),
          onSubmitted: (_) {
            if (controller.text == '7890') {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, '/v1-home');
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text == '7890') {
                Navigator.pop(ctx);
                Navigator.pushNamed(context, '/v1-home');
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Incorrect PIN')),
                );
                Navigator.pop(ctx);
              }
            },
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, V2SessionState state) {
    switch (state.status) {
      case V2SessionStatus.checking:
        return const _CheckingView();
      case V2SessionStatus.needsSetup:
        return const _NeedsSetupView();
      case V2SessionStatus.ready:
        return _ReadyView(cloudReady: state.cloudReady);
      case V2SessionStatus.recording:
        return _RecordingView(
          seconds: state.recordingSeconds,
          liveTranscript: state.liveTranscript,
        );
      case V2SessionStatus.transcribing:
        return _ProcessingView(step: state.processingStep ?? 'Transcribing...');
      case V2SessionStatus.evaluating:
        return _ProcessingView(step: state.processingStep ?? 'Evaluating...');
      case V2SessionStatus.completed:
        return _ResultsView(state: state);
      case V2SessionStatus.error:
        return _ErrorView(message: state.errorMessage ?? 'Unknown error');
    }
  }
}

// ── Checking View ──────────────────────────────────────────────────

class _CheckingView extends StatelessWidget {
  const _CheckingView();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_sync_rounded, size: 48, color: cs.primary),
          const SizedBox(height: 20),
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 16),
          Text(
            'Connecting to cloud...',
            style: tt.titleMedium?.copyWith(
              color: cs.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Verifying API key and services',
            style: tt.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Needs Setup ────────────────────────────────────────────────────

class _NeedsSetupView extends StatelessWidget {
  const _NeedsSetupView();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = context.read<V2SessionBloc>().state;
    final hasError = state.errorMessage != null && state.errorMessage!.isNotEmpty;

    return Center(
      child: Padding(
        padding: UiTokens.pagePadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasError ? Icons.cloud_off_rounded : Icons.vpn_key_rounded,
              size: 64,
              color: hasError ? cs.error : cs.primary,
            ),
            const SizedBox(height: UiTokens.s16),
            Text(
              hasError ? 'Cloud Unavailable' : 'API Key Required',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: UiTokens.s8),
            Text(
              hasError
                  ? 'The built-in API key may have hit its limit.\nPlease enter your own free Groq key to continue.'
                  : 'Set up your Groq or Gemini API key to use cloud-powered voice evaluation.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withOpacity(0.7),
                  ),
            ),
            if (hasError) ...[
              const SizedBox(height: UiTokens.s8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  state.errorMessage!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.error,
                      ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () async {
                await Navigator.pushNamed(context, '/api-setup');
                if (!context.mounted) return;
                context
                    .read<V2SessionBloc>()
                    .add(const V2CloudCheckRequested());
              },
              icon: const Icon(Icons.key_rounded),
              label: const Text('Enter Your API Key'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                context
                    .read<V2SessionBloc>()
                    .add(const V2CloudCheckRequested());
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Ready View ─────────────────────────────────────────────────────

class _ReadyView extends StatelessWidget {
  final bool cloudReady;
  const _ReadyView({required this.cloudReady});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: UiTokens.pagePadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cloud status chip
            Chip(
              avatar: Icon(
                cloudReady ? Icons.cloud_done : Icons.cloud_off,
                size: 18,
                color: cloudReady ? Colors.green : Colors.orange,
              ),
              label: Text(
                cloudReady ? 'Cloud Ready' : 'Offline Mode',
                style: tt.labelMedium,
              ),
            ),

            const SizedBox(height: 48),

            // Big mic button
            GestureDetector(
              onTap: () {
                context.read<V2SessionBloc>().add(const V2RecordingStarted());
              },
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary,
                  boxShadow: [
                    BoxShadow(
                      color: cs.primary.withOpacity(0.3),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.mic_rounded,
                  size: 48,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 24),

            Text(
              'Tap to start speaking',
              style: tt.titleMedium?.copyWith(
                color: cs.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Speak for 1-3 minutes. Your speech will be\ntranscribed and evaluated.',
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.45),
              ),
            ),

            const SizedBox(height: 32),

            // Upload option
            OutlinedButton.icon(
              onPressed: () => _pickAudioFile(context),
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: const Text('Upload Audio File'),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.onSurface.withOpacity(0.6),
                side: BorderSide(color: cs.outline.withOpacity(0.3)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'WAV, MP3, FLAC, M4A, WebM',
              style: tt.labelSmall?.copyWith(
                color: cs.onSurface.withOpacity(0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAudioFile(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'mp3', 'flac', 'm4a', 'webm', 'ogg', 'mp4'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) return;

      if (!context.mounted) return;

      context.read<V2SessionBloc>().add(V2AudioFileSelected(
            filePath: file.path!,
            fileName: file.name,
          ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick file: $e')),
      );
    }
  }
}

// ── Recording View with Waveform + Live Transcript ─────────────────

class _RecordingView extends StatefulWidget {
  final int seconds;
  final String? liveTranscript;
  const _RecordingView({required this.seconds, this.liveTranscript});

  @override
  State<_RecordingView> createState() => _RecordingViewState();
}

class _RecordingViewState extends State<_RecordingView>
    with SingleTickerProviderStateMixin {
  late final AudioRecorderService _recorder;
  late final AnimationController _animController;
  final ScrollController _scrollController = ScrollController();

  /// Rolling buffer of normalised amplitudes (0.0 – 1.0).
  final List<double> _bars = List.filled(48, 0.0);
  int _barIndex = 0;

  @override
  void initState() {
    super.initState();
    _recorder = sl<AudioRecorderService>();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );

    _recorder.rmsStream.listen((rmsDb) {
      if (!mounted) return;
      final clamped = (rmsDb + 60).clamp(0.0, 60.0) / 60.0;
      setState(() {
        _bars[_barIndex % _bars.length] = clamped;
        _barIndex++;
      });
    });
  }

  @override
  void didUpdateWidget(covariant _RecordingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-scroll to bottom when live transcript updates.
    if (widget.liveTranscript != oldWidget.liveTranscript) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _formatTime(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final hasTranscript =
        widget.liveTranscript != null && widget.liveTranscript!.isNotEmpty;

    return Padding(
      padding: UiTokens.pagePadding,
      child: Column(
        children: [
          // ── Top: pulsing dot, timer, waveform ──────────
          _PulsingDot(color: Colors.red.shade400),
          const SizedBox(height: 8),
          Text(
            'Recording',
            style: tt.titleMedium?.copyWith(color: Colors.red.shade400),
          ),
          const SizedBox(height: 4),
          Text(
            _formatTime(widget.seconds),
            style: tt.headlineMedium?.copyWith(
              fontWeight: FontWeight.w300,
              fontFeatures: [const FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 16),

          // Waveform
          SizedBox(
            height: 64,
            child: CustomPaint(
              size: const Size(double.infinity, 64),
              painter: _WaveformPainter(
                bars: _bars,
                headIndex: _barIndex,
                color: cs.primary,
                inactiveColor: cs.primary.withOpacity(0.15),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Live transcript area ───────────────────────
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: cs.outline.withOpacity(0.12),
                ),
              ),
              child: ShaderMask(
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black,
                      Colors.black,
                    ],
                    stops: const [0.0, 0.06, 1.0],
                  ).createShader(bounds);
                },
                blendMode: BlendMode.dstIn,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: hasTranscript
                      ? Text(
                          widget.liveTranscript!,
                          style: tt.bodyMedium?.copyWith(
                            height: 1.6,
                            color: cs.onSurface.withOpacity(0.85),
                          ),
                        )
                      : Text(
                          'Listening...',
                          style: tt.bodyMedium?.copyWith(
                            height: 1.6,
                            color: cs.onSurface.withOpacity(0.3),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Stop button ────────────────────────────────
          GestureDetector(
            onTap: () {
              context.read<V2SessionBloc>().add(const V2RecordingStopped());
            },
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.error,
                boxShadow: [
                  BoxShadow(
                    color: cs.error.withOpacity(0.3),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.stop_rounded,
                size: 36,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap to stop',
            style: tt.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Draws a rolling-bar waveform visualisation.
class _WaveformPainter extends CustomPainter {
  final List<double> bars;
  final int headIndex;
  final Color color;
  final Color inactiveColor;

  _WaveformPainter({
    required this.bars,
    required this.headIndex,
    required this.color,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = bars.length;
    final barWidth = size.width / barCount;
    final gap = 2.0;
    final usableBarWidth = barWidth - gap;
    if (usableBarWidth <= 0) return;

    final midY = size.height / 2;
    final maxHalf = size.height / 2 - 2;

    for (var i = 0; i < barCount; i++) {
      // Draw oldest → newest left to right
      final dataIndex = (headIndex - barCount + i) % barCount;
      final amplitude = bars[dataIndex < 0 ? dataIndex + barCount : dataIndex];

      // Minimum visible bar height
      final barHalf = math.max(amplitude * maxHalf, 1.5);

      final x = i * barWidth + gap / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(x, midY - barHalf, x + usableBarWidth, midY + barHalf),
        const Radius.circular(2),
      );

      // Fade out older bars
      final age = (barCount - i) / barCount; // 1.0 = oldest, 0.0 = newest
      final opacity = (1.0 - age * 0.6).clamp(0.4, 1.0);

      final paint = Paint()
        ..color = amplitude > 0.02
            ? color.withOpacity(opacity)
            : inactiveColor;

      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) => true;
}

// ── Processing View ────────────────────────────────────────────────

class _ProcessingView extends StatelessWidget {
  final String step;
  const _ProcessingView({required this.step});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: UiTokens.pagePadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              step,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'This may take a few seconds...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.5),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Results View ───────────────────────────────────────────────────

class _ResultsView extends StatelessWidget {
  final V2SessionState state;
  const _ResultsView({required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final eval = state.evaluationResult;
    final benchmark = state.benchmarkResult;

    return SingleChildScrollView(
      padding: UiTokens.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              const SizedBox(width: UiTokens.s8),
              Text('Evaluation Complete',
                  style: tt.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),

          if (benchmark != null) ...[
            const SizedBox(height: 4),
            Text(
              'Processed in ${(benchmark.processingTimeMs / 1000).toStringAsFixed(1)}s '
              '| ${benchmark.recordingDurationSeconds}s recording',
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.5),
              ),
            ),
          ],

          const SizedBox(height: 24),

          if (eval != null && !eval.safetyFlag) ...[
            // Score cards
            Row(
              children: [
                Expanded(
                  child: _ScoreCard(
                    title: 'Clarity',
                    score: eval.clarityScore,
                    reasoning: eval.clarityReasoning,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: UiTokens.s12),
                Expanded(
                  child: _ScoreCard(
                    title: 'Language',
                    score: eval.languageScore,
                    reasoning: eval.languageReasoning,
                    color: Colors.teal,
                  ),
                ),
              ],
            ),

            const SizedBox(height: UiTokens.s16),

            // Total score
            Card(
              child: Padding(
                padding: const EdgeInsets.all(UiTokens.s16),
                child: Row(
                  children: [
                    _CircularScore(
                      score: eval.totalScore,
                      maxScore: 20,
                      label: eval.totalLabel,
                      size: 72,
                    ),
                    const SizedBox(width: UiTokens.s16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total Score',
                              style: tt.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            '${eval.totalScore.toStringAsFixed(1)} / 20',
                            style: tt.headlineSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: UiTokens.s16),

            // Feedback
            Card(
              child: Padding(
                padding: const EdgeInsets.all(UiTokens.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Feedback',
                        style: tt.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: UiTokens.s8),
                    Text(eval.overallFeedback, style: tt.bodyMedium),
                  ],
                ),
              ),
            ),
          ] else if (eval != null && eval.safetyFlag) ...[
            Card(
              color: cs.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(UiTokens.s16),
                child: Row(
                  children: [
                    Icon(Icons.warning_rounded, color: cs.error),
                    const SizedBox(width: UiTokens.s12),
                    Expanded(
                      child: Text(
                        'Content flagged: ${eval.safetyNotes}',
                        style: tt.bodyMedium?.copyWith(color: cs.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Transcript expandable
          if (state.transcript != null) ...[
            const SizedBox(height: UiTokens.s16),
            ExpansionTile(
              title: Text('Transcript',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              subtitle: Text(
                '${state.transcript!.split(' ').length} words',
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(0.5),
                ),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(UiTokens.s16),
                  child: SelectableText(
                    state.transcript!,
                    style: tt.bodyMedium?.copyWith(height: 1.6),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 32),

          // New session button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: () {
                context.read<V2SessionBloc>().add(const V2SessionReset());
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('New Session'),
            ),
          ),

          const SizedBox(height: UiTokens.s16),
        ],
      ),
    );
  }
}

// ── Error View ─────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: UiTokens.pagePadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: cs.error),
            const SizedBox(height: UiTokens.s16),
            Text(
              'Something went wrong',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: UiTokens.s8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withOpacity(0.7),
                  ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                context.read<V2SessionBloc>().add(const V2SessionReset());
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable widgets ───────────────────────────────────────────────

class _ScoreCard extends StatelessWidget {
  final String title;
  final double score;
  final String reasoning;
  final Color color;

  const _ScoreCard({
    required this.title,
    required this.score,
    required this.reasoning,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(UiTokens.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    tt.labelLarge?.copyWith(color: color, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '${score.toStringAsFixed(1)}/10',
              style: tt.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              reasoning,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.65),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircularScore extends StatelessWidget {
  final double score;
  final double maxScore;
  final String label;
  final double size;

  const _CircularScore({
    required this.score,
    required this.maxScore,
    required this.label,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fraction = (score / maxScore).clamp(0.0, 1.0);

    Color scoreColor;
    if (fraction >= 0.75) {
      scoreColor = Colors.green;
    } else if (fraction >= 0.5) {
      scoreColor = Colors.orange;
    } else {
      scoreColor = Colors.red;
    }

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CircularScorePainter(
          fraction: fraction,
          color: scoreColor,
          backgroundColor: cs.surfaceContainerHighest,
        ),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scoreColor,
                ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _CircularScorePainter extends CustomPainter {
  final double fraction;
  final Color color;
  final Color backgroundColor;

  _CircularScorePainter({
    required this.fraction,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Background arc
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = backgroundColor,
    );

    // Score arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularScorePainter oldDelegate) =>
      fraction != oldDelegate.fraction || color != oldDelegate.color;
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
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
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_controller),
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 1.3).animate(_controller),
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}
