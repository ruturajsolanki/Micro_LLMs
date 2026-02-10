import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/di/injection.dart';
import '../../data/datasources/conversation_storage.dart';
import '../blocs/chat/chat_bloc.dart';

class ChatHistoryPage extends StatelessWidget {
  const ChatHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = sl<ConversationStorage>();
    final conversationsBox = sl<Box<dynamic>>(instanceName: 'conversationsBox');

    return ValueListenableBuilder(
      valueListenable: conversationsBox.listenable(keys: const [
        ConversationStorage.conversationIndexKey,
        ConversationStorage.activeConversationIdKey,
      ]),
      builder: (context, _, __) {
        final items = storage.listConversations();

        Future<void> deleteConversation(ConversationSummary item) async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('Delete conversation?'),
                content: Text('This will permanently delete "${item.title}".'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete'),
                  ),
                ],
              );
            },
          );
          if (ok != true) return;
          await storage.deleteConversation(item.id);
        }

        Future<void> clearAll() async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('Clear all history?'),
                content: const Text(
                  'This will permanently delete all saved conversations.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Clear'),
                  ),
                ],
              );
            },
          );
          if (ok != true) return;
          await storage.clearAll();
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Chat history'),
            actions: [
              IconButton(
                tooltip: 'Clear all',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: items.isEmpty ? null : clearAll,
              ),
            ],
          ),
          body: items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No saved conversations yet.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Colors.grey,
                          ),
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return ListTile(
                      title: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${item.messageCount} messages • ${item.primaryLanguage} → ${item.targetLanguage}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => deleteConversation(item),
                      ),
                      onTap: () {
                        context.read<ChatBloc>().add(
                              ChatConversationSelected(conversationId: item.id),
                            );
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
        );
      },
    );
  }
}

