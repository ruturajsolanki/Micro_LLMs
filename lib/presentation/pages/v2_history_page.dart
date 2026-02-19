import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/di/injection.dart';
import '../../data/datasources/v2_session_storage.dart';
import '../../domain/entities/v2_session_record.dart';
import '../theme/ui_tokens.dart';

/// Page showing history of all V2 evaluation sessions.
class V2HistoryPage extends StatefulWidget {
  const V2HistoryPage({super.key});

  @override
  State<V2HistoryPage> createState() => _V2HistoryPageState();
}

class _V2HistoryPageState extends State<V2HistoryPage> {
  late V2SessionStorage _storage;
  late List<V2SessionRecord> _records;

  @override
  void initState() {
    super.initState();
    _storage = sl<V2SessionStorage>();
    _records = _storage.getAll();
  }

  void _refresh() {
    setState(() {
      _records = _storage.getAll();
    });
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text(
          'Delete all session records? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storage.clearAll();
      _refresh();
    }
  }

  Future<void> _deleteRecord(String id) async {
    await _storage.delete(id);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session History'),
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'Clear all history',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _records.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_rounded,
                      size: 64, color: cs.onSurface.withOpacity(0.25)),
                  const SizedBox(height: UiTokens.s16),
                  Text(
                    'No sessions yet',
                    style: tt.titleMedium?.copyWith(
                      color: cs.onSurface.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(height: UiTokens.s8),
                  Text(
                    'Complete a voice evaluation to see it here.',
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.35),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Summary bar
                _SummaryBar(records: _records),

                // Sessions list
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(UiTokens.s12),
                    itemCount: _records.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: UiTokens.s8),
                    itemBuilder: (context, index) {
                      final record = _records[index];
                      return _SessionCard(
                        record: record,
                        onTap: () => _openDetail(record),
                        onDelete: () => _deleteRecord(record.id),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  void _openDetail(V2SessionRecord record) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SessionDetailPage(record: record),
      ),
    );
  }
}

// ── Summary Bar ────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final List<V2SessionRecord> records;
  const _SummaryBar({required this.records});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final avgClarity = records.isEmpty
        ? 0.0
        : records.fold<double>(0, (a, r) => a + r.clarityScore) /
            records.length;
    final avgLanguage = records.isEmpty
        ? 0.0
        : records.fold<double>(0, (a, r) => a + r.languageScore) /
            records.length;
    final avgTotal = avgClarity + avgLanguage;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: UiTokens.s16,
        vertical: UiTokens.s12,
      ),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(color: cs.outline.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          _StatChip(
            label: 'Sessions',
            value: '${records.length}',
            icon: Icons.history,
          ),
          _StatChip(
            label: 'Avg Score',
            value: '${avgTotal.toStringAsFixed(1)}/20',
            icon: Icons.trending_up,
          ),
          _StatChip(
            label: 'Clarity',
            value: avgClarity.toStringAsFixed(1),
            icon: Icons.lightbulb_outline,
          ),
          _StatChip(
            label: 'Language',
            value: avgLanguage.toStringAsFixed(1),
            icon: Icons.abc_rounded,
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: cs.primary),
          const SizedBox(height: 2),
          Text(
            value,
            style: tt.labelLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: cs.onSurface.withOpacity(0.5),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Session Card ───────────────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  final V2SessionRecord record;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SessionCard({
    required this.record,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final dateStr = _formatDate(record.completedAt);
    final timeStr = _formatTime(record.completedAt);

    Color scoreColor;
    final frac = record.totalScore / 20;
    if (frac >= 0.75) {
      scoreColor = Colors.green;
    } else if (frac >= 0.5) {
      scoreColor = Colors.orange;
    } else {
      scoreColor = Colors.red;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(UiTokens.s12),
          child: Row(
            children: [
              // Score circle
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scoreColor.withOpacity(0.12),
                  border: Border.all(color: scoreColor, width: 2),
                ),
                child: Center(
                  child: Text(
                    record.totalScore.toStringAsFixed(0),
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scoreColor,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: UiTokens.s12),

              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          dateStr,
                          style: tt.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          timeStr,
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.5),
                          ),
                        ),
                        const Spacer(),
                        if (record.audioSource == 'upload')
                          Icon(Icons.upload_file,
                              size: 14,
                              color: cs.onSurface.withOpacity(0.4))
                        else
                          Icon(Icons.mic,
                              size: 14,
                              color: cs.onSurface.withOpacity(0.4)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Metadata row
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        _MetaTag(
                          icon: Icons.timer_outlined,
                          text: record.durationFormatted,
                        ),
                        _MetaTag(
                          icon: Icons.speed_outlined,
                          text: record.processingTimeFormatted,
                        ),
                        _MetaTag(
                          icon: Icons.notes_rounded,
                          text: '${record.wordCount} words',
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Score breakdown
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'C ${record.clarityScore.toStringAsFixed(1)}',
                            overflow: TextOverflow.ellipsis,
                            style: tt.labelSmall?.copyWith(
                              color: cs.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'L ${record.languageScore.toStringAsFixed(1)}',
                            overflow: TextOverflow.ellipsis,
                            style: tt.labelSmall?.copyWith(
                              color: Colors.teal,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          record.totalLabel,
                          style: tt.labelSmall?.copyWith(
                            color: scoreColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Delete
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 18, color: cs.onSurface.withOpacity(0.3)),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : dt.hour;
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:${dt.minute.toString().padLeft(2, '0')} $amPm';
  }
}

class _MetaTag extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaTag({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: cs.onSurface.withOpacity(0.4)),
        const SizedBox(width: 3),
        Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: cs.onSurface.withOpacity(0.55),
              ),
        ),
      ],
    );
  }
}

// ── Session Detail Page ────────────────────────────────────────────

class _SessionDetailPage extends StatefulWidget {
  final V2SessionRecord record;
  const _SessionDetailPage({required this.record});

  @override
  State<_SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<_SessionDetailPage> {
  AudioPlayer? _player;
  bool _audioAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkAudio();
  }

  void _checkAudio() {
    final path = widget.record.audioFilePath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      _audioAvailable = true;
      _player = AudioPlayer();
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final record = widget.record;

    return Scaffold(
      appBar: AppBar(
        title: Text('Session — ${_formatDate(record.completedAt)}'),
      ),
      body: SingleChildScrollView(
        padding: UiTokens.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Audio Player ──────────────────────────────────
            if (_audioAvailable) ...[
              _AudioPlayerCard(
                player: _player!,
                audioPath: record.audioFilePath!,
                duration: record.recordingDurationSeconds,
              ),
              const SizedBox(height: UiTokens.s12),
            ],

            // ── Meta row ────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(UiTokens.s16),
                child: Column(
                  children: [
                    _DetailRow(
                      label: 'Date',
                      value: _formatFullDate(record.completedAt),
                    ),
                    _DetailRow(
                      label: 'Recording',
                      value: record.durationFormatted,
                    ),
                    _DetailRow(
                      label: 'Processing',
                      value: record.processingTimeFormatted,
                    ),
                    _DetailRow(
                      label: 'Words',
                      value: '${record.wordCount}',
                    ),
                    _DetailRow(
                      label: 'Source',
                      value: record.audioSource == 'upload'
                          ? 'Uploaded (${record.uploadedFileName ?? 'file'})'
                          : 'Microphone',
                    ),
                    _DetailRow(
                      label: 'LLM',
                      value: record.llmProvider,
                    ),
                    _DetailRow(
                      label: 'STT',
                      value: record.sttProvider,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: UiTokens.s16),

            // ── Scores ──────────────────────────────────────
            if (!record.safetyFlag) ...[
              _ScoreBlock(
                title: 'Clarity of Thought',
                score: record.clarityScore,
                reasoning: record.clarityReasoning,
                color: cs.primary,
              ),
              const SizedBox(height: UiTokens.s8),
              _ScoreBlock(
                title: 'Language Proficiency',
                score: record.languageScore,
                reasoning: record.languageReasoning,
                color: Colors.teal,
              ),

              const SizedBox(height: UiTokens.s12),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(UiTokens.s16),
                  child: Row(
                    children: [
                      Text(
                        '${record.totalScore.toStringAsFixed(1)}',
                        style: tt.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(' / 20', style: tt.titleMedium),
                      const SizedBox(width: UiTokens.s12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _labelColor(record.totalScore).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          record.totalLabel,
                          style: tt.labelMedium?.copyWith(
                            color: _labelColor(record.totalScore),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: UiTokens.s12),

              // ── Feedback ────────────────────────────────────
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
                      Text(record.overallFeedback, style: tt.bodyMedium),
                    ],
                  ),
                ),
              ),
            ] else ...[
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
                          'Content flagged: ${record.safetyNotes}',
                          style: tt.bodyMedium
                              ?.copyWith(color: cs.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: UiTokens.s16),

            // ── Transcript ──────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(UiTokens.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Transcript',
                            style: tt.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Text(
                          '${record.wordCount} words',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: UiTokens.s12),
                    SelectableText(
                      record.transcript,
                      style: tt.bodyMedium?.copyWith(height: 1.6),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Color _labelColor(double score) {
    if (score >= 15) return Colors.green;
    if (score >= 10) return Colors.orange;
    return Colors.red;
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  String _formatFullDate(DateTime dt) {
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} '
        'at $h:${dt.minute.toString().padLeft(2, '0')} $amPm';
  }
}

// ── Audio Player Card ──────────────────────────────────────────────

class _AudioPlayerCard extends StatefulWidget {
  final AudioPlayer player;
  final String audioPath;
  final int duration;

  const _AudioPlayerCard({
    required this.player,
    required this.audioPath,
    required this.duration,
  });

  @override
  State<_AudioPlayerCard> createState() => _AudioPlayerCardState();
}

class _AudioPlayerCardState extends State<_AudioPlayerCard> {
  bool _loaded = false;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final dur = await widget.player.setFilePath(widget.audioPath);
      if (dur != null && mounted) {
        setState(() {
          _totalDuration = dur;
          _loaded = true;
        });
      }
    } catch (e) {
      // File might be corrupt or unsupported.
      if (mounted) setState(() => _loaded = false);
    }

    widget.player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    widget.player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state.playing);
      if (state.processingState == ProcessingState.completed) {
        widget.player.seek(Duration.zero);
        widget.player.pause();
      }
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    if (!_loaded) {
      return const SizedBox.shrink();
    }

    final maxMs = _totalDuration.inMilliseconds.toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: UiTokens.s16,
          vertical: UiTokens.s12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.headphones_rounded,
                    size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Playback',
                  style: tt.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // Play / pause button
                IconButton(
                  onPressed: () {
                    if (_playing) {
                      widget.player.pause();
                    } else {
                      widget.player.play();
                    }
                  },
                  icon: Icon(
                    _playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    size: 40,
                    color: cs.primary,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
                const SizedBox(width: 8),
                // Seek bar
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                      activeTrackColor: cs.primary,
                      inactiveTrackColor: cs.primary.withOpacity(0.15),
                      thumbColor: cs.primary,
                    ),
                    child: Slider(
                      value: _position.inMilliseconds
                          .toDouble()
                          .clamp(0, maxMs),
                      max: maxMs > 0 ? maxMs : 1,
                      onChanged: (v) {
                        widget.player
                            .seek(Duration(milliseconds: v.toInt()));
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Time label
                Text(
                  '${_fmt(_position)} / ${_fmt(_totalDuration)}',
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.5),
                    fontFeatures: [const FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.5),
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: tt.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _ScoreBlock extends StatelessWidget {
  final String title;
  final double score;
  final String reasoning;
  final Color color;

  const _ScoreBlock({
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
        padding: const EdgeInsets.all(UiTokens.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: tt.labelMedium?.copyWith(
                    color: color, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              '${score.toStringAsFixed(1)}/10',
              style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              reasoning,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.6),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
