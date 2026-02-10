import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/di/injection.dart';
import '../../domain/entities/message.dart';
import '../../data/datasources/conversation_storage.dart';
import '../blocs/chat/chat_bloc.dart';
import '../blocs/model/model_bloc.dart';
import '../blocs/settings/settings_bloc.dart';
import '../blocs/voice/voice_bloc.dart';
import '../widgets/chat_input.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/model_status_banner.dart';
import '../widgets/voice_button.dart';
import '../widgets/motion/fade_slide.dart';
import '../theme/ui_tokens.dart';
import 'chat_history_page.dart';

/// Main chat page.
/// 
/// Displays the conversation with the LLM and provides input controls.
class ChatPage extends StatelessWidget {
  const ChatPage({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ChatBloc>(
          create: (_) => sl<ChatBloc>(),
        ),
        BlocProvider<VoiceBloc>(
          create: (_) => sl<VoiceBloc>(),
        ),
      ],
      child: const ChatView(),
    );
  }
}

class ChatView extends StatefulWidget {
  const ChatView({super.key});
  
  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();

  final Set<String> _seenMessageIds = <String>{};

  bool _voiceAutoSending = false;
  String? _lastVoiceAutoSentText;
  bool _voiceCallMode = false;
  String? _lastSpokenAssistantMessageId;
  
  @override
  void initState() {
    super.initState();
    
    // Initialize chat with language settings
    final settingsState = context.read<SettingsBloc>().state;
    context.read<ChatBloc>().add(ChatStarted(
      sourceLanguage: settingsState.settings.sourceLanguage,
      targetLanguage: settingsState.settings.targetLanguage,
    ));
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }
  
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: UiTokens.durSlow,
          curve: UiTokens.curveStandard,
        );
      }
    });
  }
  
  void _onSendMessage(String message) {
    if (message.trim().isEmpty) return;
    
    context.read<ChatBloc>().add(ChatMessageSent(content: message));
    _inputController.clear();
    _scrollToBottom();
  }
  
  void _onCancelGeneration() {
    context.read<ChatBloc>().add(const ChatGenerationCancelled());
  }

  void _toggleVoiceCallMode() {
    final next = !_voiceCallMode;
    setState(() => _voiceCallMode = next);

    final voiceBloc = context.read<VoiceBloc>();
    if (!next) {
      voiceBloc.add(const VoiceRecognitionStopped());
      voiceBloc.add(const VoiceSynthesisStopped());
      return;
    }

    final settings = context.read<SettingsBloc>().state.settings;
    voiceBloc.add(VoiceRecognitionStarted(
      engine: settings.speechToTextEngine,
      language: settings.sourceLanguage,
      offlineOnly: settings.voiceSttOfflineOnly,
      whisperModelId: settings.whisperModelId,
    ));
  }
  
  @override
  Widget build(BuildContext context) {
    return BlocListener<SettingsBloc, SettingsState>(
      listenWhen: (previous, current) {
        return previous.settings.sourceLanguage != current.settings.sourceLanguage ||
            previous.settings.targetLanguage != current.settings.targetLanguage;
      },
      listener: (context, settingsState) {
        // Apply language changes immediately to:
        // - conversation metadata (so UI/history match)
        // - native incremental prompt buffer (so model replies in the right language)
        context.read<ChatBloc>().add(
              ChatLanguagesUpdated(
                sourceLanguage: settingsState.settings.sourceLanguage,
                targetLanguage: settingsState.settings.targetLanguage,
              ),
            );

        // If we're in call mode, restart listening with the new input language.
        if (_voiceCallMode) {
          final voiceBloc = context.read<VoiceBloc>();
          voiceBloc.add(const VoiceRecognitionStopped());
          voiceBloc.add(VoiceRecognitionStarted(
            engine: settingsState.settings.speechToTextEngine,
            language: settingsState.settings.sourceLanguage,
            offlineOnly: settingsState.settings.voiceSttOfflineOnly,
            whisperModelId: settingsState.settings.whisperModelId,
          ));
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('MicroLLM'),
          actions: [
          IconButton(
            tooltip: _voiceCallMode ? 'End voice call' : 'Start voice call',
            icon: Icon(_voiceCallMode ? Icons.call_end : Icons.call),
            onPressed: _toggleVoiceCallMode,
          ),
          BlocBuilder<ChatBloc, ChatState>(
            builder: (context, state) {
              final tokens = state.lastGenerationTokenCount;
              final durationMs = state.lastGenerationDurationMs;
              final tps = state.tokensPerSecond;

              if (tokens != null && durationMs != null) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: Text(
                      '${(durationMs / 1000).toStringAsFixed(2)}s • $tokens tok'
                      '${tps == null ? '' : ' • ${tps.toStringAsFixed(1)} t/s'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showOptionsMenu(context),
          ),
          ],
        ),
        body: Column(
          children: [
          // Model status banner
          BlocBuilder<ModelBloc, ModelState>(
            builder: (context, state) {
              if (!state.isReady) {
                return ModelStatusBanner(state: state);
              }
              return const SizedBox.shrink();
            },
          ),

          // Conversation tabs (quick switch between saved chats)
          const _ConversationTabsBar(),
          
          // Chat messages
          Expanded(
            child: BlocConsumer<ChatBloc, ChatState>(
              listener: (context, state) {
                // Scroll to bottom when new message arrives
                if (state.isGenerating) {
                  _scrollToBottom();
                }

                // Auto-speak assistant replies if enabled
                final settings = context.read<SettingsBloc>().state.settings;
                final shouldSpeak = _voiceCallMode || settings.voiceOutputEnabled;
                if (shouldSpeak &&
                    !state.isGenerating &&
                    state.conversation.messages.isNotEmpty) {
                  final last = state.conversation.messages.last;
                  if (last.role == MessageRole.assistant &&
                      !last.isStreaming &&
                      last.content.trim().isNotEmpty) {
                    if (_lastSpokenAssistantMessageId == last.id) return;
                    _lastSpokenAssistantMessageId = last.id;

                    if (_voiceCallMode) {
                      // Avoid the recognizer hearing the TTS output.
                      context.read<VoiceBloc>().add(const VoiceRecognitionStopped());
                    }
                    context.read<VoiceBloc>().add(
                          VoiceSynthesisStarted(
                            engine: settings.textToSpeechEngine,
                            text: last.content,
                            language: settings.targetLanguage,
                            elevenLabsVoiceId: settings.elevenLabsVoiceId,
                          ),
                        );
                  }
                }
              },
              builder: (context, state) {
                if (state.conversation.isEmpty) {
                  return _buildEmptyState(context);
                }
                
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: UiTokens.s16,
                    vertical: UiTokens.s8,
                  ),
                  itemCount: state.conversation.messages.length,
                  itemBuilder: (context, index) {
                    final message = state.conversation.messages[index];
                    
                    // Skip system messages
                    if (message.role == MessageRole.system) {
                      return const SizedBox.shrink();
                    }
                    
                    final animateIn = !_seenMessageIds.contains(message.id);
                    _seenMessageIds.add(message.id);

                    return RepaintBoundary(
                      child: ChatMessageBubble(
                        key: ValueKey(message.id),
                        message: message,
                        animateIn: animateIn,
                        onTranslate: () {
                          context.read<ChatBloc>().add(
                            ChatTranslationRequested(messageId: message.id),
                          );
                        },
                        onSpeak: () {
                          final settings = context.read<SettingsBloc>().state.settings;
                          context.read<VoiceBloc>().add(
                            VoiceSynthesisStarted(
                              engine: settings.textToSpeechEngine,
                              text: message.content,
                              language: message.role == MessageRole.user
                                  ? settings.sourceLanguage
                                  : settings.targetLanguage,
                              elevenLabsVoiceId: settings.elevenLabsVoiceId,
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
          
          // Input area
          BlocBuilder<ModelBloc, ModelState>(
            builder: (context, modelState) {
              return BlocBuilder<SettingsBloc, SettingsState>(
                builder: (context, settingsState) {
                  return BlocBuilder<ChatBloc, ChatState>(
                    builder: (context, chatState) {
                      final isEnabled = modelState.isReady && !chatState.isGenerating;
                      final voiceInputEnabled = settingsState.settings.voiceInputEnabled;
                      
                      return BlocListener<VoiceBloc, VoiceState>(
                        listenWhen: (prev, curr) {
                          final ttsFinishedInCallMode = _voiceCallMode &&
                              prev.ttsStatus == VoiceTtsStatus.speaking &&
                              curr.ttsStatus == VoiceTtsStatus.idle;
                          if (ttsFinishedInCallMode) return true;

                          final stoppedTalking = prev.sttStatus == VoiceSttStatus.listening &&
                              curr.sttStatus == VoiceSttStatus.idle &&
                              curr.recognizedText.trim().isNotEmpty;
                          return stoppedTalking;
                        },
                        listener: (context, voiceState) async {
                          // After TTS ends in call mode, restart listening.
                          if (_voiceCallMode &&
                              voiceState.ttsStatus == VoiceTtsStatus.idle &&
                              !voiceState.isListening) {
                            final settings = context.read<SettingsBloc>().state.settings;
                            context.read<VoiceBloc>().add(
                                  VoiceRecognitionStarted(
                                    engine: settings.speechToTextEngine,
                                    language: settings.sourceLanguage,
                                    offlineOnly: settings.voiceSttOfflineOnly,
                                    whisperModelId: settings.whisperModelId,
                                  ),
                                );
                            return;
                          }

                          // Auto-send on final STT result for a smooth voice flow.
                          final text = voiceState.recognizedText.trim();
                          if (text.isEmpty) return;

                          // Avoid double-send for the same final result.
                          if (_lastVoiceAutoSentText == text) return;
                          _lastVoiceAutoSentText = text;

                          // Always reflect the final text in the input first.
                          _inputController.value = TextEditingValue(
                            text: text,
                            selection: TextSelection.collapsed(offset: text.length),
                          );

                          // Only auto-send if model is ready and chat isn't generating.
                          final canAutoSend = context.read<ModelBloc>().state.isReady &&
                              !context.read<ChatBloc>().state.isGenerating;

                          if (!canAutoSend) return;

                          if (mounted) setState(() => _voiceAutoSending = true);

                          // Small delay so the user sees the final transcript + a "sending" feel.
                          await Future.delayed(const Duration(milliseconds: 220));
                          if (!mounted) return;

                          _onSendMessage(text);

                          if (mounted) {
                            setState(() => _voiceAutoSending = false);
                          }
                        },
                        child: BlocBuilder<VoiceBloc, VoiceState>(
                          builder: (context, voiceState) {
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_voiceCallMode)
                                  _CallModeBanner(
                                    onEnd: _toggleVoiceCallMode,
                                  ),
                                if (voiceInputEnabled)
                                  AnimatedSwitcher(
                                    duration: UiTokens.durMed,
                                    switchInCurve: UiTokens.curveStandard,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, animation) =>
                                        fadeSlideSwitcherTransition(
                                      child,
                                      animation,
                                      fromOffset: const Offset(0, 0.10),
                                    ),
                                    child: _voiceAutoSending
                                        ? const _SendingBanner(key: ValueKey('sending'))
                                        : (voiceState.isListening
                                            ? _ListeningBanner(
                                                key: const ValueKey('listening'),
                                                text: voiceState.recognizedText,
                                                levelDb: voiceState.inputLevelDb,
                                              )
                                            : const SizedBox.shrink(
                                                key: ValueKey('idle'),
                                              )),
                                  ),
                                ChatInput(
                                  controller: _inputController,
                                  enabled: isEnabled,
                                  isGenerating: chatState.isGenerating,
                                  onSend: _onSendMessage,
                                  onCancel: _onCancelGeneration,
                                  voiceButton: voiceInputEnabled
                                      ? VoiceButton(
                                          enabled: isEnabled,
                                          onResult: (text) {
                                            // Live partial transcript updates.
                                            _inputController.value = TextEditingValue(
                                              text: text,
                                              selection: TextSelection.collapsed(offset: text.length),
                                            );
                                          },
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'Start a conversation',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Type a message or use voice input to begin',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  void _showOptionsMenu(BuildContext context) {
    // Capture the page-level bloc + navigator context.
    // The bottom sheet gets its own overlay context which might not be able
    // to resolve providers correctly.
    final pageContext = context;
    final chatBloc = pageContext.read<ChatBloc>();

    showModalBottomSheet(
      context: pageContext,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Chat history'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    pageContext,
                    MaterialPageRoute(
                      builder: (_) => BlocProvider.value(
                        value: chatBloc,
                        child: const ChatHistoryPage(),
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_comment_outlined),
                title: const Text('New chat (close current)'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  chatBloc.add(const ChatNewConversationRequested());
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Clear conversation'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  chatBloc.add(const ChatConversationCleared());
                },
              ),
              ListTile(
                leading: const Icon(Icons.speed_outlined),
                title: const Text('Voice benchmark'),
                subtitle: const Text('Record & evaluate summarization'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.pushNamed(pageContext, '/benchmark');
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.pushNamed(pageContext, '/settings');
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('About'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showAboutDialog(pageContext);
                },
              ),
            ],
          ),
        );
      },
    );
  }
  
  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('MicroLLM'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Version 1.0.0'),
              SizedBox(height: 8),
              Text('An offline-first multilingual conversational assistant.'),
              SizedBox(height: 8),
              Text('Powered by llama.cpp and Phi-2.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

class _ConversationTabsBar extends StatelessWidget {
  const _ConversationTabsBar();

  @override
  Widget build(BuildContext context) {
    final storage = sl<ConversationStorage>();
    final conversationsBox = sl<Box<dynamic>>(instanceName: 'conversationsBox');

    return BlocBuilder<ChatBloc, ChatState>(
      buildWhen: (p, c) => p.conversation.id != c.conversation.id,
      builder: (context, chatState) {
        return ValueListenableBuilder(
          valueListenable: conversationsBox.listenable(keys: const [
            ConversationStorage.conversationIndexKey,
            ConversationStorage.activeConversationIdKey,
          ]),
          builder: (context, _, __) {
            final items = storage.listConversations();
            final activeId = chatState.conversation.id;

            // Hide tabs until we actually have history.
            if (items.isEmpty) return const SizedBox.shrink();

            return Container(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _TabChip(
                    icon: Icons.add,
                    label: 'New',
                    selected: false,
                    onTap: () => context
                        .read<ChatBloc>()
                        .add(const ChatNewConversationRequested()),
                  ),
                  const SizedBox(width: 8),
                  for (final c in items) ...[
                    _TabChip(
                      icon: c.id == activeId ? Icons.chat_bubble : Icons.chat_bubble_outline,
                      label: c.title,
                      selected: c.id == activeId,
                      onTap: () => context.read<ChatBloc>().add(
                            ChatConversationSelected(conversationId: c.id),
                          ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _TabChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).colorScheme.surface;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? primary.withOpacity(0.12) : surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? primary.withOpacity(0.5) : Colors.grey.withOpacity(0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? primary : onSurface.withOpacity(0.65)),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: selected ? primary : onSurface.withOpacity(0.8),
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListeningBanner extends StatelessWidget {
  final String text;
  final double? levelDb;

  const _ListeningBanner({
    super.key,
    required this.text,
    required this.levelDb,
  });

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final danger = Theme.of(context).colorScheme.error;

    final displayText = text.trim().isEmpty ? 'Listening…' : text.trim();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: danger.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          VoiceCaptureAnimation(active: true, levelDb: levelDb),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              displayText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: onSurface.withOpacity(0.9),
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Tap mic to stop',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: onSurface.withOpacity(0.55),
                ),
          ),
        ],
      ),
    );
  }
}

class _SendingBanner extends StatelessWidget {
  const _SendingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: primary.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation(primary),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sending…',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: onSurface.withOpacity(0.9),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallModeBanner extends StatelessWidget {
  final VoidCallback onEnd;

  const _CallModeBanner({required this.onEnd});

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final danger = Theme.of(context).colorScheme.error;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: danger.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_calling_3, color: danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Voice call mode is ON',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: onSurface.withOpacity(0.9),
                  ),
            ),
          ),
          TextButton(
            onPressed: onEnd,
            child: Text(
              'End',
              style: TextStyle(color: danger),
            ),
          ),
        ],
      ),
    );
  }
}
