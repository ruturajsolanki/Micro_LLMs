import 'package:hive/hive.dart';

import '../../domain/entities/benchmark_prompt.dart';
import '../../core/utils/logger.dart';

/// Persistence layer for benchmark prompt presets.
///
/// Stores user-created and modified prompts in Hive. Built-in presets
/// are always available and cannot be deleted.
class BenchmarkStorage {
  static const String _promptsKey = 'benchmark_prompts';
  static const String _selectedPromptIdKey = 'benchmark_selected_prompt_id';

  final Box<dynamic> _settingsBox;

  BenchmarkStorage({required Box<dynamic> settingsBox})
      : _settingsBox = settingsBox;

  /// Load all prompt presets (built-in + user-created).
  ///
  /// Built-in prompts are always included. User prompts stored in Hive
  /// are merged on top.
  List<BenchmarkPrompt> loadPrompts() {
    try {
      final stored = _settingsBox.get(_promptsKey) as List<dynamic>?;
      if (stored == null || stored.isEmpty) {
        return BenchmarkPrompt.defaults;
      }

      final prompts = <BenchmarkPrompt>[];
      for (final item in stored) {
        if (item is Map) {
          prompts.add(_promptFromMap(Map<String, dynamic>.from(item)));
        }
      }

      // Merge: keep built-in defaults, append user-created
      final builtInIds = BenchmarkPrompt.defaults.map((p) => p.id).toSet();
      final userPrompts =
          prompts.where((p) => !builtInIds.contains(p.id)).toList();

      return [...BenchmarkPrompt.defaults, ...userPrompts];
    } catch (e) {
      AppLogger.e('Failed to load benchmark prompts: $e');
      return BenchmarkPrompt.defaults;
    }
  }

  /// Save a prompt preset.
  Future<void> savePrompt(BenchmarkPrompt prompt) async {
    final prompts = loadPrompts();
    final index = prompts.indexWhere((p) => p.id == prompt.id);

    if (index >= 0) {
      prompts[index] = prompt;
    } else {
      prompts.add(prompt);
    }

    await _settingsBox.put(
        _promptsKey, prompts.map(_promptToMap).toList());
  }

  /// Delete a user-created prompt preset. Built-in prompts are preserved.
  Future<void> deletePrompt(String promptId) async {
    final prompts = loadPrompts();
    prompts.removeWhere((p) => p.id == promptId && !p.isBuiltIn);
    await _settingsBox.put(
        _promptsKey, prompts.map(_promptToMap).toList());
  }

  /// Get the ID of the currently selected prompt.
  String getSelectedPromptId() {
    return _settingsBox.get(_selectedPromptIdKey,
        defaultValue: 'general') as String;
  }

  /// Set the currently selected prompt ID.
  Future<void> setSelectedPromptId(String promptId) async {
    await _settingsBox.put(_selectedPromptIdKey, promptId);
  }

  Map<String, dynamic> _promptToMap(BenchmarkPrompt prompt) {
    return {
      'id': prompt.id,
      'name': prompt.name,
      'instruction': prompt.instruction,
      'mode': prompt.mode.index,
      'isBuiltIn': prompt.isBuiltIn,
      'version': prompt.version,
      'createdAt': prompt.createdAt.toIso8601String(),
    };
  }

  BenchmarkPrompt _promptFromMap(Map<String, dynamic> map) {
    return BenchmarkPrompt(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Untitled',
      instruction: map['instruction'] as String? ?? '',
      mode: BenchmarkMode.values[map['mode'] as int? ?? 0],
      isBuiltIn: map['isBuiltIn'] as bool? ?? false,
      version: map['version'] as int? ?? 1,
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
