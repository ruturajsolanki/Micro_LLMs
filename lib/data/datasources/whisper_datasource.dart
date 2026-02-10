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

  Stream<SpeechRecognitionResult> startRecognition({
    required String language,
    bool translateToEnglish,
  });

  Future<void> stopRecognition();
  Future<void> cancelRecognition();

  bool get isListening;
}

class WhisperDataSourceImpl with Loggable implements WhisperDataSource {
  static const _channel = MethodChannel('com.microllm.app/whisper');
  static const _events = EventChannel('com.microllm.app/whisper_events');

  bool _isListening = false;
  StreamSubscription? _sub;
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
  }) {
    _cancelCurrent();
    _controller = StreamController<SpeechRecognitionResult>();
    _isListening = true;

    _channel.invokeMethod('start', {
      'language': language,
      'translateToEnglish': translateToEnglish,
    }).catchError((error) {
      _controller?.addError(VoiceException(message: 'Failed to start Whisper STT: $error'));
      _isListening = false;
    });

    _sub = _events.receiveBroadcastStream().listen(
      _handleEvent,
      onError: (error) {
        final errObj = error is Object
            ? error
            : VoiceException(message: error?.toString() ?? 'Whisper STT error');
        _controller?.addError(errObj);
        _isListening = false;
      },
      onDone: () {
        _isListening = false;
        _controller?.close();
      },
    );

    return _controller!.stream;
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
          alternatives: (map['alternatives'] as List?)?.map((e) => e as String).toList() ?? const [],
        ));

        if (map['isFinal'] as bool? ?? false) {
          _isListening = false;
          if (!controller.isClosed) controller.close();
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
        controller.addError(VoiceException(message: message));
        _isListening = false;
        if (!controller.isClosed) controller.close();
        break;

      case 'end':
        // No-op (we emit SpeechToTextStopped at usecase level once stream finishes)
        break;
    }
  }

  @override
  Future<void> stopRecognition() async {
    try {
      await _channel.invokeMethod('stop');
    } finally {
      _isListening = false;
    }
  }

  @override
  Future<void> cancelRecognition() async {
    try {
      await _channel.invokeMethod('cancel');
    } finally {
      _isListening = false;
    }
  }

  void _cancelCurrent() {
    _sub?.cancel();
    _sub = null;
    _controller?.close();
    _controller = null;
    _isListening = false;
  }
}

