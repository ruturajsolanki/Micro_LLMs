import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/utils/logger.dart';
import '../../domain/entities/inference_request.dart';
import '../../domain/entities/message.dart';

/// Groq API client for chat completions and Whisper STT.
///
/// Groq API is OpenAI-compatible:
/// - Chat: POST /openai/v1/chat/completions
/// - Whisper: POST /openai/v1/audio/transcriptions
class GroqApiService {
  static const String _baseUrl = 'https://api.groq.com/openai/v1';
  static const String _defaultChatModel = 'llama-3.3-70b-versatile';
  static const String _defaultWhisperModel = 'whisper-large-v3-turbo';

  final Dio _dio;

  GroqApiService()
      : _dio = Dio(BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 120),
        ));

  /// Generate a chat completion (non-streaming).
  Future<GroqChatResponse> chatCompletion({
    required String apiKey,
    required InferenceRequest request,
    String? model,
  }) async {
    final messages = <Map<String, String>>[];

    if (request.systemPrompt != null && request.systemPrompt!.isNotEmpty) {
      messages.add({'role': 'system', 'content': request.systemPrompt!});
    }

    for (final msg in request.contextMessages) {
      final role = msg.role == MessageRole.user
          ? 'user'
          : msg.role == MessageRole.assistant
              ? 'assistant'
              : 'system';
      messages.add({'role': role, 'content': msg.content});
    }

    messages.add({'role': 'user', 'content': request.prompt});

    final stopwatch = Stopwatch()..start();

    final response = await _dio.post<Map<String, dynamic>>(
      '/chat/completions',
      options: Options(headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      }),
      data: jsonEncode({
        'model': model ?? _defaultChatModel,
        'messages': messages,
        'max_tokens': request.maxTokens,
        'temperature': request.temperature,
        'top_p': request.topP,
        if (request.stopSequences.isNotEmpty) 'stop': request.stopSequences,
        'stream': false,
      }),
    );

    stopwatch.stop();

    final body = response.data!;
    final choice = (body['choices'] as List).first as Map<String, dynamic>;
    final message = choice['message'] as Map<String, dynamic>;
    final usage = body['usage'] as Map<String, dynamic>?;

    return GroqChatResponse(
      text: (message['content'] as String?) ?? '',
      promptTokens: (usage?['prompt_tokens'] as int?) ?? 0,
      completionTokens: (usage?['completion_tokens'] as int?) ?? 0,
      totalTimeMs: stopwatch.elapsedMilliseconds,
      finishReason: (choice['finish_reason'] as String?) ?? 'stop',
      model: (body['model'] as String?) ?? _defaultChatModel,
    );
  }

  /// Generate a streaming chat completion.
  Stream<GroqStreamEvent> chatCompletionStream({
    required String apiKey,
    required InferenceRequest request,
    String? model,
  }) async* {
    final messages = <Map<String, String>>[];

    if (request.systemPrompt != null && request.systemPrompt!.isNotEmpty) {
      messages.add({'role': 'system', 'content': request.systemPrompt!});
    }

    for (final msg in request.contextMessages) {
      final role = msg.role == MessageRole.user
          ? 'user'
          : msg.role == MessageRole.assistant
              ? 'assistant'
              : 'system';
      messages.add({'role': role, 'content': msg.content});
    }

    messages.add({'role': 'user', 'content': request.prompt});

    final stopwatch = Stopwatch()..start();

    final response = await _dio.post<ResponseBody>(
      '/chat/completions',
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.stream,
      ),
      data: jsonEncode({
        'model': model ?? _defaultChatModel,
        'messages': messages,
        'max_tokens': request.maxTokens,
        'temperature': request.temperature,
        'top_p': request.topP,
        if (request.stopSequences.isNotEmpty) 'stop': request.stopSequences,
        'stream': true,
      }),
    );

    final fullText = StringBuffer();
    var tokenCount = 0;

    await for (final chunk in response.data!.stream) {
      final lines = utf8.decode(chunk).split('\n');
      for (final line in lines) {
        if (!line.startsWith('data: ')) continue;
        final jsonStr = line.substring(6).trim();
        if (jsonStr == '[DONE]') continue;

        try {
          final data = jsonDecode(jsonStr) as Map<String, dynamic>;
          final delta = ((data['choices'] as List).first
              as Map<String, dynamic>)['delta'] as Map<String, dynamic>?;
          final content = delta?['content'] as String?;
          if (content != null && content.isNotEmpty) {
            fullText.write(content);
            tokenCount++;
            yield GroqStreamToken(token: content, tokenCount: tokenCount);
          }
        } catch (_) {
          // Skip malformed SSE chunks
        }
      }
    }

    stopwatch.stop();
    yield GroqStreamDone(
      fullText: fullText.toString(),
      tokenCount: tokenCount,
      totalTimeMs: stopwatch.elapsedMilliseconds,
    );
  }

  /// Transcribe audio using Groq Whisper API.
  ///
  /// [audioFilePath] must be a valid WAV, MP3, FLAC, or WebM file.
  Future<GroqTranscriptionResponse> transcribeAudio({
    required String apiKey,
    required String audioFilePath,
    String? language,
    String? model,
  }) async {
    final file = File(audioFilePath);
    if (!file.existsSync()) {
      throw ArgumentError('Audio file not found: $audioFilePath');
    }

    AppLogger.i('GroqApiService: transcribing ${file.lengthSync()} bytes '
        'from $audioFilePath');

    final stopwatch = Stopwatch()..start();

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        audioFilePath,
        filename: audioFilePath.split('/').last,
      ),
      'model': model ?? _defaultWhisperModel,
      if (language != null) 'language': language,
      'response_format': 'verbose_json',
      'temperature': 0.0,
    });

    final response = await _dio.post<Map<String, dynamic>>(
      '/audio/transcriptions',
      options: Options(headers: {
        'Authorization': 'Bearer $apiKey',
      }),
      data: formData,
    );

    stopwatch.stop();

    final body = response.data!;
    final text = (body['text'] as String?) ?? '';
    final duration = (body['duration'] as num?)?.toDouble() ?? 0.0;

    AppLogger.i('GroqApiService: transcription completed in '
        '${stopwatch.elapsedMilliseconds}ms — '
        '${text.split(' ').length} words, ${duration}s audio');

    return GroqTranscriptionResponse(
      text: text,
      audioDurationSeconds: duration,
      processingTimeMs: stopwatch.elapsedMilliseconds,
      language: (body['language'] as String?) ?? 'en',
    );
  }

  /// Validate API key by listing models.
  Future<bool> validateApiKey(String apiKey) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/models',
        options: Options(headers: {
          'Authorization': 'Bearer $apiKey',
        }),
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

/// Response from Groq chat completion.
class GroqChatResponse {
  final String text;
  final int promptTokens;
  final int completionTokens;
  final int totalTimeMs;
  final String finishReason;
  final String model;

  const GroqChatResponse({
    required this.text,
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTimeMs,
    required this.finishReason,
    required this.model,
  });

  int get totalTokens => promptTokens + completionTokens;
}

/// Streaming events from Groq.
sealed class GroqStreamEvent {
  const GroqStreamEvent();
}

final class GroqStreamToken extends GroqStreamEvent {
  final String token;
  final int tokenCount;
  const GroqStreamToken({required this.token, required this.tokenCount});
}

final class GroqStreamDone extends GroqStreamEvent {
  final String fullText;
  final int tokenCount;
  final int totalTimeMs;
  const GroqStreamDone({
    required this.fullText,
    required this.tokenCount,
    required this.totalTimeMs,
  });
}

/// Response from Groq Whisper transcription.
class GroqTranscriptionResponse {
  final String text;
  final double audioDurationSeconds;
  final int processingTimeMs;
  final String language;

  const GroqTranscriptionResponse({
    required this.text,
    required this.audioDurationSeconds,
    required this.processingTimeMs,
    required this.language,
  });
}
