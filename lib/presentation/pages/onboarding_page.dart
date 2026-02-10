import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/model_info.dart';
import '../blocs/model/model_bloc.dart';
import '../theme/ui_tokens.dart';
import '../widgets/motion/fade_slide.dart';

/// Onboarding page for model download.
/// 
/// Displayed when the model is not yet downloaded. Handles the download
/// process with progress indication and error recovery.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});
  
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: BlocConsumer<ModelBloc, ModelState>(
          listener: (context, state) {
            // Navigate to chat when model is ready
            if (state.isReady) {
              Navigator.of(context).pushReplacementNamed('/chat');
            }
            
            // Show error snackbar
            if (state.hasError) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.errorMessage ?? 'An error occurred'),
                  backgroundColor: Theme.of(context).colorScheme.error,
                  action: SnackBarAction(
                    label: 'Retry',
                    textColor: Colors.white,
                    onPressed: () {
                      context.read<ModelBloc>().add(const ModelDownloadStarted());
                    },
                  ),
                ),
              );
            }
          },
          builder: (context, state) {
            return Padding(
              padding: const EdgeInsets.all(UiTokens.s24),
              child: Column(
                children: [
                  const Spacer(),
                  
                  // App icon/logo
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(UiTokens.r24),
                      boxShadow: [softShadow(context)],
                    ),
                    child: Icon(
                      Icons.chat_bubble_rounded,
                      size: 64,
                      color: cs.primary,
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Title
                  Text(
                    'MicroLLM',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Subtitle
                  Text(
                    'Your offline AI assistant',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: cs.onSurface.withOpacity(0.65),
                    ),
                  ),
                  
                  const SizedBox(height: 48),
                  
                  // Status/Progress area
                  AnimatedSwitcher(
                    duration: UiTokens.durMed,
                    switchInCurve: UiTokens.curveStandard,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) =>
                        fadeSlideSwitcherTransition(
                      child,
                      animation,
                      fromOffset: const Offset(0, 0.06),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(state.status),
                      child: _buildStatusArea(context, state),
                    ),
                  ),
                  
                  const Spacer(),
                  
                  // Action button
                  AnimatedSwitcher(
                    duration: UiTokens.durMed,
                    switchInCurve: UiTokens.curveStandard,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) =>
                        fadeSlideSwitcherTransition(
                      child,
                      animation,
                      fromOffset: const Offset(0, 0.08),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey('btn-${state.status}'),
                      child: _buildActionButton(context, state),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Device compatibility link
                  TextButton.icon(
                    onPressed: () => Navigator.pushNamed(context, '/device-compatibility'),
                    icon: const Icon(Icons.speed, size: 18),
                    label: const Text('Check Device Compatibility'),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Privacy notice
                  Text(
                    'All processing happens on your device.\nNo data is sent to external servers.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.55),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
  
  Widget _buildStatusArea(BuildContext context, ModelState state) {
    switch (state.status) {
      case ModelStatus.notDownloaded:
        return _buildDownloadPrompt(context);
      
      case ModelStatus.downloading:
        return _buildDownloadProgress(context, state);
      
      case ModelStatus.downloaded:
        return _buildLoadPrompt(context, state);
      
      case ModelStatus.loading:
        return _buildLoadingIndicator(context);
      
      case ModelStatus.error:
        return _buildErrorState(context, state);
      
      default:
        return const SizedBox.shrink();
    }
  }
  
  Widget _buildDownloadPrompt(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(UiTokens.r16),
            border: Border.all(color: cs.primary.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              Icon(Icons.download_rounded, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Model Required',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Download the AI model (~1 GB) to get started.',
                      style: TextStyle(
                        color: cs.onSurface.withOpacity(0.70),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Make sure you\'re connected to WiFi',
          style: TextStyle(color: cs.onSurface.withOpacity(0.65), fontSize: 13),
        ),
      ],
    );
  }
  
  Widget _buildDownloadProgress(BuildContext context, ModelState state) {
    final progress = state.downloadProgress;
    final cs = Theme.of(context).colorScheme;
    
    return Column(
      children: [
        CircularProgressIndicator(strokeWidth: 3, color: cs.primary),
        const SizedBox(height: 24),
        Text(
          'Downloading model...',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        if (progress != null) ...[
          LinearProgressIndicator(
            value: progress.progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${progress.downloadedFormatted} / ${progress.totalFormatted}',
                style: TextStyle(color: cs.onSurface.withOpacity(0.65), fontSize: 13),
              ),
              Text(
                progress.speedFormatted,
                style: TextStyle(color: cs.onSurface.withOpacity(0.65), fontSize: 13),
              ),
            ],
          ),
        ],
      ],
    );
  }
  
  Widget _buildLoadPrompt(BuildContext context, ModelState state) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.10),
            borderRadius: BorderRadius.circular(UiTokens.r16),
            border: Border.all(color: Colors.green.withOpacity(0.18)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Model Downloaded',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withOpacity(0.90),
                      ),
                    ),
                    if (state.modelInfo != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${state.modelInfo!.parameterCount} parameters • ${state.modelInfo!.sizeFormatted}',
                        style: TextStyle(
                          color: cs.onSurface.withOpacity(0.65),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Tap continue to load the model',
          style: TextStyle(color: cs.onSurface.withOpacity(0.65), fontSize: 13),
        ),
      ],
    );
  }
  
  Widget _buildLoadingIndicator(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        const SizedBox(
          width: 60,
          height: 60,
          child: CircularProgressIndicator(strokeWidth: 4),
        ),
        const SizedBox(height: 24),
        Text(
          'Loading model into memory...',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.secondary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(UiTokens.r12),
            border: Border.all(color: cs.secondary.withOpacity(0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hourglass_empty, color: cs.secondary, size: 20),
              const SizedBox(width: 8),
              Text(
                'This may take 1-5 minutes',
                style: TextStyle(
                  color: cs.onSurface.withOpacity(0.80),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Please keep the app open.\nThe screen may briefly freeze during loading.',
          style: TextStyle(color: cs.onSurface.withOpacity(0.65), fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
  
  Widget _buildErrorState(BuildContext context, ModelState state) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.error.withOpacity(0.10),
        borderRadius: BorderRadius.circular(UiTokens.r16),
        border: Border.all(color: cs.error.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: cs.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Error',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: cs.error,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  state.errorMessage ?? 'An unexpected error occurred',
                  style: TextStyle(
                    color: cs.onSurface.withOpacity(0.75),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildActionButton(BuildContext context, ModelState state) {
    switch (state.status) {
      case ModelStatus.notDownloaded:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              context.read<ModelBloc>().add(const ModelDownloadStarted());
            },
            child: const Text('Download Model'),
          ),
        );
      
      case ModelStatus.downloading:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              context.read<ModelBloc>().add(const ModelDownloadCancelled());
            },
            child: const Text('Cancel'),
          ),
        );
      
      case ModelStatus.downloaded:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              context.read<ModelBloc>().add(const ModelLoadRequested());
            },
            child: const Text('Continue'),
          ),
        );
      
      case ModelStatus.error:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              if (state.modelInfo != null) {
                context.read<ModelBloc>().add(const ModelLoadRequested());
              } else {
                context.read<ModelBloc>().add(const ModelDownloadStarted());
              }
            },
            child: const Text('Retry'),
          ),
        );
      
      default:
        return const SizedBox.shrink();
    }
  }
}
