import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../domain/entities/message.dart';
import '../theme/app_theme.dart';
import '../theme/ui_tokens.dart';

/// Chat message bubble widget.
/// 
/// Displays a single message with appropriate styling based on the sender.
/// Supports:
/// - User and assistant message styling
/// - Markdown rendering for assistant messages
/// - Streaming indicator
/// - Translation display
/// - Action buttons (copy, translate, speak)
class ChatMessageBubble extends StatefulWidget {
  final Message message;
  final bool animateIn;
  final VoidCallback? onTranslate;
  final VoidCallback? onSpeak;
  
  const ChatMessageBubble({
    super.key,
    required this.message,
    this.animateIn = false,
    this.onTranslate,
    this.onSpeak,
  });
  
  @override
  State<ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends State<ChatMessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  bool get _isUser => widget.message.role == MessageRole.user;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: UiTokens.durMed,
    );

    final curved = CurvedAnimation(
      parent: _controller,
      curve: UiTokens.curveStandard,
      reverseCurve: Curves.easeInCubic,
    );

    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(curved);

    if (widget.animateIn) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant ChatMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If a bubble starts streaming into existence, animate once.
    if (!oldWidget.animateIn && widget.animateIn && _controller.value == 0.0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final message = widget.message;
    final genStats = (!_isUser && !message.isStreaming) ? _readGenStats(message) : null;
    
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Align(
          alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: UiTokens.s4),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82,
            ),
            child: Column(
              crossAxisAlignment:
                  _isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // Main bubble
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: UiTokens.s16,
                    vertical: UiTokens.s12,
                  ),
                  decoration: BoxDecoration(
                    color: _isUser
                        ? (isDark
                            ? AppTheme.userBubbleDark
                            : AppTheme.userBubbleLight)
                        : (isDark
                            ? AppTheme.assistantBubbleDark
                            : AppTheme.assistantBubbleLight),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(UiTokens.r20),
                      topRight: const Radius.circular(UiTokens.r20),
                      bottomLeft:
                          Radius.circular(_isUser ? UiTokens.r20 : UiTokens.s4),
                      bottomRight:
                          Radius.circular(_isUser ? UiTokens.s4 : UiTokens.r20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                        color: Colors.black.withOpacity(isDark ? 0.18 : 0.06),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Message content
                      if (_isUser)
                        SelectableText(
                          message.content,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        )
                      else
                        _buildAssistantContent(context, message),

                      // Streaming indicator
                      AnimatedSize(
                        duration: UiTokens.durMed,
                        curve: UiTokens.curveStandard,
                        child: message.isStreaming
                            ? Padding(
                                padding: const EdgeInsets.only(top: UiTokens.s8),
                                child: _buildStreamingIndicator(),
                              )
                            : const SizedBox.shrink(),
                      ),

                      // Generation stats (as a subtle chip)
                      if (genStats != null) ...[
                        const SizedBox(height: UiTokens.s8),
                        _GenStatsChip(text: genStats),
                      ],
                    ],
                  ),
                ),

                // Translation (if available)
                if (message.translation != null) ...[
                  const SizedBox(height: UiTokens.s8),
                  _buildTranslation(context, isDark, message),
                ],

                // Action buttons
                const SizedBox(height: UiTokens.s8),
                _buildActionButtons(context, message),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildAssistantContent(BuildContext context, Message message) {
    if (message.content.isEmpty && message.isStreaming) {
      return const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(Colors.grey),
        ),
      );
    }
    
    // Use Markdown for assistant messages
    return MarkdownBody(
      data: message.content,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          fontSize: 15,
          height: 1.4,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          backgroundColor: Colors.grey.shade800.withOpacity(0.1),
        ),
        codeblockDecoration: BoxDecoration(
          color: Colors.grey.shade900.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
  
  Widget _buildStreamingIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDot(0),
        const SizedBox(width: 4),
        _buildDot(1),
        const SizedBox(width: 4),
        _buildDot(2),
      ],
    );
  }
  
  Widget _buildDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 100)),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildTranslation(BuildContext context, bool isDark, Message message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.translate,
                size: 14,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 4),
              Text(
                'Translation (${message.translationLanguage?.toUpperCase() ?? ""})',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            message.translation!,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildActionButtons(BuildContext context, Message message) {
    if (message.isStreaming) return const SizedBox.shrink();
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Copy button
        _ActionButton(
          icon: Icons.copy,
          tooltip: 'Copy',
          onPressed: () {
            HapticFeedback.selectionClick();
            Clipboard.setData(ClipboardData(text: message.content));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copied to clipboard'),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),
        
        // Translate button
        if (widget.onTranslate != null && message.translation == null)
          _ActionButton(
            icon: Icons.translate,
            tooltip: 'Translate',
            onPressed: widget.onTranslate!,
          ),
        
        // Speak button
        if (widget.onSpeak != null)
          _ActionButton(
            icon: Icons.volume_up,
            tooltip: 'Speak',
            onPressed: widget.onSpeak!,
          ),
      ],
    );
  }

  String? _readGenStats(Message message) {
    final meta = message.metadata;
    if (meta == null) return null;
    final durationMs = (meta['genDurationMs'] as num?)?.toInt();
    final tokens = (meta['genTokens'] as num?)?.toInt();
    final tps = (meta['genTokensPerSecond'] as num?)?.toDouble();
    if (durationMs == null && tokens == null) return null;

    final parts = <String>[];
    if (durationMs != null) {
      parts.add('${(durationMs / 1000).toStringAsFixed(2)}s');
    }
    if (tokens != null) {
      parts.add('$tokens tok');
    }
    if (tps != null) {
      parts.add('${tps.toStringAsFixed(1)} t/s');
    }
    return parts.join(' • ');
  }
}

class _GenStatsChip extends StatelessWidget {
  final String text;

  const _GenStatsChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: onSurface.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: onSurface.withOpacity(0.08)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: onSurface.withOpacity(0.60),
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  
  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(right: UiTokens.s8),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onPressed();
          },
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: onSurface.withOpacity(0.04),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: onSurface.withOpacity(0.06)),
            ),
            child: Icon(
              icon,
              size: 16,
              color: onSurface.withOpacity(0.62),
            ),
          ),
        ),
      ),
    );
  }
}
