import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/logger.dart';

/// ElevenLabs TTS client + local playback.
///
/// Notes:
/// - This is OPTIONAL and requires an internet connection.
/// - The API key is stored in [FlutterSecureStorage] (keystore-backed on Android).
class ElevenLabsTtsService with Loggable {
  static const _apiKeyStorageKey = 'elevenLabsApiKey';

  final FlutterSecureStorage _secureStorage;
  final Dio _dio;
  final AudioPlayer _player;

  ElevenLabsTtsService({
    required FlutterSecureStorage secureStorage,
    Dio? dio,
    AudioPlayer? player,
  })  : _secureStorage = secureStorage,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://api.elevenlabs.io',
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 60),
            )),
        _player = player ?? AudioPlayer();

  Future<void> dispose() async {
    await _player.dispose();
  }

  Future<void> setApiKey(String apiKey) async {
    await _secureStorage.write(key: _apiKeyStorageKey, value: apiKey.trim());
  }

  Future<String?> getApiKey() async {
    final key = await _secureStorage.read(key: _apiKeyStorageKey);
    return key?.trim().isEmpty ?? true ? null : key?.trim();
  }

  Future<void> clearApiKey() async {
    await _secureStorage.delete(key: _apiKeyStorageKey);
  }

  bool get isPlaying => _player.playing;

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// Convert [text] to speech and play it.
  ///
  /// Uses ElevenLabs REST endpoint:
  /// `POST /v1/text-to-speech/{voice_id}?output_format=mp3_44100_128`
  Future<void> speak({
    required String text,
    required String voiceId,
    String modelId = 'eleven_multilingual_v2',
    String outputFormat = 'mp3_44100_128',
  }) async {
    final apiKey = await getApiKey();
    if (apiKey == null) {
      throw StateError('ElevenLabs API key not set');
    }

    final bytes = await _convertToAudioBytes(
      apiKey: apiKey,
      text: text,
      voiceId: voiceId,
      modelId: modelId,
      outputFormat: outputFormat,
    );

    final path = await _writeTempMp3(bytes);

    // Ensure we stop any current playback (avoid overlaps in call mode).
    await stop();

    await _player.setFilePath(path);
    await _player.play();

    // Wait for completion.
    await _player.processingStateStream.firstWhere(
      (s) => s == ProcessingState.completed,
    );
  }

  Future<Uint8List> _convertToAudioBytes({
    required String apiKey,
    required String text,
    required String voiceId,
    required String modelId,
    required String outputFormat,
  }) async {
    try {
      final resp = await _dio.post<List<int>>(
        '/v1/text-to-speech/$voiceId',
        queryParameters: {
          'output_format': outputFormat,
          'enable_logging': false,
        },
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'xi-api-key': apiKey,
            'accept': 'audio/mpeg',
            'content-type': 'application/json',
          },
        ),
        data: {
          'text': text,
          'model_id': modelId,
        },
      );

      final data = resp.data;
      if (data == null || data.isEmpty) {
        throw Exception('Empty audio response from ElevenLabs');
      }

      return Uint8List.fromList(data);
    } on DioException catch (e, stack) {
      logger.e('ElevenLabs TTS failed', error: e, stackTrace: stack);
      final msg = e.response?.data is Map
          ? (e.response?.data as Map)['detail']?.toString()
          : e.message;
      throw Exception(msg ?? 'ElevenLabs request failed');
    }
  }

  Future<String> _writeTempMp3(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/elevenlabs_${DateTime.now().millisecondsSinceEpoch}.mp3');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}

