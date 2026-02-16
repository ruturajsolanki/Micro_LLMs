import 'package:flutter/material.dart';

import '../../core/di/injection.dart';
import '../../domain/services/system_prompt_manager.dart';
import '../theme/ui_tokens.dart';

/// Page that lists all system prompts and allows viewing, editing, and
/// resetting them to defaults.
///
/// Accessible from Settings → Tools → System Prompts.
class SystemPromptsPage extends StatefulWidget {
  const SystemPromptsPage({super.key});

  @override
  State<SystemPromptsPage> createState() => _SystemPromptsPageState();
}

class _SystemPromptsPageState extends State<SystemPromptsPage> {
  late SystemPromptManager _manager;
  late List<SystemPromptEntry> _entries;

  @override
  void initState() {
    super.initState();
    _manager = sl<SystemPromptManager>();
    _reload();
  }

  void _reload() {
    _manager.reload();
    setState(() {
      _entries = _manager.getAllEntries();
    });
  }

  IconData _iconForKey(SystemPromptKey key) {
    switch (key) {
      case SystemPromptKey.evaluation:
        return Icons.grading_rounded;
      case SystemPromptKey.globalSafety:
        return Icons.shield_rounded;
      case SystemPromptKey.injectionGuard:
        return Icons.security_rounded;
      case SystemPromptKey.cloudEvaluation:
        return Icons.cloud_rounded;
    }
  }

  String _subtitleForKey(SystemPromptKey key) {
    switch (key) {
      case SystemPromptKey.evaluation:
        return 'Scoring rubric for Clarity of Thought & Language Proficiency';
      case SystemPromptKey.globalSafety:
        return 'Screens transcripts for unsafe content before evaluation';
      case SystemPromptKey.injectionGuard:
        return 'Detects prompt injection attempts in transcripts';
      case SystemPromptKey.cloudEvaluation:
        return 'Cloud-optimized rubric for Groq/Gemini (V2)';
    }
  }

  Color _colorForKey(BuildContext context, SystemPromptKey key) {
    final cs = Theme.of(context).colorScheme;
    switch (key) {
      case SystemPromptKey.evaluation:
        return cs.primary;
      case SystemPromptKey.globalSafety:
        return Colors.orange;
      case SystemPromptKey.injectionGuard:
        return Colors.redAccent;
      case SystemPromptKey.cloudEvaluation:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('System Prompts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore_rounded),
            tooltip: 'Reset all to defaults',
            onPressed: () => _showResetAllDialog(context),
          ),
        ],
      ),
      body: ListView(
        padding: UiTokens.pagePadding,
        children: [
          // Header explanation
          Container(
            padding: const EdgeInsets.all(UiTokens.s16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(UiTokens.r16),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: cs.primary,
                  size: 20,
                ),
                const SizedBox(width: UiTokens.s12),
                Expanded(
                  child: Text(
                    'These prompts control how the AI evaluates your speech. '
                    'Edit them to adjust scoring behavior, safety rules, or output format.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: UiTokens.s20),

          // Prompt cards
          for (int i = 0; i < _entries.length; i++) ...[
            _PromptCard(
              entry: _entries[i],
              icon: _iconForKey(_entries[i].key),
              subtitle: _subtitleForKey(_entries[i].key),
              accentColor: _colorForKey(context, _entries[i].key),
              onTap: () => _openEditor(_entries[i]),
              onReset: () => _resetSingle(_entries[i].key),
            ),
            if (i < _entries.length - 1) const SizedBox(height: UiTokens.s12),
          ],

          const SizedBox(height: UiTokens.s32),
        ],
      ),
    );
  }

  void _openEditor(SystemPromptEntry entry) async {
    final edited = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _SystemPromptEditPage(
          manager: _manager,
          promptKey: entry.key,
        ),
      ),
    );

    if (edited == true) {
      _reload();
    }
  }

  void _resetSingle(SystemPromptKey key) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Prompt'),
        content: Text(
          'Reset "${_manager.getEntry(key).name}" to its built-in default? '
          'Your edits will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _manager.resetToDefault(key);
              _reload();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Prompt reset to default')),
                );
              }
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  void _showResetAllDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset All Prompts'),
        content: const Text(
          'Reset all system prompts to their built-in defaults? '
          'All your edits will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              for (final key in SystemPromptKey.values) {
                await _manager.resetToDefault(key);
              }
              _reload();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All prompts reset to defaults')),
                );
              }
            },
            child: const Text('Reset All'),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// PROMPT CARD
// ════════════════════════════════════════════════════════════════════════════════

class _PromptCard extends StatelessWidget {
  final SystemPromptEntry entry;
  final IconData icon;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;
  final VoidCallback onReset;

  const _PromptCard({
    required this.entry,
    required this.icon,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isCustomized = entry.version > 1;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(UiTokens.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(UiTokens.r10),
                    ),
                    child: Icon(icon, color: accentColor, size: 22),
                  ),
                  const SizedBox(width: UiTokens.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: cs.onSurface.withOpacity(0.4),
                  ),
                ],
              ),

              const SizedBox(height: UiTokens.s12),

              // Preview of prompt text (first 2 lines)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(UiTokens.s12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(UiTokens.r10),
                ),
                child: Text(
                  _truncatePrompt(entry.text, 120),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: cs.onSurface.withOpacity(0.7),
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              const SizedBox(height: UiTokens.s12),

              // Footer: version, modified date, reset button
              Row(
                children: [
                  if (isCustomized)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'CUSTOMIZED',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: accentColor,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    )
                  else
                    Text(
                      'Default',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurface.withOpacity(0.5),
                      ),
                    ),
                  const SizedBox(width: UiTokens.s8),
                  Text(
                    'v${entry.version}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.4),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${entry.text.split(' ').length} words',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.4),
                    ),
                  ),
                  if (isCustomized) ...[
                    const SizedBox(width: UiTokens.s8),
                    SizedBox(
                      height: 28,
                      child: TextButton.icon(
                        onPressed: onReset,
                        icon: const Icon(Icons.restore, size: 14),
                        label: const Text('Reset'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          textStyle: theme.textTheme.labelSmall,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _truncatePrompt(String text, int maxLen) {
    final trimmed = text.trim();
    if (trimmed.length <= maxLen) return trimmed;
    return '${trimmed.substring(0, maxLen)}…';
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// PROMPT EDITOR PAGE
// ════════════════════════════════════════════════════════════════════════════════

class _SystemPromptEditPage extends StatefulWidget {
  final SystemPromptManager manager;
  final SystemPromptKey promptKey;

  const _SystemPromptEditPage({
    required this.manager,
    required this.promptKey,
  });

  @override
  State<_SystemPromptEditPage> createState() => _SystemPromptEditPageState();
}

class _SystemPromptEditPageState extends State<_SystemPromptEditPage> {
  late TextEditingController _controller;
  late String _originalText;
  bool _saving = false;

  SystemPromptEntry get _entry => widget.manager.getEntry(widget.promptKey);

  @override
  void initState() {
    super.initState();
    _originalText = _entry.text;
    _controller = TextEditingController(text: _originalText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _hasChanges => _controller.text != _originalText;

  int get _wordCount {
    final text = _controller.text.trim();
    if (text.isEmpty) return 0;
    return text.split(RegExp(r'\s+')).length;
  }

  Future<void> _save() async {
    if (!_hasChanges) return;

    setState(() => _saving = true);

    await widget.manager.updatePrompt(widget.promptKey, _controller.text);

    setState(() {
      _saving = false;
      _originalText = _controller.text;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_entry.name} saved (v${_entry.version})'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _resetToDefault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to Default'),
        content: Text(
          'Discard all changes to "${_entry.name}" and restore '
          'the built-in default prompt?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await widget.manager.resetToDefault(widget.promptKey);
    final defaultText = widget.manager.getPrompt(widget.promptKey);

    setState(() {
      _controller.text = defaultText;
      _originalText = defaultText;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prompt reset to default'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) {
      Navigator.pop(context, _originalText != _entry.text);
      return false;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text('You have unsaved changes. What would you like to do?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Keep Editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (action == 'save') {
      await _save();
      if (mounted) Navigator.pop(context, true);
    } else if (action == 'discard') {
      if (mounted) Navigator.pop(context, false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onWillPop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_entry.name),
          actions: [
            TextButton.icon(
              onPressed: _resetToDefault,
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('Default'),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            // Info bar
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: UiTokens.s16,
                vertical: UiTokens.s8,
              ),
              color: cs.surfaceContainerHighest.withOpacity(0.3),
              child: Row(
                children: [
                  Text(
                    'v${_entry.version}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(width: UiTokens.s16),
                  Text(
                    '$_wordCount words',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.5),
                    ),
                  ),
                  const Spacer(),
                  if (_hasChanges)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'UNSAVED',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Editor
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(UiTokens.s12),
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.5,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter the system prompt...',
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withOpacity(0.2),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(UiTokens.r12),
                      borderSide: BorderSide(
                        color: cs.outline.withOpacity(0.3),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(UiTokens.r12),
                      borderSide: BorderSide(
                        color: cs.outline.withOpacity(0.2),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(UiTokens.r12),
                      borderSide: BorderSide(color: cs.primary),
                    ),
                    contentPadding: const EdgeInsets.all(UiTokens.s16),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
          ],
        ),

        // Save FAB
        floatingActionButton: _hasChanges
            ? FloatingActionButton.extended(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_saving ? 'Saving…' : 'Save Changes'),
              )
            : null,
      ),
    );
  }
}
