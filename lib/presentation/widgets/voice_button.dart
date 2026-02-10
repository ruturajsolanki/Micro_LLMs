import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/voice/voice_bloc.dart';
import '../blocs/settings/settings_bloc.dart';
import '../../domain/entities/speech_to_text_engine.dart';

/// Voice input button widget.
/// 
/// Shows microphone icon that activates speech-to-text.
/// Changes appearance when listening.
class VoiceButton extends StatelessWidget {
  final bool enabled;
  final void Function(String text) onResult;
  
  const VoiceButton({
    super.key,
    required this.enabled,
    required this.onResult,
  });
  
  @override
  Widget build(BuildContext context) {
    return BlocConsumer<VoiceBloc, VoiceState>(
      listenWhen: (previous, current) {
        final recognizedTextChanged = previous.recognizedText != current.recognizedText;

        // Final results: recognizer finished and we have non-empty text.
        final gotFinalText = recognizedTextChanged &&
            current.recognizedText.isNotEmpty &&
            current.sttStatus == VoiceSttStatus.idle;

        // Partial results: update input live while listening so the user
        // sees immediate feedback (otherwise it feels like nothing happens).
        final gotPartialText = recognizedTextChanged &&
            current.recognizedText.isNotEmpty &&
            current.sttStatus == VoiceSttStatus.listening;

        final newError = previous.errorMessage != current.errorMessage &&
            current.hasSttError &&
            (current.errorMessage?.isNotEmpty ?? false);

        return gotFinalText || gotPartialText || newError;
      },
      listener: (context, state) {
        if (state.hasSttError && (state.errorMessage?.isNotEmpty ?? false)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.errorMessage!),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }

        if (state.recognizedText.isNotEmpty) {
          onResult(state.recognizedText);
        }
      },
      builder: (context, state) {
        final isListening = state.isListening;
        final levelDb = state.inputLevelDb;

        return SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VoiceCaptureAnimation(active: isListening, levelDb: levelDb),
              IconButton(
                onPressed: enabled ? () => _toggleListening(context, state) : null,
                icon: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    isListening ? Icons.mic : Icons.mic_none,
                    key: ValueKey(isListening),
                  ),
                ),
                style: IconButton.styleFrom(
                  backgroundColor: isListening
                      ? Theme.of(context).colorScheme.error.withOpacity(0.12)
                      : Colors.transparent,
                  foregroundColor: isListening
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  minimumSize: const Size(56, 56),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  void _toggleListening(BuildContext context, VoiceState state) {
    if (state.isListening) {
      context.read<VoiceBloc>().add(const VoiceRecognitionStopped());
    } else {
      final settings = context.read<SettingsBloc>().state.settings;
      context.read<VoiceBloc>().add(VoiceRecognitionStarted(
        engine: settings.speechToTextEngine,
        language: settings.sourceLanguage,
        offlineOnly: settings.voiceSttOfflineOnly,
        whisperModelId: settings.whisperModelId,
      ));
    }
  }
}

/// Simple pulsing animation while listening.
class VoiceCaptureAnimation extends StatefulWidget {
  final bool active;
  final double? levelDb;

  const VoiceCaptureAnimation({super.key, required this.active, this.levelDb});

  @override
  State<VoiceCaptureAnimation> createState() => _VoiceCaptureAnimationState();
}

class _VoiceCaptureAnimationState extends State<VoiceCaptureAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.6).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _opacity = Tween<double>(begin: 0.35, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant VoiceCaptureAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();

    final color = Theme.of(context).colorScheme.error;
    // Normalize typical rms range (-2..10) -> (0..1)
    final db = widget.levelDb ?? 0.0;
    final norm = ((db + 2.0) / 12.0).clamp(0.0, 1.0);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final glowStrength = 0.10 + 0.20 * norm;
        return Transform.scale(
          scale: _scale.value * (1.0 + 0.35 * norm),
          child: Opacity(
            opacity: _opacity.value,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(glowStrength),
                    blurRadius: 14,
                    spreadRadius: 3,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
