import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart';

import '../../../domain/entities/message.dart';
import '../../../domain/entities/conversation.dart';
import '../../../domain/repositories/llm_repository.dart';
import '../../../domain/usecases/generate_response_usecase.dart';
import '../../../domain/usecases/translate_text_usecase.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/logger.dart';
import '../../../data/datasources/conversation_storage.dart';
import '../../../data/datasources/llm_conversation_sync_datasource.dart';

part 'chat_event.dart';
part 'chat_state.dart';

/// BLoC for managing chat conversation state.
/// 
/// Handles:
/// - Sending messages to the LLM
/// - Receiving streaming responses
/// - Translation requests
/// - Conversation history management
class ChatBloc extends Bloc<ChatEvent, ChatState> with Loggable {
  final GenerateResponseUseCase _generateResponseUseCase;
  final TranslateTextUseCase _translateTextUseCase;
  final _uuid = const Uuid();
  final Box<dynamic> _settingsBox;
  final ConversationStorage _conversationStorage;
  final LlmConversationSyncDataSource _llmConversationSync;
  
  StreamSubscription<InferenceEvent>? _responseSubscription;
  
  ChatBloc({
    required GenerateResponseUseCase generateResponseUseCase,
    required TranslateTextUseCase translateTextUseCase,
    required Box<dynamic> settingsBox,
    required ConversationStorage conversationStorage,
    required LlmConversationSyncDataSource llmConversationSync,
  })  : _generateResponseUseCase = generateResponseUseCase,
        _translateTextUseCase = translateTextUseCase,
        _settingsBox = settingsBox,
        _conversationStorage = conversationStorage,
        _llmConversationSync = llmConversationSync,
        super(ChatState.initial()) {
    on<ChatStarted>(_onChatStarted);
    on<ChatLanguagesUpdated>(_onLanguagesUpdated);
    on<ChatConversationSelected>(_onConversationSelected);
    on<ChatNewConversationRequested>(_onNewConversationRequested);
    on<ChatMessageSent>(_onMessageSent);
    on<ChatResponseTokenReceived>(_onResponseTokenReceived);
    on<ChatResponseCompleted>(_onResponseCompleted);
    on<ChatResponseFailed>(_onResponseFailed);
    on<ChatGenerationCancelled>(_onGenerationCancelled);
    on<ChatTranslationRequested>(_onTranslationRequested);
    on<ChatConversationCleared>(_onConversationCleared);
    on<ChatMessageDeleted>(_onMessageDeleted);
  }
  
  @override
  Future<void> close() {
    _responseSubscription?.cancel();
    return super.close();
  }
  
  Future<void> _onChatStarted(
    ChatStarted event,
    Emitter<ChatState> emit,
  ) async {
    final stored = _conversationStorage.loadActiveConversation();
    final conversation = (stored != null && stored.messages.isNotEmpty)
        ? stored.copyWith(
            // Keep history, but align language settings with current app state.
            primaryLanguage: event.sourceLanguage,
            targetLanguage: event.targetLanguage,
            isActive: true,
          )
        : Conversation.create(
            id: _uuid.v4(),
            primaryLanguage: event.sourceLanguage,
            targetLanguage: event.targetLanguage,
          );

    emit(state.copyWith(
      conversation: conversation,
      status: ChatStatus.ready,
      errorMessage: null,
    ));

    // Ensure it's persisted (especially if this is a newly created conversation).
    try {
      await _conversationStorage.saveActiveConversation(conversation);
    } catch (_) {
      // Ignore persistence errors; chat should still function.
    }

    // Sync selected conversation into native incremental buffer.
    await _llmConversationSync.setConversation(
      messages: conversation.messages,
      // IMPORTANT: Native layer expects a human language name (e.g. "Spanish"),
      // not a language code (e.g. "es"), otherwise the system prompt constraint
      // becomes "respond in es" which the model may ignore.
      assistantLanguage: _displayLanguage(conversation.targetLanguage),
    );
  }

  Future<void> _onLanguagesUpdated(
    ChatLanguagesUpdated event,
    Emitter<ChatState> emit,
  ) async {
    // If the user changes languages mid-generation, cancel so we don't end up
    // with a native prompt buffer that's out of sync with the UI.
    if (state.status == ChatStatus.generating) {
      _responseSubscription?.cancel();
      _generateResponseUseCase.cancel();
    }

    final updated = state.conversation.copyWith(
      primaryLanguage: event.sourceLanguage,
      targetLanguage: event.targetLanguage,
    );

    emit(state.copyWith(
      conversation: updated,
      status: ChatStatus.ready,
      currentStreamingMessageId: null,
      errorMessage: null,
    ));

    // Persist updated metadata so it survives restarts and stays consistent with history.
    try {
      await _conversationStorage.saveActiveConversation(updated);
    } catch (_) {
      // Ignore persistence errors; chat should still function.
    }

    // Rehydrate native incremental buffer with the same message history but new language constraint.
    await _llmConversationSync.setConversation(
      messages: updated.messages,
      assistantLanguage: _displayLanguage(updated.targetLanguage),
    );
  }

  Future<void> _onConversationSelected(
    ChatConversationSelected event,
    Emitter<ChatState> emit,
  ) async {
    // Cancel any generation before switching.
    _responseSubscription?.cancel();
    _generateResponseUseCase.cancel();

    final loaded = _conversationStorage.loadConversationById(event.conversationId);
    if (loaded == null) return;

    emit(state.copyWith(
      conversation: loaded,
      status: ChatStatus.ready,
      currentStreamingMessageId: null,
      errorMessage: null,
    ));

    try {
      await _conversationStorage.setActiveConversationId(loaded.id);
    } catch (_) {
      // Ignore persistence errors
    }

    await _llmConversationSync.setConversation(
      messages: loaded.messages,
      assistantLanguage: _displayLanguage(loaded.targetLanguage),
    );
  }

  Future<void> _onNewConversationRequested(
    ChatNewConversationRequested event,
    Emitter<ChatState> emit,
  ) async {
    // Cancel any generation before switching.
    _responseSubscription?.cancel();
    _generateResponseUseCase.cancel();

    // Best-effort persist current conversation (already persisted during sends/completions).
    try {
      await _conversationStorage.saveActiveConversation(state.conversation);
    } catch (_) {}

    final fresh = Conversation.create(
      id: _uuid.v4(),
      primaryLanguage: state.conversation.primaryLanguage,
      targetLanguage: state.conversation.targetLanguage,
    );

    emit(state.copyWith(
      conversation: fresh,
      status: ChatStatus.ready,
      currentStreamingMessageId: null,
      errorMessage: null,
    ));

    try {
      await _conversationStorage.saveActiveConversation(fresh);
    } catch (_) {}

    await _llmConversationSync.resetConversation();
    await _llmConversationSync.setConversation(
      messages: const [],
      assistantLanguage: _displayLanguage(fresh.targetLanguage),
    );
  }
  
  Future<void> _onMessageSent(
    ChatMessageSent event,
    Emitter<ChatState> emit,
  ) async {
    // Don't allow sending while generating
    if (state.status == ChatStatus.generating) {
      return;
    }
    
    // Create user message
    final userMessage = Message.user(
      id: _uuid.v4(),
      content: event.content.trim(),
      language: state.conversation.primaryLanguage,
    );
    
    // Create placeholder for assistant response
    final assistantMessage = Message.assistant(
      id: _uuid.v4(),
      content: '',
      isStreaming: true,
    );
    
    // Update conversation with both messages
    var updatedConversation = state.conversation
        .addMessage(userMessage)
        .addMessage(assistantMessage);
    
    emit(state.copyWith(
      conversation: updatedConversation,
      status: ChatStatus.generating,
      currentStreamingMessageId: assistantMessage.id,
    ));

    // Persist immediately so the user's message isn't lost if the app
    // crashes mid-generation. We intentionally do NOT persist per-token.
    try {
      await _conversationStorage.saveActiveConversation(updatedConversation);
    } catch (_) {
      // Ignore persistence errors
    }
    
    // Start generation
    final params = GenerateResponseParams(
      userMessage: event.content,
      conversationHistory: state.conversation.messages
          .where((m) => m.role != MessageRole.system)
          .toList(),
      temperature: event.temperature ?? 0.7,
    );
    
    await _responseSubscription?.cancel();
    
    _responseSubscription = _generateResponseUseCase(params).listen(
      (inferenceEvent) {
        switch (inferenceEvent) {
          case TokenEvent(:final token, :final tokenCount):
            add(ChatResponseTokenReceived(
              token: token,
              tokenCount: tokenCount,
            ));
          case CompletionEvent(:final response):
            add(ChatResponseCompleted(
              tokenCount: response.completionTokens,
              durationMs: response.totalTimeMs,
            ));
          case ErrorEvent(:final message):
            add(ChatResponseFailed(error: message));
        }
      },
      onError: (error) {
        add(ChatResponseFailed(error: error.toString()));
      },
    );
  }
  
  void _onResponseTokenReceived(
    ChatResponseTokenReceived event,
    Emitter<ChatState> emit,
  ) {
    final messageId = state.currentStreamingMessageId;
    if (messageId == null) return;
    
    final messages = state.conversation.messages.toList();
    final index = messages.indexWhere((m) => m.id == messageId);
    
    if (index == -1) return;
    
    messages[index] = messages[index].appendContent(event.token);
    
    emit(state.copyWith(
      conversation: state.conversation.copyWith(messages: messages),
    ));
  }
  
  void _onResponseCompleted(
    ChatResponseCompleted event,
    Emitter<ChatState> emit,
  ) {
    final messageId = state.currentStreamingMessageId;
    if (messageId == null) return;
    
    final messages = state.conversation.messages.toList();
    final index = messages.indexWhere((m) => m.id == messageId);
    
    if (index != -1) {
      final existingMeta = messages[index].metadata ?? const <String, dynamic>{};
      final durationSec = event.durationMs / 1000.0;
      final tps = durationSec <= 0 ? null : (event.tokenCount / durationSec);

      messages[index] = messages[index]
          .completeStreaming(finalTokenCount: event.tokenCount)
          .copyWith(
            metadata: {
              ...existingMeta,
              'genDurationMs': event.durationMs,
              'genTokens': event.tokenCount,
              if (tps != null) 'genTokensPerSecond': tps,
            },
          );
    }
    
    AppLogger.llm(
      'Generation complete',
      tokensGenerated: event.tokenCount,
      duration: Duration(milliseconds: event.durationMs),
      tokensPerSecond: event.tokenCount / (event.durationMs / 1000),
    );
    
    emit(state.copyWith(
      conversation: state.conversation.copyWith(messages: messages),
      status: ChatStatus.ready,
      currentStreamingMessageId: null,
      lastGenerationTokenCount: event.tokenCount,
      lastGenerationDurationMs: event.durationMs,
    ));

    // Persist last generation stats for Settings page
    try {
      _settingsBox.put('lastGenTokens', event.tokenCount);
      _settingsBox.put('lastGenDurationMs', event.durationMs);
    } catch (_) {
      // Ignore persistence errors
    }

    // Persist updated conversation (with final assistant message + stats)
    try {
      _conversationStorage.saveActiveConversation(
        state.conversation.copyWith(messages: messages),
      );
    } catch (_) {
      // Ignore persistence errors
    }
  }
  
  void _onResponseFailed(
    ChatResponseFailed event,
    Emitter<ChatState> emit,
  ) {
    logger.e('Generation failed: ${event.error}');
    
    // Remove the streaming message on failure
    final messageId = state.currentStreamingMessageId;
    if (messageId != null) {
      final messages = state.conversation.messages
          .where((m) => m.id != messageId)
          .toList();
      
      emit(state.copyWith(
        conversation: state.conversation.copyWith(messages: messages),
        status: ChatStatus.error,
        currentStreamingMessageId: null,
        errorMessage: event.error,
      ));
    } else {
      emit(state.copyWith(
        status: ChatStatus.error,
        errorMessage: event.error,
      ));
    }
  }
  
  void _onGenerationCancelled(
    ChatGenerationCancelled event,
    Emitter<ChatState> emit,
  ) {
    _responseSubscription?.cancel();
    _generateResponseUseCase.cancel();
    
    // Mark the current message as complete (with whatever we have)
    final messageId = state.currentStreamingMessageId;
    if (messageId != null) {
      final messages = state.conversation.messages.toList();
      final index = messages.indexWhere((m) => m.id == messageId);
      
      if (index != -1) {
        if (messages[index].content.isEmpty) {
          // Remove empty message
          messages.removeAt(index);
        } else {
          // Complete with partial content
          messages[index] = messages[index].completeStreaming();
        }
      }
      
      emit(state.copyWith(
        conversation: state.conversation.copyWith(messages: messages),
        status: ChatStatus.ready,
        currentStreamingMessageId: null,
      ));
    }
  }
  
  Future<void> _onTranslationRequested(
    ChatTranslationRequested event,
    Emitter<ChatState> emit,
  ) async {
    // Defensive: UI actions can race with state updates (e.g., deleting/clearing),
    // so never assume the message still exists.
    final messageIndex =
        state.conversation.messages.indexWhere((m) => m.id == event.messageId);
    if (messageIndex == -1) {
      emit(state.copyWith(
        status: ChatStatus.error,
        errorMessage: 'Message not found for translation.',
      ));
      return;
    }

    final message = state.conversation.messages[messageIndex];
    if (message.content.trim().isEmpty) {
      emit(state.copyWith(
        status: ChatStatus.error,
        errorMessage: 'Nothing to translate yet.',
      ));
      return;
    }
    
    emit(state.copyWith(status: ChatStatus.translating));
    
    final result = await _translateTextUseCase(TranslateParams(
      text: message.content,
      // Use human-readable language names for higher instruction-following accuracy.
      sourceLanguage: _displayLanguage(state.conversation.primaryLanguage),
      targetLanguage: _displayLanguage(state.conversation.targetLanguage),
    ));
    
    result.fold(
      (failure) {
        emit(state.copyWith(
          status: ChatStatus.error,
          errorMessage: failure.message,
        ));
      },
      (translation) {
        final messages = state.conversation.messages.toList();
        final index = messages.indexWhere((m) => m.id == event.messageId);
        
        if (index != -1) {
          messages[index] = messages[index].withTranslation(
            translation.translatedText,
            state.conversation.targetLanguage,
          );
        }
        
        emit(state.copyWith(
          conversation: state.conversation.copyWith(messages: messages),
          status: ChatStatus.ready,
        ));

        try {
          _conversationStorage.saveActiveConversation(
            state.conversation.copyWith(messages: messages),
          );
        } catch (_) {
          // Ignore persistence errors
        }
      },
    );
  }

  /// Map a language code (e.g. "es") to a name (e.g. "Spanish") for prompts/native.
  ///
  /// This prevents models from ignoring constraints like "respond in es".
  String _displayLanguage(String codeOrName) {
    return LanguageConstants.supportedLanguages[codeOrName] ?? codeOrName;
  }
  
  void _onConversationCleared(
    ChatConversationCleared event,
    Emitter<ChatState> emit,
  ) {
    final newConversation = Conversation.create(
      id: _uuid.v4(),
      primaryLanguage: state.conversation.primaryLanguage,
      targetLanguage: state.conversation.targetLanguage,
    );

    emit(state.copyWith(
      conversation: newConversation,
      status: ChatStatus.ready,
    ));

    try {
      _conversationStorage.saveActiveConversation(newConversation);
    } catch (_) {
      // Ignore persistence errors
    }
  }
  
  void _onMessageDeleted(
    ChatMessageDeleted event,
    Emitter<ChatState> emit,
  ) {
    final messages = state.conversation.messages
        .where((m) => m.id != event.messageId)
        .toList();
    
    emit(state.copyWith(
      conversation: state.conversation.copyWith(messages: messages),
    ));

    try {
      _conversationStorage.saveActiveConversation(
        state.conversation.copyWith(messages: messages),
      );
    } catch (_) {
      // Ignore persistence errors
    }
  }
}
