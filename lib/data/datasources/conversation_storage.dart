import 'package:hive/hive.dart';

import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';

/// Persists the active conversation to local storage (Hive).
///
/// Why:
/// - Chat retention must survive app restarts/crashes
/// - We keep it offline-first and avoid network dependencies
///
/// Storage format:
/// - `activeConversationId`: String
/// - `conversationIndex`: List<Map> (most-recent first)
/// - `conversation:<id>`: Map (full serialized conversation)
///
/// Migration:
/// - Older builds stored a single `activeConversation` map; we migrate it into
///   the new format on first load.
class ConversationStorage {
  static const String _activeConversationKeyLegacy = 'activeConversation';
  static const String activeConversationIdKey = 'activeConversationId';
  static const String conversationIndexKey = 'conversationIndex';
  static const String _conversationPrefix = 'conversation:';
  static const int maxConversationsToKeep = 25;

  final Box<dynamic> _box;

  ConversationStorage({required Box<dynamic> conversationsBox})
      : _box = conversationsBox;

  Conversation? loadActiveConversation() {
    // New format
    final activeId = _box.get(activeConversationIdKey);
    if (activeId is String && activeId.isNotEmpty) {
      final raw = _box.get('$_conversationPrefix$activeId');
      if (raw is Map) {
        return _sanitizeConversation(
          _conversationFromMap(Map<String, dynamic>.from(raw)),
        );
      }
    }

    // Legacy format migration
    final legacy = _box.get(_activeConversationKeyLegacy);
    if (legacy is Map) {
      final conv = _sanitizeConversation(
        _conversationFromMap(Map<String, dynamic>.from(legacy)),
      );
      // Best-effort migrate
      try {
        saveActiveConversation(conv);
        _box.delete(_activeConversationKeyLegacy);
      } catch (_) {
        // Ignore migration errors
      }
      return conv;
    }

    return null;
  }

  Future<void> saveActiveConversation(Conversation conversation) async {
    final conv = _sanitizeConversation(conversation);
    final convKey = '$_conversationPrefix${conv.id}';
    await _box.put(convKey, _conversationToMap(conv));
    await _box.put(activeConversationIdKey, conv.id);
    await _upsertIndexEntry(conv);
  }

  Future<void> setActiveConversationId(String conversationId) async {
    await _box.put(activeConversationIdKey, conversationId);
  }

  List<ConversationSummary> listConversations() {
    final raw = _box.get(conversationIndexKey);
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => ConversationSummary.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  Conversation? loadConversationById(String id) {
    final raw = _box.get('$_conversationPrefix$id');
    if (raw is! Map) return null;
    return _sanitizeConversation(
      _conversationFromMap(Map<String, dynamic>.from(raw)),
    );
  }

  Future<void> deleteConversation(String id) async {
    await _box.delete('$_conversationPrefix$id');

    final raw = _box.get(conversationIndexKey);
    if (raw is List) {
      final list = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      list.removeWhere((e) => (e['id'] as String?) == id);
      await _box.put(conversationIndexKey, list);
    }

    final activeId = _box.get(activeConversationIdKey);
    if (activeId == id) {
      await _box.delete(activeConversationIdKey);
    }
  }

  Future<void> clearAll() async {
    final summaries = listConversations();
    for (final s in summaries) {
      await _box.delete('$_conversationPrefix${s.id}');
    }
    await _box.delete(conversationIndexKey);
    await _box.delete(activeConversationIdKey);
  }

  Future<void> _upsertIndexEntry(Conversation c) async {
    final raw = _box.get(conversationIndexKey);
    final list = (raw is List)
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];

    // Remove existing
    list.removeWhere((e) => (e['id'] as String?) == c.id);
    // Add to front
    list.insert(
      0,
      ConversationSummary(
        id: c.id,
        title: c.title.isNotEmpty ? c.title : 'Conversation',
        updatedAt: c.updatedAt,
        messageCount: c.messages.length,
        primaryLanguage: c.primaryLanguage,
        targetLanguage: c.targetLanguage,
      ).toMap(),
    );

    // Cap size
    if (list.length > maxConversationsToKeep) {
      final overflow = list.sublist(maxConversationsToKeep);
      for (final e in overflow) {
        final id = e['id'] as String?;
        if (id != null) {
          await _box.delete('$_conversationPrefix$id');
        }
      }
      list.removeRange(maxConversationsToKeep, list.length);
    }

    await _box.put(conversationIndexKey, list);
  }
}

class ConversationSummary {
  final String id;
  final String title;
  final DateTime updatedAt;
  final int messageCount;
  final String primaryLanguage;
  final String targetLanguage;

  const ConversationSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messageCount,
    required this.primaryLanguage,
    required this.targetLanguage,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'messageCount': messageCount,
        'primaryLanguage': primaryLanguage,
        'targetLanguage': targetLanguage,
      };

  factory ConversationSummary.fromMap(Map<String, dynamic> map) {
    return ConversationSummary(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? 'Conversation',
      updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      messageCount: (map['messageCount'] as num?)?.toInt() ?? 0,
      primaryLanguage: map['primaryLanguage'] as String? ?? 'en',
      targetLanguage: map['targetLanguage'] as String? ?? 'es',
    );
  }
}

Map<String, dynamic> _conversationToMap(Conversation c) {
  return {
    'id': c.id,
    'title': c.title,
    'createdAt': c.createdAt.toIso8601String(),
    'updatedAt': c.updatedAt.toIso8601String(),
    'primaryLanguage': c.primaryLanguage,
    'targetLanguage': c.targetLanguage,
    'totalTokenCount': c.totalTokenCount,
    'isActive': c.isActive,
    'messages': c.messages.map(_messageToMap).toList(),
  };
}

Conversation _conversationFromMap(Map<String, dynamic> map) {
  final messagesRaw = map['messages'];
  final messages = (messagesRaw is List)
      ? messagesRaw
          .whereType<Map>()
          .map((m) => _messageFromMap(Map<String, dynamic>.from(m)))
          .toList()
      : <Message>[];

  return Conversation(
    id: map['id'] as String? ?? '',
    title: map['title'] as String? ?? 'Conversation',
    messages: messages,
    createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
        DateTime.now(),
    updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ??
        DateTime.now(),
    primaryLanguage: map['primaryLanguage'] as String? ?? 'en',
    targetLanguage: map['targetLanguage'] as String? ?? 'es',
    totalTokenCount: (map['totalTokenCount'] as num?)?.toInt() ?? 0,
    isActive: map['isActive'] as bool? ?? true,
  );
}

Conversation _sanitizeConversation(Conversation c) {
  // If we crash mid-generation, the stored conversation can contain a
  // streaming assistant bubble with empty content. On next start, we must
  // avoid showing a "stuck streaming" UI.
  final messages = <Message>[];
  for (final m in c.messages) {
    if (m.role == MessageRole.assistant && m.isStreaming && m.content.trim().isEmpty) {
      // Drop empty streaming placeholder
      continue;
    }
    if (m.isStreaming) {
      messages.add(m.copyWith(isStreaming: false));
    } else {
      messages.add(m);
    }
  }

  final safeTitle = (c.title.trim().isEmpty) ? c.generateTitle() : c.title;
  return c.copyWith(
    title: safeTitle,
    messages: messages,
    isActive: true,
  );
}

Map<String, dynamic> _messageToMap(Message m) {
  return {
    'id': m.id,
    'content': m.content,
    'role': m.role.name,
    'timestamp': m.timestamp.toIso8601String(),
    'language': m.language,
    'translation': m.translation,
    'translationLanguage': m.translationLanguage,
    'tokenCount': m.tokenCount,
    'isStreaming': m.isStreaming,
    'metadata': m.metadata,
  };
}

Message _messageFromMap(Map<String, dynamic> map) {
  final roleStr = map['role'] as String? ?? 'user';
  final role = MessageRole.values.firstWhere(
    (r) => r.name == roleStr,
    orElse: () => MessageRole.user,
  );

  final metadataRaw = map['metadata'];
  final metadata = metadataRaw is Map ? Map<String, dynamic>.from(metadataRaw) : null;

  return Message(
    id: map['id'] as String? ?? '',
    content: map['content'] as String? ?? '',
    role: role,
    timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ??
        DateTime.now(),
    language: map['language'] as String?,
    translation: map['translation'] as String?,
    translationLanguage: map['translationLanguage'] as String?,
    tokenCount: (map['tokenCount'] as num?)?.toInt(),
    isStreaming: map['isStreaming'] as bool? ?? false,
    metadata: metadata,
  );
}

