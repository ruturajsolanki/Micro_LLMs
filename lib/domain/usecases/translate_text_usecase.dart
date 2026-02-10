import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../entities/inference_request.dart';
import '../repositories/llm_repository.dart';
import '../../core/utils/result.dart';
import '../../core/error/failures.dart';
import 'usecase.dart';

/// Use case for translating text between languages.
/// 
/// Uses the LLM for translation via carefully crafted prompts.
/// This approach works well for Phi-2 and similar instruction-following models.
/// 
/// Design Decision: We use a non-streaming approach for translation because:
/// 1. Translations are typically short
/// 2. Partial translations can be confusing
/// 3. We want the complete translation before displaying
class TranslateTextUseCase extends UseCase<TranslationResult, TranslateParams> {
  final LLMRepository _llmRepository;
  
  TranslateTextUseCase({
    required LLMRepository llmRepository,
  }) : _llmRepository = llmRepository;
  
  @override
  AsyncResult<TranslationResult> call(TranslateParams params) async {
    // Validate model is loaded
    if (!_llmRepository.isModelLoaded) {
      return const Left(LLMFailure(
        message: 'Model not loaded',
        type: LLMFailureType.modelNotLoaded,
      ));
    }
    
    // Validate input
    if (params.text.trim().isEmpty) {
      return const Left(LLMFailure(
        message: 'Text to translate cannot be empty',
        type: LLMFailureType.inferenceError,
      ));
    }
    
    // Build translation request
    final request = InferenceRequest.forTranslation(
      text: params.text,
      sourceLanguage: params.sourceLanguage,
      targetLanguage: params.targetLanguage,
    );
    
    // Execute inference
    final result = await _llmRepository.generate(request);
    
    return result.fold(
      (failure) => Left(failure),
      (response) {
        // Clean up the response
        final translatedText = _cleanTranslation(response.text);
        
        return Right(TranslationResult(
          originalText: params.text,
          translatedText: translatedText,
          sourceLanguage: params.sourceLanguage,
          targetLanguage: params.targetLanguage,
          tokenCount: response.completionTokens,
          processingTimeMs: response.totalTimeMs,
        ));
      },
    );
  }
  
  /// Clean up translation output.
  /// 
  /// The LLM might include extra text, quotes, or formatting.
  /// This method strips those artifacts.
  String _cleanTranslation(String rawOutput) {
    var cleaned = rawOutput.trim();
    
    // Remove common prefixes the model might add
    final prefixes = [
      'Translation:',
      'Here is the translation:',
      'The translation is:',
    ];
    
    for (final prefix in prefixes) {
      if (cleaned.toLowerCase().startsWith(prefix.toLowerCase())) {
        cleaned = cleaned.substring(prefix.length).trim();
      }
    }
    
    // Remove surrounding quotes if present
    if ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
        (cleaned.startsWith("'") && cleaned.endsWith("'"))) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    
    // Remove trailing newlines
    cleaned = cleaned.replaceAll(RegExp(r'\n+$'), '');
    
    return cleaned;
  }
}

/// Parameters for translation.
class TranslateParams extends Equatable {
  /// Text to translate.
  final String text;
  
  /// Source language (display name or code).
  final String sourceLanguage;
  
  /// Target language (display name or code).
  final String targetLanguage;
  
  const TranslateParams({
    required this.text,
    required this.sourceLanguage,
    required this.targetLanguage,
  });
  
  @override
  List<Object> get props => [text, sourceLanguage, targetLanguage];
}

/// Result of a translation operation.
class TranslationResult extends Equatable {
  /// Original text that was translated.
  final String originalText;
  
  /// Translated text.
  final String translatedText;
  
  /// Source language.
  final String sourceLanguage;
  
  /// Target language.
  final String targetLanguage;
  
  /// Tokens used for translation.
  final int tokenCount;
  
  /// Processing time in milliseconds.
  final int processingTimeMs;
  
  const TranslationResult({
    required this.originalText,
    required this.translatedText,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.tokenCount,
    required this.processingTimeMs,
  });
  
  @override
  List<Object> get props => [
    originalText,
    translatedText,
    sourceLanguage,
    targetLanguage,
    tokenCount,
    processingTimeMs,
  ];
}
