import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/utils/logger.dart';
import '../../domain/entities/inference_request.dart';
import '../../domain/entities/message.dart';

/// Gemini API client for content generation.
///
/// Uses the Gemini REST API:
/// POST /v1beta/models/{model}:generateContent
class GeminiApiService {
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta';
  static const String _defaultModel = 'gemini-2.0-flash';

  final Dio _dio;

  GeminiApiService()
      : _dio = Dio(BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 120),
        ));

  /// Generate content (non-streaming).
  Future<GeminiResponse> generateContent({
    required String apiKey,
    required InferenceRequest request,
    String? model,
  }) async {
    final contents = <Map<String, dynamic>>[];

    for (final msg in request.contextMessages) {
      final role = msg.role == MessageRole.user ? 'user' : 'model';
      contents.add({
        'role': role,
        'parts': [
          {'text': msg.content},
        ],
      });
    }

    contents.add({
      'role': 'user',
      'parts': [
        {'text': request.prompt},
      ],
    });

    final systemInstruction = request.systemPrompt != null
        ? {
            'parts': [
              {'text': request.systemPrompt},
            ],
          }
        : null;

    final modelName = model ?? _defaultModel;
    final stopwatch = Stopwatch()..start();

    final response = await _dio.post<Map<String, dynamic>>(
      '/models/$modelName:generateContent',
      queryParameters: {'key': apiKey},
      options: Options(headers: {'Content-Type': 'application/json'}),
      data: jsonEncode({
        'contents': contents,
        if (systemInstruction != null) 'systemInstruction': systemInstruction,
        'generationConfig': {
          'maxOutputTokens': request.maxTokens,
          'temperature': request.temperature,
          'topP': request.topP,
          'topK': request.topK,
          if (request.stopSequences.isNotEmpty)
            'stopSequences': request.stopSequences,
        },
      }),
    );

    stopwatch.stop();

    final body = response.data!;
    final candidates = body['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      AppLogger.w('GeminiApiService: no candidates in response');
      return GeminiResponse(
        text: '',
        promptTokens: 0,
        completionTokens: 0,
        totalTimeMs: stopwatch.elapsedMilliseconds,
        finishReason: 'SAFETY',
        model: modelName,
      );
    }

    final candidate = candidates.first as Map<String, dynamic>;
    final content = candidate['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List?;
    final text = parts?.isNotEmpty == true
        ? (parts!.first as Map<String, dynamic>)['text'] as String? ?? ''
        : '';

    final usageMetadata = body['usageMetadata'] as Map<String, dynamic>?;
    final promptTokens =
        (usageMetadata?['promptTokenCount'] as int?) ?? 0;
    final completionTokens =
        (usageMetadata?['candidatesTokenCount'] as int?) ?? 0;

    return GeminiResponse(
      text: text,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTimeMs: stopwatch.elapsedMilliseconds,
      finishReason:
          (candidate['finishReason'] as String?) ?? 'STOP',
      model: modelName,
    );
  }

  /// Stream content generation.
  Stream<GeminiStreamEvent> generateContentStream({
    required String apiKey,
    required InferenceRequest request,
    String? model,
  }) async* {
    final contents = <Map<String, dynamic>>[];

    for (final msg in request.contextMessages) {
      final role = msg.role == MessageRole.user ? 'user' : 'model';
      contents.add({
        'role': role,
        'parts': [
          {'text': msg.content},
        ],
      });
    }

    contents.add({
      'role': 'user',
      'parts': [
        {'text': request.prompt},
      ],
    });

    final systemInstruction = request.systemPrompt != null
        ? {
            'parts': [
              {'text': request.systemPrompt},
            ],
          }
        : null;

    final modelName = model ?? _defaultModel;
    final stopwatch = Stopwatch()..start();

    final response = await _dio.post<ResponseBody>(
      '/models/$modelName:streamGenerateContent',
      queryParameters: {'key': apiKey, 'alt': 'sse'},
      options: Options(
        headers: {'Content-Type': 'application/json'},
        responseType: ResponseType.stream,
      ),
      data: jsonEncode({
        'contents': contents,
        if (systemInstruction != null) 'systemInstruction': systemInstruction,
        'generationConfig': {
          'maxOutputTokens': request.maxTokens,
          'temperature': request.temperature,
          'topP': request.topP,
          'topK': request.topK,
          if (request.stopSequences.isNotEmpty)
            'stopSequences': request.stopSequences,
        },
      }),
    );

    final fullText = StringBuffer();
    var tokenCount = 0;

    await for (final chunk in response.data!.stream) {
      final lines = utf8.decode(chunk).split('\n');
      for (final line in lines) {
        if (!line.startsWith('data: ')) continue;
        final jsonStr = line.substring(6).trim();
        if (jsonStr.isEmpty) continue;

        try {
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;
          final candidates = data['candidates'] as List?;
          if (candidates == null || candidates.isEmpty) continue;

          final content = (candidates.first
              as Map<String, dynamic>)['content'] as Map<String, dynamic>?;
          final parts = content?['parts'] as List?;
          if (parts == null || parts.isEmpty) continue;

          final text =
              (parts.first as Map<String, dynamic>)['text'] as String?;
          if (text != null && text.isNotEmpty) {
            fullText.write(text);
            tokenCount++;
            yield GeminiStreamToken(token: text, tokenCount: tokenCount);
          }
        } catch (_) {
          // Skip malformed SSE chunks
        }
      }
    }

    stopwatch.stop();
    yield GeminiStreamDone(
      fullText: fullText.toString(),
      tokenCount: tokenCount,
      totalTimeMs: stopwatch.elapsedMilliseconds,
    );
  }

  /// Validate API key by listing models.
  Future<bool> validateApiKey(String apiKey) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/models',
        queryParameters: {'key': apiKey},
      );
      return response.statusCode == 200;
    } on DioException {
      return false;
    }
  }

  void dispose() {
    _dio.close();
  }
}

/// Response from Gemini generate content.
class GeminiResponse {
  final String text;
  final int promptTokens;
  final int completionTokens;
  final int totalTimeMs;
  final String finishReason;
  final String model;

  const GeminiResponse({
    required this.text,
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTimeMs,
    required this.finishReason,
    required this.model,
  });

  int get totalTokens => promptTokens + completionTokens;
}

/// Streaming events from Gemini.
sealed class GeminiStreamEvent {
  const GeminiStreamEvent();
}

final class GeminiStreamToken extends GeminiStreamEvent {
  final String token;
  final int tokenCount;
  const GeminiStreamToken({required this.token, required this.tokenCount});
}

final class GeminiStreamDone extends GeminiStreamEvent {
  final String fullText;
  final int tokenCount;
  final int totalTimeMs;
  const GeminiStreamDone({
    required this.fullText,
    required this.tokenCount,
    required this.totalTimeMs,
  });
}
