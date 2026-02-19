import 'dart:async';

import 'package:deepgram_speech_to_text/deepgram_speech_to_text.dart';
import 'package:deepgram_speech_to_text/src/listen/deepgram_listen_result.dart';

import '../../core/utils/logger.dart';
import 'cloud_api_key_storage.dart';

/// Real-time streaming speech-to-text using Deepgram's WebSocket API.
///
/// Accepts raw PCM audio chunks from the native recorder and emits
/// partial transcript updates in real time.
class DeepgramStreamingService {
  final CloudApiKeyStorage _keyStorage;

  /// Built-in default Deepgram API key.
  static const String _defaultDeepgramKey =
      '6382e5e7e2315bd1b17a1704d7b6c5887bd32fa4';

  Deepgram? _deepgram;
  DeepgramLiveListener? _listener;
  StreamController<String>? _transcriptController;
  StreamController<List<int>>? _audioController;

  /// Accumulated transcript from final results.
  final StringBuffer _finalText = StringBuffer();

  /// The most recent interim (partial) text.
  String _interimText = '';

  DeepgramStreamingService({
    required CloudApiKeyStorage keyStorage,
  }) : _keyStorage = keyStorage;

  /// Stream of live transcript updates (combined final + interim text).
  Stream<String>? get transcriptStream => _transcriptController?.stream;

  /// Whether the service is currently streaming.
  bool get isStreaming => _listener != null;

  /// Start live transcription. Pipe PCM audio chunks via [addAudioData].
  Future<void> start() async {
    if (_listener != null) {
      AppLogger.w(
          'DeepgramStreamingService: already streaming, stopping first');
      await stop();
    }

    final apiKey = await _getApiKey();

    _deepgram = Deepgram(apiKey);
    _transcriptController = StreamController<String>.broadcast();
    _finalText.clear();
    _interimText = '';

    final params = <String, dynamic>{
      'language': 'en',
      'punctuate': true,
      'smart_format': true,
      'filler_words': true,
      'interim_results': true,
      'endpointing': 300,
      'vad_events': false,
    };

    // Create audio input stream for the Deepgram listener.
    final audioController = StreamController<List<int>>();
    _audioController = audioController;

    _listener = _deepgram!.listen.liveListener(
      audioController.stream,
      queryParams: params,
      encoding: 'linear16',
      sampleRate: 16000,
    );

    _listener!.stream.listen(
      (result) {
        _handleResult(result);
      },
      onError: (e) {
        AppLogger.e('DeepgramStreamingService: stream error: $e');
      },
      onDone: () {
        AppLogger.i('DeepgramStreamingService: stream done');
      },
    );

    await _listener!.start();

    AppLogger.i('DeepgramStreamingService: started live transcription');
  }

  /// Feed raw PCM audio bytes into the Deepgram WebSocket.
  void addAudioData(List<int> pcmBytes) {
    if (_audioController != null && !_audioController!.isClosed) {
      _audioController!.add(pcmBytes);
    }
  }

  /// Stop live transcription and clean up.
  Future<void> stop() async {
    try {
      await _listener?.close();
    } catch (e) {
      AppLogger.e('DeepgramStreamingService: error closing listener: $e');
    }
    _listener = null;

    try {
      await _audioController?.close();
    } catch (_) {}
    _audioController = null;

    _deepgram = null;

    // Emit final state before closing.
    final finalTranscript = _finalText.toString().trim();
    if (finalTranscript.isNotEmpty) {
      _transcriptController?.add(finalTranscript);
    }

    try {
      await _transcriptController?.close();
    } catch (_) {}
    _transcriptController = null;

    AppLogger.i('DeepgramStreamingService: stopped');
  }

  void _handleResult(DeepgramListenResult result) {
    try {
      if (!result.isResults) return;

      final transcript = result.transcript ?? '';

      if (result.isFinal && transcript.isNotEmpty) {
        _finalText.write('$transcript ');
        _interimText = '';
      } else if (!result.isFinal) {
        _interimText = transcript;
      }

      // Combine final text + current interim for display.
      final display = '${_finalText}$_interimText'.trim();
      if (display.isNotEmpty &&
          _transcriptController != null &&
          !_transcriptController!.isClosed) {
        _transcriptController!.add(display);
      }
    } catch (e) {
      AppLogger.e('DeepgramStreamingService: parse error: $e');
    }
  }

  Future<String> _getApiKey() async {
    final userKey = await _keyStorage.getDeepgramApiKey();
    if (userKey != null && userKey.isNotEmpty) return userKey;
    return _defaultDeepgramKey;
  }

  void dispose() {
    stop();
  }
}
