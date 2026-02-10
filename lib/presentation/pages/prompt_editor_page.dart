import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/di/injection.dart';
import '../../domain/entities/benchmark_prompt.dart';
import '../../data/datasources/benchmark_storage.dart';
import '../theme/ui_tokens.dart';

/// Page for viewing, editing, creating, and managing benchmark prompt presets.
///
/// Prompt presets are centralized, versioned, and user-editable.
/// Built-in presets cannot be deleted but can serve as templates.
class PromptEditorPage extends StatefulWidget {
  const PromptEditorPage({super.key});

  @override
  State<PromptEditorPage> createState() => _PromptEditorPageState();
}

class _PromptEditorPageState extends State<PromptEditorPage> {
  final _storage = sl<BenchmarkStorage>();
  late List<BenchmarkPrompt> _prompts;
  late String _selectedId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _prompts = _storage.loadPrompts();
    _selectedId = _storage.getSelectedPromptId();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prompt Presets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New prompt',
            onPressed: _createNew,
          ),
        ],
      ),
      body: ListView.separated(
        padding: UiTokens.pagePadding,
        itemCount: _prompts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final prompt = _prompts[index];
          final isSelected = prompt.id == _selectedId;

          return _PromptCard(
            prompt: prompt,
            isSelected: isSelected,
            onTap: () => _selectPrompt(prompt.id),
            onEdit: () => _editPrompt(prompt),
            onDelete: prompt.isBuiltIn ? null : () => _deletePrompt(prompt.id),
          );
        },
      ),
    );
  }

  void _selectPrompt(String id) {
    _storage.setSelectedPromptId(id);
    setState(() => _selectedId = id);
  }

  void _editPrompt(BenchmarkPrompt prompt) async {
    final edited = await Navigator.push<BenchmarkPrompt>(
      context,
      MaterialPageRoute(
        builder: (_) => _PromptFormPage(prompt: prompt),
      ),
    );

    if (edited != null) {
      await _storage.savePrompt(edited);
      setState(_reload);
    }
  }

  void _createNew() async {
    final fresh = BenchmarkPrompt(
      id: const Uuid().v4(),
      name: 'Custom Prompt',
      instruction: '',
      mode: BenchmarkMode.generalSummary,
      isBuiltIn: false,
      createdAt: DateTime.now(),
    );

    final created = await Navigator.push<BenchmarkPrompt>(
      context,
      MaterialPageRoute(
        builder: (_) => _PromptFormPage(prompt: fresh, isNew: true),
      ),
    );

    if (created != null) {
      await _storage.savePrompt(created);
      setState(_reload);
    }
  }

  void _deletePrompt(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Prompt'),
        content: const Text('Are you sure you want to delete this prompt?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storage.deletePrompt(id);
      if (_selectedId == id) {
        _selectPrompt('general');
      }
      setState(_reload);
    }
  }
}

/// Card displaying a single prompt preset.
class _PromptCard extends StatelessWidget {
  final BenchmarkPrompt prompt;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _PromptCard({
    required this.prompt,
    required this.isSelected,
    required this.onTap,
    required this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return AnimatedContainer(
      duration: UiTokens.durMed,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(UiTokens.r16),
        border: Border.all(
          color: isSelected ? primary.withOpacity(0.5) : theme.colorScheme.onSurface.withOpacity(0.08),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(UiTokens.r16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(UiTokens.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isSelected)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(Icons.check_circle,
                          color: primary, size: 18),
                    ),
                  Expanded(
                    child: Text(
                      prompt.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: isSelected ? primary : null,
                      ),
                    ),
                  ),
                  if (prompt.isBuiltIn)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Built-in',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.45),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: onEdit,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Edit',
                  ),
                  if (onDelete != null)
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 18, color: theme.colorScheme.error),
                      onPressed: onDelete,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Delete',
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                prompt.mode.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                prompt.instruction,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.55),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'v${prompt.version}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.3),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Form for editing or creating a prompt preset.
class _PromptFormPage extends StatefulWidget {
  final BenchmarkPrompt prompt;
  final bool isNew;

  const _PromptFormPage({required this.prompt, this.isNew = false});

  @override
  State<_PromptFormPage> createState() => _PromptFormPageState();
}

class _PromptFormPageState extends State<_PromptFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _instructionController;
  late BenchmarkMode _mode;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.prompt.name);
    _instructionController =
        TextEditingController(text: widget.prompt.instruction);
    _mode = widget.prompt.mode;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _instructionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New Prompt' : 'Edit Prompt'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: UiTokens.pagePadding,
          children: [
            // Name
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Meeting Notes Summary',
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: UiTokens.s16),

            // Mode
            Text('Benchmark Mode', style: theme.textTheme.labelLarge),
            const SizedBox(height: UiTokens.s8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: BenchmarkMode.values.map((mode) {
                return ChoiceChip(
                  label: Text(mode.label),
                  selected: _mode == mode,
                  onSelected: (_) => setState(() => _mode = mode),
                );
              }).toList(),
            ),
            const SizedBox(height: UiTokens.s16),

            // Instruction
            TextFormField(
              controller: _instructionController,
              decoration: const InputDecoration(
                labelText: 'Summarization Instruction',
                hintText: 'Enter the system prompt instruction…',
                alignLabelWithHint: true,
              ),
              maxLines: 8,
              minLines: 4,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Instruction is required' : null,
            ),
            const SizedBox(height: UiTokens.s24),

            // Tips
            Container(
              padding: const EdgeInsets.all(UiTokens.s16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(UiTokens.r12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tips',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(height: 6),
                  Text(
                    '• Be specific about what you want the model to produce.\n'
                    '• Mention the desired format (bullet points, paragraphs, etc.).\n'
                    '• Include tone or audience guidance if relevant.\n'
                    '• Keep instructions concise — models work best with clear direction.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final updated = widget.prompt.copyWith(
      name: _nameController.text.trim(),
      instruction: _instructionController.text.trim(),
      mode: _mode,
      version: widget.prompt.version + (widget.isNew ? 0 : 1),
    );

    Navigator.pop(context, updated);
  }
}
