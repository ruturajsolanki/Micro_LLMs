import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injection.dart';
import '../../data/datasources/device_scanner_datasource.dart';
import '../../domain/entities/device_specs.dart';
import '../../domain/services/device_benchmark.dart';
import '../blocs/device/device_bloc.dart';
import '../widgets/device_specs_card.dart';
import '../widgets/model_compatibility_card.dart';
import '../widgets/benchmark_dialog.dart';
import '../theme/ui_tokens.dart';
import '../widgets/motion/fade_slide.dart';

/// Page showing device specs and model compatibility.
/// 
/// Displays:
/// - Device hardware specifications
/// - Performance tier assessment
/// - Compatible models with performance estimates
/// - Recommended model
class DeviceCompatibilityPage extends StatelessWidget {
  const DeviceCompatibilityPage({super.key});
  
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DeviceBloc(
        deviceScanner: sl<DeviceScannerDataSource>(),
      )..add(const DeviceScanRequested()),
      child: const DeviceCompatibilityView(),
    );
  }
}

class DeviceCompatibilityView extends StatelessWidget {
  const DeviceCompatibilityView({super.key});
  
  void _showBenchmarkDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const BenchmarkDialog(),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Compatibility'),
        actions: [
          IconButton(
            icon: const Icon(Icons.speed),
            tooltip: 'Run Benchmark',
            onPressed: () => _showBenchmarkDialog(context),
          ),
          BlocBuilder<DeviceBloc, DeviceState>(
            builder: (context, state) {
              return IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: state.isScanning
                    ? null
                    : () => context.read<DeviceBloc>().add(
                          const DeviceScanRequested(),
                        ),
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<DeviceBloc, DeviceState>(
        builder: (context, state) {
          Widget child;
          if (state.isScanning) {
            child = const _LoadingView(key: ValueKey('loading'));
          } else if (state.hasError) {
            child = _ErrorView(key: const ValueKey('error'), message: state.errorMessage);
          } else if (!state.isComplete || state.deviceSpecs == null) {
            child = const _LoadingView(key: ValueKey('loading2'));
          } else {
            child = _ContentView(key: const ValueKey('content'), state: state);
          }

          return AnimatedSwitcher(
            duration: UiTokens.durMed,
            switchInCurve: UiTokens.curveStandard,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (c, a) =>
                fadeSlideSwitcherTransition(c, a, fromOffset: const Offset(0, 0.04)),
            child: child,
          );
        },
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({super.key});
  
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: cs.primary),
          const SizedBox(height: 24),
          Text(
            'Scanning device...',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Analyzing hardware capabilities',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: cs.onSurface.withOpacity(0.60),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String? message;
  
  const _ErrorView({super.key, this.message});
  
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(UiTokens.s24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: cs.error.withOpacity(0.75),
            ),
            const SizedBox(height: 16),
            Text(
              'Scan Failed',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message ?? 'Failed to scan device specifications',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurface.withOpacity(0.65),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.read<DeviceBloc>().add(
                    const DeviceScanRequested(),
                  ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContentView extends StatelessWidget {
  final DeviceState state;
  
  const _ContentView({super.key, required this.state});
  
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: UiTokens.pagePadding,
      children: [
        // Device Info Card with RAM cleanup callback
        DeviceSpecsCard(
          specs: state.deviceSpecs!,
          onSpecsUpdated: () {
            // Rescan to get updated memory info after cleanup
            context.read<DeviceBloc>().add(const DeviceScanRequested());
          },
        ),
        
        const SizedBox(height: UiTokens.s24),
        
        // Performance Tier
        _buildPerformanceTier(context, state.deviceSpecs!),
        
        const SizedBox(height: UiTokens.s24),
        
        // Recommended Model
        if (state.recommendedModel != null) ...[
          Text(
            'Recommended Model',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ModelCompatibilityCard(
            compatibility: state.recommendedModel!,
            isRecommended: true,
            isSelected: state.selectedModel?.model.id == 
                        state.recommendedModel!.model.id,
            isDownloaded: state.isModelDownloaded(state.recommendedModel!.model.id),
            isDownloading: state.isModelDownloading(state.recommendedModel!.model.id),
            downloadProgress: state.isModelDownloading(state.recommendedModel!.model.id)
                ? state.downloadProgress
                : 0.0,
            onSelect: () => context.read<DeviceBloc>().add(
              DeviceModelSelected(modelId: state.recommendedModel!.model.id),
            ),
            onDownload: () => context.read<DeviceBloc>().add(
              ModelDownloadRequested(modelId: state.recommendedModel!.model.id),
            ),
          ),
          const SizedBox(height: UiTokens.s24),
        ],
        
        // All Models
        Text(
          'All Models',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Sorted by compatibility with your device',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 12),
        
        ...state.modelAssessments.map((assessment) {
          final isRecommended = state.recommendedModel?.model.id == 
                                assessment.model.id;
          
          // Skip recommended as it's shown above
          if (isRecommended) return const SizedBox.shrink();
          
          return Padding(
            padding: const EdgeInsets.only(bottom: UiTokens.s12),
            child: ModelCompatibilityCard(
              compatibility: assessment,
              isRecommended: false,
              isSelected: state.selectedModel?.model.id == assessment.model.id,
              isDownloaded: state.isModelDownloaded(assessment.model.id),
              isDownloading: state.isModelDownloading(assessment.model.id),
              downloadProgress: state.isModelDownloading(assessment.model.id)
                  ? state.downloadProgress
                  : 0.0,
              onSelect: () => context.read<DeviceBloc>().add(
                DeviceModelSelected(modelId: assessment.model.id),
              ),
              onDownload: () => context.read<DeviceBloc>().add(
                ModelDownloadRequested(modelId: assessment.model.id),
              ),
            ),
          );
        }),
        
        const SizedBox(height: 24),
        
        // Legend
        _buildLegend(context),
        
        const SizedBox(height: 16),
      ],
    );
  }
  
  Widget _buildPerformanceTier(BuildContext context, DeviceSpecs specs) {
    final tierColor = _getTierColor(specs.performanceTier);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            tierColor.withOpacity(0.1),
            tierColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tierColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: tierColor.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${specs.performanceTier}',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: tierColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  specs.performanceTierName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: tierColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getTierDescription(specs.performanceTier),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Color _getTierColor(int tier) {
    switch (tier) {
      case 5: return Colors.purple;
      case 4: return Colors.blue;
      case 3: return Colors.green;
      case 2: return Colors.orange;
      default: return Colors.grey;
    }
  }
  
  String _getTierDescription(int tier) {
    switch (tier) {
      case 5: return 'Can run all models with excellent performance';
      case 4: return 'Can run most models smoothly';
      case 3: return 'Good for medium-sized models';
      case 2: return 'Best suited for smaller models';
      default: return 'Limited to smallest models only';
    }
  }
  
  Widget _buildLegend(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Compatibility Legend',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _legendItem(CompatibilityLevel.excellent),
          _legendItem(CompatibilityLevel.good),
          _legendItem(CompatibilityLevel.fair),
          _legendItem(CompatibilityLevel.poor),
          _legendItem(CompatibilityLevel.incompatible),
        ],
      ),
    );
  }
  
  Widget _legendItem(CompatibilityLevel level) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            level.emoji,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(width: 8),
          Text(
            level.displayName,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _levelDescription(level),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  String _levelDescription(CompatibilityLevel level) {
    switch (level) {
      case CompatibilityLevel.excellent:
        return 'Fast, smooth experience';
      case CompatibilityLevel.good:
        return 'Works well, recommended';
      case CompatibilityLevel.fair:
        return 'Usable but may be slow';
      case CompatibilityLevel.poor:
        return 'Will struggle, not recommended';
      case CompatibilityLevel.incompatible:
        return 'Cannot run on this device';
    }
  }
}
