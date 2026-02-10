import 'package:flutter/material.dart';

import '../../domain/services/device_benchmark.dart';
import '../theme/ui_tokens.dart';

/// Dialog for running device benchmarks.
class BenchmarkDialog extends StatefulWidget {
  const BenchmarkDialog({super.key});
  
  @override
  State<BenchmarkDialog> createState() => _BenchmarkDialogState();
}

class _BenchmarkDialogState extends State<BenchmarkDialog> {
  bool _isRunning = false;
  String _status = 'Ready to run benchmark';
  double _progress = 0.0;
  BenchmarkResults? _results;
  
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 400 ? screenWidth * 0.9 : 320.0;
    final cs = Theme.of(context).colorScheme;
    
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.speed, size: 22, color: cs.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Benchmark',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.65,
          ),
          child: _results != null
              ? _buildResults()
              : _buildRunning(),
        ),
      ),
      actions: [
        if (_results != null)
          TextButton(
            onPressed: () {
              setState(() {
                _results = null;
                _progress = 0.0;
                _status = 'Ready to run benchmark';
              });
            },
            child: const Text('Run Again'),
          ),
        TextButton(
          onPressed: _isRunning ? null : () => Navigator.pop(context),
          child: Text(_results != null ? 'Close' : 'Cancel'),
        ),
        if (_results == null && !_isRunning)
          ElevatedButton(
            onPressed: _runBenchmark,
            child: const Text('Start'),
          ),
      ],
    );
  }
  
  Widget _buildRunning() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Center(
          child: _isRunning
              ? CircularProgressIndicator(color: cs.primary)
              : Icon(
                  Icons.play_circle_outline,
                  size: 56,
                  color: cs.onSurface.withOpacity(0.35),
                ),
        ),
        const SizedBox(height: 16),
        Text(
          _status,
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
        if (_isRunning) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(UiTokens.r12),
            child: LinearProgressIndicator(value: _progress),
          ),
          const SizedBox(height: 6),
          Text(
            '${(_progress * 100).round()}%',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ] else ...[
          const SizedBox(height: 12),
          Text(
            'Measures CPU, memory & SIMD to estimate LLM performance.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.60),
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
  
  Widget _buildResults() {
    final results = _results!;
    final tierColor = _getTierColor(results.performanceTier);
    final cs = Theme.of(context).colorScheme;
    
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Overall score - compact design
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  tierColor.withOpacity(0.1),
                  tierColor.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  '${results.overallScore}',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: tierColor,
                  ),
                ),
                Text(
                  results.performanceTier.displayName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: tierColor,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Score breakdown - compact
          _buildScoreBar('CPU', results.cpuScore, Colors.blue),
          const SizedBox(height: 6),
          _buildScoreBar('Memory', results.memoryScore, Colors.green),
          const SizedBox(height: 6),
          _buildScoreBar('SIMD', results.simdScore, Colors.purple),
          
          const SizedBox(height: 16),
          
          // Estimated performance - compact
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(UiTokens.r16),
              border: Border.all(color: cs.primary.withOpacity(0.14)),
            ),
            child: Row(
              children: [
                Icon(Icons.speed, color: cs.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '~${results.estimatedTokensPerSecond.toStringAsFixed(1)} tok/s',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Estimated (Phi-2 Q4)',
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurface.withOpacity(0.55),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Recommended models - compact
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.onSurface.withOpacity(0.05),
              borderRadius: BorderRadius.circular(UiTokens.r16),
              border: Border.all(color: cs.onSurface.withOpacity(0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Recommended',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: results.performanceTier.recommendedModels
                      .map((model) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: cs.surface,
                              borderRadius: BorderRadius.circular(UiTokens.r12),
                              border: Border.all(color: cs.onSurface.withOpacity(0.10)),
                            ),
                            child: Text(
                              model,
                              style: const TextStyle(fontSize: 10),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
  
  Widget _buildScoreBar(String label, int score, Color color) {
    final percentage = (score / 1000 * 100).clamp(0, 100);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(
              '$score',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage / 100,
            minHeight: 8,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
  
  Color _getTierColor(PerformanceTier tier) {
    switch (tier) {
      case PerformanceTier.flagship: return Colors.purple;
      case PerformanceTier.highEnd: return Colors.blue;
      case PerformanceTier.midRange: return Colors.green;
      case PerformanceTier.entryLevel: return Colors.orange;
      case PerformanceTier.basic: return Colors.grey;
    }
  }
  
  Future<void> _runBenchmark() async {
    setState(() {
      _isRunning = true;
      _progress = 0.0;
    });
    
    try {
      final results = await DeviceBenchmark.runAll(
        onProgress: (status, progress) {
          if (mounted) {
            setState(() {
              _status = status;
              _progress = progress;
            });
          }
        },
      );
      
      if (mounted) {
        setState(() {
          _results = results;
          _isRunning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'Benchmark failed: $e';
          _isRunning = false;
        });
      }
    }
  }
}
