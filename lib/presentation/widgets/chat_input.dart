import 'package:flutter/material.dart';

import '../theme/ui_tokens.dart';

/// Chat input widget with text field and send button.
/// 
/// Supports:
/// - Text input with multi-line support
/// - Send button with disabled state during generation
/// - Cancel button during generation
/// - Voice input button slot
class ChatInput extends StatefulWidget {
  final TextEditingController controller;
  final bool enabled;
  final bool isGenerating;
  final void Function(String) onSend;
  final VoidCallback? onCancel;
  final Widget? voiceButton;
  
  const ChatInput({
    super.key,
    required this.controller,
    required this.enabled,
    required this.isGenerating,
    required this.onSend,
    this.onCancel,
    this.voiceButton,
  });
  
  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  bool _hasText = false;
  
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }
  
  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }
  
  void _onTextChanged() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }
  
  void _onSubmit() {
    if (!_hasText || !widget.enabled) return;
    widget.onSend(widget.controller.text);
  }
  
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dockColor = isDark ? cs.surface : Theme.of(context).scaffoldBackgroundColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: UiTokens.s12, vertical: UiTokens.s12),
      decoration: BoxDecoration(
        color: dockColor,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerTheme.color ?? Colors.grey.shade300,
          ),
        ),
      ),
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(UiTokens.s8, UiTokens.s8, UiTokens.s8, UiTokens.s8),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: cs.onSurface.withOpacity(isDark ? 0.10 : 0.08)),
            boxShadow: [
              BoxShadow(
                blurRadius: 18,
                offset: const Offset(0, 10),
                color: Colors.black.withOpacity(isDark ? 0.22 : 0.08),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Voice input button
              if (widget.voiceButton != null && !widget.isGenerating) ...[
                widget.voiceButton!,
                const SizedBox(width: UiTokens.s4),
              ],

              // Text field
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  enabled: widget.enabled,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    hintText: widget.isGenerating
                        ? 'Generating response…'
                        : 'Message',
                    hintStyle: TextStyle(
                      color: cs.onSurface.withOpacity(0.45),
                      fontWeight: FontWeight.w500,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: UiTokens.s12,
                      vertical: UiTokens.s12,
                    ),
                  ),
                  onSubmitted: (_) => _onSubmit(),
                ),
              ),

              const SizedBox(width: UiTokens.s8),

              // Send or Cancel button
              if (widget.isGenerating)
                _buildCancelButton(context)
              else
                _buildSendButton(context),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildSendButton(BuildContext context) {
    final canSend = _hasText && widget.enabled;
    
    final cs = Theme.of(context).colorScheme;

    return AnimatedScale(
      duration: UiTokens.durFast,
      curve: UiTokens.curveStandard,
      scale: canSend ? 1.0 : 0.96,
      child: AnimatedOpacity(
        duration: UiTokens.durFast,
        opacity: widget.enabled ? 1.0 : 0.6,
        child: IconButton(
          onPressed: canSend ? _onSubmit : null,
          icon: const Icon(Icons.send_rounded),
          style: IconButton.styleFrom(
            backgroundColor: canSend ? cs.primary : cs.onSurface.withOpacity(0.10),
            foregroundColor: canSend ? Colors.white : cs.onSurface.withOpacity(0.45),
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildCancelButton(BuildContext context) {
    return IconButton(
      onPressed: widget.onCancel,
      icon: const Icon(Icons.stop_rounded),
      style: IconButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.error,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }
}
