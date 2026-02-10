import 'package:flutter/services.dart';

import '../../core/utils/logger.dart';
import '../../domain/entities/message.dart';

/// Syncs the currently selected conversation history to the native (Kotlin/JNI)
/// incremental prompt buffer.
///
/// Why:
/// - Kotlin side keeps its own `conversationBuffer` for speed.
/// - When user switches chats (tabs/history), we must rehydrate that buffer,
///   otherwise the model will answer with the *wrong* context.
class LlmConversationSyncDataSource with Loggable {
  static const MethodChannel _channel = MethodChannel('com.microllm.app/llama');

  Future<void> resetConversation() async {
    try {
      await _channel.invokeMethod('resetConversation');
    } catch (e) {
      logger.w('resetConversation failed: $e');
    }
  }

  Future<void> setConversation({
    required List<Message> messages,
    required String assistantLanguage,
  }) async {
    try {
      final payload = {
        'assistantLanguage': assistantLanguage,
        'messages': messages
            .where((m) => m.role == MessageRole.user || m.role == MessageRole.assistant)
            .map((m) => {
                  'role': m.role.name,
                  'content': m.content,
                })
            .toList(),
      };
      await _channel.invokeMethod('setConversation', payload);
    } catch (e) {
      logger.w('setConversation failed: $e');
    }
  }
}

