import 'package:hive/hive.dart';

import '../../core/utils/logger.dart';
import '../../domain/entities/v2_session_record.dart';

/// Persists V2 evaluation session records to Hive.
///
/// Each record is stored as a Map keyed by its `id`.
class V2SessionStorage {
  final Box<dynamic> _box;

  static const String _listKey = 'v2_sessions';

  V2SessionStorage({required Box<dynamic> settingsBox}) : _box = settingsBox;

  /// Save a session record.
  Future<void> save(V2SessionRecord record) async {
    try {
      final sessions = _loadRawList();
      sessions.insert(0, record.toMap());
      await _box.put(_listKey, sessions);
      AppLogger.i('V2SessionStorage: saved session ${record.id}');
    } catch (e) {
      AppLogger.e('V2SessionStorage: save failed: $e');
    }
  }

  /// Get all session records, newest first.
  List<V2SessionRecord> getAll() {
    try {
      final sessions = _loadRawList();
      return sessions
          .map((m) => V2SessionRecord.fromMap(m as Map<dynamic, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.e('V2SessionStorage: getAll failed: $e');
      return [];
    }
  }

  /// Get a single session by ID.
  V2SessionRecord? getById(String id) {
    try {
      final sessions = _loadRawList();
      for (final m in sessions) {
        final map = m as Map<dynamic, dynamic>;
        if (map['id'] == id) {
          return V2SessionRecord.fromMap(map);
        }
      }
      return null;
    } catch (e) {
      AppLogger.e('V2SessionStorage: getById failed: $e');
      return null;
    }
  }

  /// Delete a session by ID.
  Future<void> delete(String id) async {
    try {
      final sessions = _loadRawList();
      sessions.removeWhere(
          (m) => (m as Map<dynamic, dynamic>)['id'] == id);
      await _box.put(_listKey, sessions);
    } catch (e) {
      AppLogger.e('V2SessionStorage: delete failed: $e');
    }
  }

  /// Delete all sessions.
  Future<void> clearAll() async {
    await _box.delete(_listKey);
  }

  /// Total number of saved sessions.
  int get count => _loadRawList().length;

  /// Average total score across all sessions.
  double get averageTotalScore {
    final records = getAll();
    if (records.isEmpty) return 0;
    final sum = records.fold<double>(
        0, (acc, r) => acc + r.totalScore);
    return sum / records.length;
  }

  List<dynamic> _loadRawList() {
    final raw = _box.get(_listKey);
    if (raw == null) return [];
    if (raw is List) return List<dynamic>.from(raw);
    return [];
  }
}
