import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dartz/dartz.dart';

import 'package:micro_llm_app/core/error/failures.dart';
import 'package:micro_llm_app/domain/entities/inference_request.dart';
import 'package:micro_llm_app/domain/repositories/llm_repository.dart';
import 'package:micro_llm_app/domain/usecases/translate_text_usecase.dart';

// Mocks
class MockLLMRepository extends Mock implements LLMRepository {}

void main() {
  late TranslateTextUseCase useCase;
  late MockLLMRepository mockRepository;

  setUp(() {
    mockRepository = MockLLMRepository();
    useCase = TranslateTextUseCase(llmRepository: mockRepository);
  });

  setUpAll(() {
    // Register fallback values for mocktail
    registerFallbackValue(const InferenceRequest(prompt: ''));
  });

  group('TranslateTextUseCase', () {
    const testText = 'Hello, world!';
    const sourceLanguage = 'English';
    const targetLanguage = 'Spanish';
    const translatedText = 'Hola, mundo!';
    
    final testParams = TranslateParams(
      text: testText,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
    
    final testResponse = InferenceResponse(
      text: translatedText,
      promptTokens: 10,
      completionTokens: 5,
      totalTimeMs: 100,
    );

    test('returns TranslationResult when translation succeeds', () async {
      // Arrange
      when(() => mockRepository.isModelLoaded).thenReturn(true);
      when(() => mockRepository.generate(any()))
          .thenAnswer((_) async => Right(testResponse));
      
      // Act
      final result = await useCase(testParams);
      
      // Assert
      expect(result.isRight(), true);
      result.fold(
        (failure) => fail('Expected success'),
        (translation) {
          expect(translation.originalText, testText);
          expect(translation.translatedText, translatedText);
          expect(translation.sourceLanguage, sourceLanguage);
          expect(translation.targetLanguage, targetLanguage);
        },
      );
    });

    test('returns failure when model is not loaded', () async {
      // Arrange
      when(() => mockRepository.isModelLoaded).thenReturn(false);
      
      // Act
      final result = await useCase(testParams);
      
      // Assert
      expect(result.isLeft(), true);
      result.fold(
        (failure) {
          expect(failure, isA<LLMFailure>());
          expect((failure as LLMFailure).type, LLMFailureType.modelNotLoaded);
        },
        (_) => fail('Expected failure'),
      );
    });

    test('returns failure when text is empty', () async {
      // Arrange
      when(() => mockRepository.isModelLoaded).thenReturn(true);
      
      final emptyParams = TranslateParams(
        text: '   ',
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      );
      
      // Act
      final result = await useCase(emptyParams);
      
      // Assert
      expect(result.isLeft(), true);
    });

    test('returns failure when inference fails', () async {
      // Arrange
      when(() => mockRepository.isModelLoaded).thenReturn(true);
      when(() => mockRepository.generate(any()))
          .thenAnswer((_) async => const Left(LLMFailure(
            message: 'Inference error',
            type: LLMFailureType.inferenceError,
          )));
      
      // Act
      final result = await useCase(testParams);
      
      // Assert
      expect(result.isLeft(), true);
    });

    test('cleans translation output correctly', () async {
      // Arrange
      when(() => mockRepository.isModelLoaded).thenReturn(true);
      when(() => mockRepository.generate(any()))
          .thenAnswer((_) async => Right(InferenceResponse(
            text: 'Translation: "Hola, mundo!"\n\n',
            promptTokens: 10,
            completionTokens: 5,
            totalTimeMs: 100,
          )));
      
      // Act
      final result = await useCase(testParams);
      
      // Assert
      expect(result.isRight(), true);
      result.fold(
        (_) => fail('Expected success'),
        (translation) {
          // Should clean up the "Translation:" prefix and quotes
          expect(translation.translatedText, 'Hola, mundo!');
        },
      );
    });
  });
}
