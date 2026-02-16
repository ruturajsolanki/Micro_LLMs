import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/error/exceptions.dart';
import '../../core/utils/logger.dart';
import '../../domain/repositories/voice_repository.dart';

/// Data source for whisper.cpp offline STT via platform channels.
abstract class WhisperDataSource {
  Future<bool> isAvailable();
  Future<bool> isModelLoaded();
  Future<bool> loadModel({required String modelPath, required int threads});
  Future<void> unloadModel();

  /// Start recognition.
  ///
  /// If [continuous] is true, the recognizer will automatically restart
  /// after each utterance finishes, accumulating transcript across multiple
  /// recording segments. This is essential for the voice benchmark flow
  /// where users speak for 2–3 minutes.
  Stream<SpeechRecognitionResult> startRecognition({
    required String language,
    bool translateToEnglish,
    bool continuous,
  });

  Future<void> stopRecognition();
  Future<void> cancelRecognition();

  bool get isListening;
}

class WhisperDataSourceImpl with Loggable implements WhisperDataSource {
  static const _channel = MethodChannel('com.microllm.app/whisper');
  static const _events = EventChannel('com.microllm.app/whisper_events');

  bool _isListening = false;
  bool _continuous = false;
  bool _stopRequested = false;
  String _lastLanguage = 'en';
  bool _lastTranslate = false;
  StreamSubscription<dynamic>? _sub;
  StreamController<SpeechRecognitionResult>? _controller;

  @override
  bool get isListening => _isListening;

  @override
  Future<bool> isAvailable() async {
    try {
      final ok = await _channel.invokeMethod<bool>('isAvailable');
      return ok ?? false;
    } on PlatformException catch (e) {
      logger.w('Whisper availability check failed: $e');
      return false;
    }
  }

  @override
  Future<bool> isModelLoaded() async {
    try {
      final ok = await _channel.invokeMethod<bool>('isModelLoaded');
      return ok ?? false;
    } on PlatformException catch (e) {
      logger.w('Whisper model-loaded check failed: $e');
      return false;
    }
  }

  @override
  Future<bool> loadModel({required String modelPath, required int threads}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('loadModel', {
        'modelPath': modelPath,
        'threads': threads,
      });
      return ok ?? false;
    } on PlatformException catch (e, stack) {
      logger.e('Whisper loadModel failed', error: e, stackTrace: stack);
      throw VoiceException(message: e.message ?? 'Whisper loadModel failed');
    }
  }

  @override
  Future<void> unloadModel() async {
    try {
      await _channel.invokeMethod('unloadModel');
    } on PlatformException catch (e) {
      logger.w('Whisper unloadModel failed: $e');
    }
  }

  @override
  Stream<SpeechRecognitionResult> startRecognition({
    required String language,
    bool translateToEnglish = false,
    bool continuous = false,
  }) {
    _cancelCurrent();
    _controller = StreamController<SpeechRecognitionResult>();
    _isListening = true;
    _continuous = continuous;
    _stopRequested = false;
    _lastLanguage = language;
    _lastTranslate = translateToEnglish;

    _startNativeRecognition(language, translateToEnglish, subscribeEvents: true);

    return _controller!.stream;
  }

  /// Start the native Whisper recognition session and listen for events.
  ///
  /// If [subscribeEvents] is true, a new EventChannel subscription is created.
  /// On restarts in continuous mode, we pass false to reuse the existing subscription
  /// since the EventChannel eventSink stays valid as long as we don't cancel.
  void _startNativeRecognition(
    String language,
    bool translateToEnglish, {
    bool subscribeEvents = false,
  }) {
    // Subscribe to the EventChannel FIRST so the native eventSink is
    // established before we invoke 'start'. This prevents a race where
    // early events (e.g. "ready", "rms") are emitted before onListen fires.
    if (subscribeEvents) {
      _sub?.cancel();
      _sub = _events.receiveBroadcastStream().listen(
        _handleEvent,
        onError: (Object error) {
          _controller?.addError(
            error is Exception
                ? error
                : VoiceException(message: error.toString()),
          );
          // In continuous mode, try to restart after a brief delay.
          if (_continuous && !_stopRequested) {
            _scheduleRestart();
          } else {
            _isListening = false;
          }
        },
        onDone: () {
          // EventChannel stream closed — if in continuous mode, restart.
          if (_continuous && !_stopRequested) {
            _scheduleRestart();
          } else {
            _isListening = false;
            _controller?.close();
          }
        },
      );
    }

    // Now start the native recognizer.
    _channel.invokeMethod('start', {
      'language': language,
      'translateToEnglish': translateToEnglish,
    }).catchError((Object error) {
      _controller?.addError(
        VoiceException(message: 'Failed to start Whisper STT: $error'),
      );
      _isListening = false;
    });
  }

  void _handleEvent(dynamic event) {
    if (event == null) return;
    final controller = _controller;
    if (controller == null || controller.isClosed) return;

    final map = Map<String, dynamic>.from(event as Map);
    final type = map['type'] as String?;
    switch (type) {
      case 'result':
        controller.add(SpeechRecognitionResult(
          text: map['text'] as String? ?? '',
          confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
          isFinal: map['isFinal'] as bool? ?? false,
          alternatives: (map['alternatives'] as List?)
                  ?.map((e) => e as String)
                  .toList() ??
              const [],
        ));

        if (map['isFinal'] as bool? ?? false) {
          // Utterance complete.
          if (_continuous && !_stopRequested) {
            // In continuous mode: restart for the next utterance.
            // Don't close the stream — keep it open for the caller.
            logger.i('Whisper continuous: utterance done, restarting…');
            _scheduleRestart();
          } else {
            _isListening = false;
            if (!controller.isClosed) controller.close();
          }
        }
        break;

      case 'rms':
        controller.add(SpeechRecognitionResult(
          text: '',
          confidence: 0.0,
          isFinal: false,
          alternatives: const [],
          levelDb: (map['rmsDb'] as num?)?.toDouble(),
        ));
        break;

      case 'error':
        final message = map['message'] as String? ?? 'Whisper STT error';
        final isRecoverable =
            map['isRecoverable'] as bool? ?? false;

        if (_continuous && !_stopRequested && isRecoverable) {
          // Recoverable error in continuous mode — try restarting.
          logger.w('Whisper continuous: recoverable error ($message), restarting…');
          _scheduleRestart();
        } else {
          controller.addError(VoiceException(message: message));
          _isListening = false;
          if (!controller.isClosed) controller.close();
        }
        break;

      case 'ready':
        // Whisper native side is ready to receive audio — no action needed.
        break;

      case 'end':
        // Native recording phase ended (audio capture done, transcription starts).
        // In continuous mode, the restart happens on the 'result' isFinal event.
        break;
    }
  }

  /// Schedule a restart of the native recognizer after a brief delay.
  ///
  /// The delay gives the native AudioRecord time to release resources
  /// before we create a new one.
  void _scheduleRestart() {
    if (_stopRequested) return;
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (_stopRequested || _controller == null || _controller!.isClosed) return;
      logger.i('Whisper continuous: restarting recognizer…');
      // Don't re-subscribe to events — the EventChannel is still active.
      _startNativeRecognition(_lastLanguage, _lastTranslate, subscribeEvents: true);
    });
  }

  @override
  Future<void> stopRecognition() async {
    _stopRequested = true;
    _continuous = false;
    try {
      await _channel.invokeMethod('stop');
    } finally {
      _isListening = false;
    }
  }

  @override
  Future<void> cancelRecognition() async {
    _stopRequested = true;
    _continuous = false;
    try {
      await _channel.invokeMethod('cancel');
    } finally {
      _isListening = false;
    }
  }

  void _cancelCurrent() {
    _stopRequested = true;
    _continuous = false;
    _sub?.cancel();
    _sub = null;
    _controller?.close();
    _controller = null;
    _isListening = false;
  }
}

