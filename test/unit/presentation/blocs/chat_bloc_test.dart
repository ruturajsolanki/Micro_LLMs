import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:micro_llm_app/domain/repositories/llm_repository.dart';
import 'package:micro_llm_app/domain/entities/inference_request.dart';
import 'package:micro_llm_app/domain/usecases/generate_response_usecase.dart';
import 'package:micro_llm_app/domain/usecases/translate_text_usecase.dart';
import 'package:micro_llm_app/presentation/blocs/chat/chat_bloc.dart';
import 'package:micro_llm_app/data/datasources/conversation_storage.dart';
import 'package:micro_llm_app/data/datasources/llm_conversation_sync_datasource.dart';
import 'package:hive/hive.dart';

// Mocks
class MockGenerateResponseUseCase extends Mock implements GenerateResponseUseCase {}
class MockTranslateTextUseCase extends Mock implements TranslateTextUseCase {}
class MockLLMRepository extends Mock implements LLMRepository {}
class MockSettingsBox extends Mock implements Box<dynamic> {}
class MockConversationStorage extends Mock implements ConversationStorage {}
class MockLlmConversationSyncDataSource extends Mock implements LlmConversationSyncDataSource {}

void main() {
  late ChatBloc chatBloc;
  late MockGenerateResponseUseCase mockGenerateResponseUseCase;
  late MockTranslateTextUseCase mockTranslateTextUseCase;
  late MockSettingsBox mockSettingsBox;
  late MockConversationStorage mockConversationStorage;
  late MockLlmConversationSyncDataSource mockSync;

  setUp(() {
    mockGenerateResponseUseCase = MockGenerateResponseUseCase();
    mockTranslateTextUseCase = MockTranslateTextUseCase();
    mockSettingsBox = MockSettingsBox();
    mockConversationStorage = MockConversationStorage();
    mockSync = MockLlmConversationSyncDataSource();
    
    chatBloc = ChatBloc(
      generateResponseUseCase: mockGenerateResponseUseCase,
      translateTextUseCase: mockTranslateTextUseCase,
      settingsBox: mockSettingsBox,
      conversationStorage: mockConversationStorage,
      llmConversationSync: mockSync,
    );
  });

  setUpAll(() {
    registerFallbackValue(const GenerateResponseParams(userMessage: ''));
    registerFallbackValue(const TranslateParams(
      text: '',
      sourceLanguage: '',
      targetLanguage: '',
    ));
  });

  tearDown(() {
    chatBloc.close();
  });

  group('ChatBloc', () {
    test('initial state is correct', () {
      expect(chatBloc.state.status, ChatStatus.initial);
      expect(chatBloc.state.conversation.isEmpty, true);
    });

    blocTest<ChatBloc, ChatState>(
      'emits ready state when ChatStarted is added',
      build: () => chatBloc,
      act: (bloc) => bloc.add(const ChatStarted(
        sourceLanguage: 'en',
        targetLanguage: 'es',
      )),
      expect: () => [
        isA<ChatState>()
            .having((s) => s.status, 'status', ChatStatus.ready)
            .having((s) => s.conversation.primaryLanguage, 'primaryLanguage', 'en')
            .having((s) => s.conversation.targetLanguage, 'targetLanguage', 'es'),
      ],
    );

    blocTest<ChatBloc, ChatState>(
      'adds user message and starts generation when ChatMessageSent is added',
      build: () {
        when(() => mockGenerateResponseUseCase.call(any()))
            .thenAnswer((_) => Stream.fromIterable([
              const TokenEvent(token: 'Hello', tokenCount: 1),
              const TokenEvent(token: ' world', tokenCount: 2),
              CompletionEvent(
                response: InferenceResponse(
                  text: 'Hello world',
                  promptTokens: 5,
                  completionTokens: 2,
                  totalTimeMs: 100,
                ),
              ),
            ]));
        
        return chatBloc;
      },
      seed: () {
        // Start with initialized state
        chatBloc.add(const ChatStarted(
          sourceLanguage: 'en',
          targetLanguage: 'es',
        ));
        return ChatState(
          conversation: chatBloc.state.conversation,
          status: ChatStatus.ready,
        );
      },
      act: (bloc) => bloc.add(const ChatMessageSent(content: 'Hi there!')),
      verify: (_) {
        verify(() => mockGenerateResponseUseCase.call(any())).called(1);
      },
    );

    blocTest<ChatBloc, ChatState>(
      'clears conversation when ChatConversationCleared is added',
      build: () => chatBloc,
      seed: () => ChatState(
        conversation: chatBloc.state.conversation.copyWith(
          messages: [
            // Add some messages
          ],
        ),
        status: ChatStatus.ready,
      ),
      act: (bloc) => bloc.add(const ChatConversationCleared()),
      expect: () => [
        isA<ChatState>()
            .having((s) => s.status, 'status', ChatStatus.ready)
            .having((s) => s.conversation.isEmpty, 'isEmpty', true),
      ],
    );

    blocTest<ChatBloc, ChatState>(
      'handles generation cancellation correctly',
      build: () {
        // Create a stream that never completes
        when(() => mockGenerateResponseUseCase.call(any()))
            .thenAnswer((_) => Stream.periodic(
              const Duration(milliseconds: 100),
              (i) => TokenEvent(token: 'token$i', tokenCount: i + 1),
            ));
        
        when(() => mockGenerateResponseUseCase.cancel()).thenReturn(null);
        
        return chatBloc;
      },
      act: (bloc) async {
        bloc.add(const ChatStarted(sourceLanguage: 'en', targetLanguage: 'es'));
        await Future.delayed(const Duration(milliseconds: 50));
        bloc.add(const ChatMessageSent(content: 'Hello'));
        await Future.delayed(const Duration(milliseconds: 150));
        bloc.add(const ChatGenerationCancelled());
      },
      verify: (_) {
        verify(() => mockGenerateResponseUseCase.cancel()).called(1);
      },
    );
  });

  group('ChatState', () {
    test('isGenerating returns correct value', () {
      expect(
        ChatState(
          conversation: chatBloc.state.conversation,
          status: ChatStatus.generating,
        ).isGenerating,
        true,
      );
    });

    test('tokensPerSecond calculates correctly', () {
      final state = ChatState(
        conversation: chatBloc.state.conversation,
        status: ChatStatus.ready,
        lastGenerationTokenCount: 100,
        lastGenerationDurationMs: 1000,
      );
      
      expect(state.tokensPerSecond, 100.0);
    });

    test('tokensPerSecond returns null when no generation data', () {
      final state = ChatState(
        conversation: chatBloc.state.conversation,
        status: ChatStatus.ready,
      );
      
      expect(state.tokensPerSecond, null);
    });
  });
}
