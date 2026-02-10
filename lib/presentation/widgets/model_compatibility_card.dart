import 'package:flutter/material.dart';

import '../../domain/entities/device_specs.dart';
import '../theme/ui_tokens.dart';

/// Card displaying model compatibility information.
class ModelCompatibilityCard extends StatelessWidget {
  final ModelCompatibility compatibility;
  final bool isRecommended;
  final bool isSelected;
  final bool isDownloaded;
  final bool isDownloading;
  final double downloadProgress;
  final VoidCallback? onSelect;
  final VoidCallback? onDownload;
  
  const ModelCompatibilityCard({
    super.key,
    required this.compatibility,
    this.isRecommended = false,
    this.isSelected = false,
    this.isDownloaded = false,
    this.isDownloading = false,
    this.downloadProgress = 0.0,
    this.onSelect,
    this.onDownload,
  });
  
  @override
  Widget build(BuildContext context) {
    final model = compatibility.model;
    final level = compatibility.level;
    final isIncompatible = level == CompatibilityLevel.incompatible;
    final cs = Theme.of(context).colorScheme;
    
    return Opacity(
      opacity: isIncompatible ? 0.6 : 1.0,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(UiTokens.r16),
          side: isSelected
              ? BorderSide(
                  color: cs.primary.withOpacity(0.80),
                  width: 1.5,
                )
              : isRecommended
                  ? BorderSide(
                      color: Colors.green.withOpacity(0.70),
                      width: 1.5,
                    )
                  : BorderSide(color: cs.onSurface.withOpacity(0.08)),
        ),
        child: InkWell(
          onTap: isIncompatible ? null : onSelect,
          borderRadius: BorderRadius.circular(UiTokens.r16),
          child: Padding(
            padding: const EdgeInsets.all(UiTokens.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    // Compatibility indicator
                    _CompatibilityBadge(level: level),
                    const SizedBox(width: UiTokens.s12),
                    
                    // Model info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Use Wrap to prevent overflow with model name and badge
                          Wrap(
                            spacing: UiTokens.s8,
                            runSpacing: UiTokens.s4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                model.name,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (isRecommended)
                                Chip(
                                  label: const Text('Recommended'),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor: Colors.green.withOpacity(0.12),
                                  side: BorderSide(color: Colors.green.withOpacity(0.18)),
                                  labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                                        color: Colors.green.shade700,
                                      ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${model.parameters} • ${model.quantization}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.60),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    
                    // Size badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: UiTokens.s12,
                        vertical: UiTokens.s8,
                      ),
                      decoration: BoxDecoration(
                        color: cs.onSurface.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(UiTokens.r12),
                        border: Border.all(color: cs.onSurface.withOpacity(0.08)),
                      ),
                      child: Text(
                        model.sizeFormatted,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface.withOpacity(0.75),
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: UiTokens.s12),
                
                // Description
                Text(
                  model.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.70),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                
                const SizedBox(height: UiTokens.s12),
                
                // Performance estimates
                if (!isIncompatible) _buildPerformanceRow(context),
                
                // Warnings
                if (compatibility.warnings.isNotEmpty) ...[
                  const SizedBox(height: UiTokens.s12),
                  _buildWarnings(context),
                ],
                
                // Strengths
                if (model.strengths.isNotEmpty) ...[
                  const SizedBox(height: UiTokens.s12),
                  _buildStrengths(context),
                ],
                
                // Languages
                if (model.supportedLanguages.length > 1) ...[
                  const SizedBox(height: UiTokens.s12),
                  _buildLanguages(context),
                ],
                
                // Download button
                if (!isIncompatible) ...[
                  const SizedBox(height: UiTokens.s16),
                  _buildDownloadButton(context),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildDownloadButton(BuildContext context) {
    if (isDownloading) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: downloadProgress > 0 ? downloadProgress : null,
                    valueColor: AlwaysStoppedAnimation(Colors.blue.shade700),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Downloading...',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '${(downloadProgress * 100).toInt()}%',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: downloadProgress > 0 ? downloadProgress : null,
                backgroundColor: Colors.blue.shade100,
                valueColor: AlwaysStoppedAnimation(Colors.blue.shade600),
                minHeight: 6,
              ),
            ),
          ],
        ),
      );
    }
    
    if (isDownloaded) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onSelect,
          icon: const Icon(Icons.check_circle, size: 18),
          label: const Text('Downloaded - Tap to Use'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.green.shade700,
            side: BorderSide(color: Colors.green.shade400),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      );
    }
    
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onDownload,
        icon: const Icon(Icons.download, size: 18),
        label: Text('Download (${compatibility.model.sizeFormatted})'),
        style: ElevatedButton.styleFrom(
          backgroundColor: isRecommended ? Colors.green : Colors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
  
  Widget _buildPerformanceRow(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PerformanceItem(
              icon: Icons.speed,
              label: 'Speed',
              value: '~${compatibility.estimatedTokensPerSecond.toStringAsFixed(1)} t/s',
              subLabel: compatibility.performanceEstimate,
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.blue.shade200,
          ),
          Expanded(
            child: _PerformanceItem(
              icon: Icons.hourglass_bottom,
              label: 'First Token',
              value: '~${compatibility.estimatedTimeToFirstTokenMs}ms',
              subLabel: _getLatencyLabel(compatibility.estimatedTimeToFirstTokenMs),
            ),
          ),
          Container(
            width: 1,
            height: 40,
            color: Colors.blue.shade200,
          ),
          Expanded(
            child: _PerformanceItem(
              icon: Icons.memory,
              label: 'RAM Needed',
              value: compatibility.model.minRamFormatted,
              subLabel: compatibility.hasEnoughRam ? 'OK' : 'Low',
            ),
          ),
        ],
      ),
    );
  }
  
  String _getLatencyLabel(int ms) {
    if (ms < 300) return 'Fast';
    if (ms < 600) return 'Good';
    if (ms < 1000) return 'Moderate';
    return 'Slow';
  }
  
  Widget _buildWarnings(BuildContext context) {
    return Column(
      children: compatibility.warnings.map((warning) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 16,
                color: Colors.orange.shade700,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  warning,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade700,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
  
  Widget _buildStrengths(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: compatibility.model.strengths.map((strength) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Text(
            strength,
            style: TextStyle(
              fontSize: 11,
              color: Colors.green.shade700,
            ),
          ),
        );
      }).toList(),
    );
  }
  
  Widget _buildLanguages(BuildContext context) {
    final languages = compatibility.model.supportedLanguages;
    final displayLanguages = languages.take(5).toList();
    final remaining = languages.length - 5;
    
    return Row(
      children: [
        Icon(
          Icons.language,
          size: 14,
          color: Colors.grey.shade500,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            displayLanguages.map((l) => l.toUpperCase()).join(', ') +
                (remaining > 0 ? ' +$remaining more' : ''),
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }
}

class _CompatibilityBadge extends StatelessWidget {
  final CompatibilityLevel level;
  
  const _CompatibilityBadge({required this.level});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            level.emoji,
            style: const TextStyle(fontSize: 20),
          ),
          Text(
            '${_score}%',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ),
        ],
      ),
    );
  }
  
  int get _score {
    switch (level) {
      case CompatibilityLevel.excellent: return 95;
      case CompatibilityLevel.good: return 80;
      case CompatibilityLevel.fair: return 60;
      case CompatibilityLevel.poor: return 35;
      case CompatibilityLevel.incompatible: return 0;
    }
  }
  
  Color get _backgroundColor {
    switch (level) {
      case CompatibilityLevel.excellent: return Colors.green.shade100;
      case CompatibilityLevel.good: return Colors.lightGreen.shade100;
      case CompatibilityLevel.fair: return Colors.orange.shade100;
      case CompatibilityLevel.poor: return Colors.red.shade100;
      case CompatibilityLevel.incompatible: return Colors.grey.shade200;
    }
  }
  
  Color get _textColor {
    switch (level) {
      case CompatibilityLevel.excellent: return Colors.green.shade700;
      case CompatibilityLevel.good: return Colors.lightGreen.shade700;
      case CompatibilityLevel.fair: return Colors.orange.shade700;
      case CompatibilityLevel.poor: return Colors.red.shade700;
      case CompatibilityLevel.incompatible: return Colors.grey.shade600;
    }
  }
}

class _PerformanceItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subLabel;
  
  const _PerformanceItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.subLabel,
  });
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          icon,
          size: 16,
          color: Colors.blue.shade700,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade900,
          ),
        ),
        Text(
          subLabel,
          style: TextStyle(
            fontSize: 10,
            color: Colors.blue.shade600,
          ),
        ),
      ],
    );
  }
}
