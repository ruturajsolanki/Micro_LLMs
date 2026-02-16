import 'package:hive/hive.dart';

import '../../domain/services/system_prompt_manager.dart';
import '../../core/utils/logger.dart';

/// Hive-backed implementation of [SystemPromptStorage].
///
/// Stores user-edited system prompts as JSON maps in the settings Hive box.
/// Each prompt is stored under a key derived from its [SystemPromptKey].
class SystemPromptStorageImpl implements SystemPromptStorage {
  static const String _prefix = 'sys_prompt_';

  final Box<dynamic> _settingsBox;

  SystemPromptStorageImpl({required Box<dynamic> settingsBox})
      : _settingsBox = settingsBox;

  String _storageKey(SystemPromptKey key) => '$_prefix${key.name}';

  @override
  SystemPromptEntry? loadPromptEntry(SystemPromptKey key) {
    try {
      final raw = _settingsBox.get(_storageKey(key));
      if (raw == null) return null;
      if (raw is! Map) return null;

      final map = Map<String, dynamic>.from(raw);
      return SystemPromptEntry(
        key: key,
        name: map['name'] as String? ?? key.name,
        text: map['text'] as String? ?? '',
        version: map['version'] as int? ?? 1,
        updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
    } catch (e) {
      AppLogger.e('Failed to load system prompt ${key.name}: $e');
      return null;
    }
  }

  @override
  Future<void> savePromptEntry(SystemPromptEntry entry) async {
    try {
      await _settingsBox.put(_storageKey(entry.key), {
        'name': entry.name,
        'text': entry.text,
        'version': entry.version,
        'updatedAt': entry.updatedAt.toIso8601String(),
      });
    } catch (e) {
      AppLogger.e('Failed to save system prompt ${entry.key.name}: $e');
    }
  }

  @override
  Future<void> deletePromptEntry(SystemPromptKey key) async {
    try {
      await _settingsBox.delete(_storageKey(key));
    } catch (e) {
      AppLogger.e('Failed to delete system prompt ${key.name}: $e');
    }
  }
}
