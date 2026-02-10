import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/error/exceptions.dart';
import '../../core/utils/logger.dart';
import '../../domain/repositories/voice_repository.dart';

/// Data source for voice operations using platform channels.
/// 
/// Interfaces with Android's SpeechRecognizer and TextToSpeech APIs
/// through method channels.
abstract class VoiceDataSource {
  Future<bool> isSpeechRecognitionAvailable();
  Future<bool> isTextToSpeechAvailable();
  Future<List<VoiceLanguage>> getAvailableRecognitionLanguages();
  Future<List<VoiceLanguage>> getAvailableSynthesisLanguages();
  Stream<SpeechRecognitionResult> startRecognition({
    required String language,
    bool continuous,
    bool preferOffline,
    bool offlineOnly,
  });
  Future<void> stopRecognition();
  Future<void> cancelRecognition();
  Future<void> synthesize({
    required String text,
    required String language,
    double pitch,
    double rate,
  });
  Future<void> stopSynthesis();
  Stream<SpeechSynthesisEvent> get synthesisEvents;
  bool get isSpeaking;
  bool get isListening;
}

/// Implementation using method channels.
class VoiceDataSourceImpl with Loggable implements VoiceDataSource {
  static const _sttChannel = MethodChannel('com.microllm.app/stt');
  static const _ttsChannel = MethodChannel('com.microllm.app/tts');
  static const _sttEventChannel = EventChannel('com.microllm.app/stt_events');
  
  bool _isListening = false;
  bool _isSpeaking = false;
  StreamSubscription? _sttSubscription;
  StreamController<SpeechRecognitionResult>? _sttController;
  final StreamController<SpeechSynthesisEvent> _ttsEventsController =
      StreamController<SpeechSynthesisEvent>.broadcast();

  String? _lastLanguage;
  bool _lastContinuous = false;
  bool _didFallbackToOnline = false;
  bool _lastPreferOffline = true;
  bool _offlineOnly = false;
  int _consecutiveNoMatch = 0;
  bool _restartScheduled = false; // guard against double restarts
  static const int _maxConsecutiveNoMatch = 30; // stop after ~60s of silence
  
  VoiceDataSourceImpl() {
    // Set up TTS completion callback
    _ttsChannel.setMethodCallHandler(_handleTtsCallback);
  }
  
  Future<dynamic> _handleTtsCallback(MethodCall call) async {
    switch (call.method) {
      case 'onTtsComplete':
        _isSpeaking = false;
        _ttsEventsController.add(const SpeechSynthesisCompleted());
        break;
      case 'onTtsError':
        _isSpeaking = false;
        final message = call.arguments?.toString() ?? 'Speech synthesis error';
        logger.e('TTS error: $message');
        _ttsEventsController.add(SpeechSynthesisError(message));
        break;
    }
    return null;
  }
  
  @override
  Future<bool> isSpeechRecognitionAvailable() async {
    try {
      final result = await _sttChannel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } on PlatformException catch (e) {
      logger.w('STT availability check failed: $e');
      return false;
    }
  }
  
  @override
  Future<bool> isTextToSpeechAvailable() async {
    try {
      final result = await _ttsChannel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } on PlatformException catch (e) {
      logger.w('TTS availability check failed: $e');
      return false;
    }
  }
  
  @override
  Future<List<VoiceLanguage>> getAvailableRecognitionLanguages() async {
    try {
      final result = await _sttChannel.invokeMethod<List>('getLanguages');
      
      if (result == null) return [];
      
      return result.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return VoiceLanguage(
          code: map['code'] as String,
          displayName: map['displayName'] as String,
          isDefault: map['isDefault'] as bool? ?? false,
        );
      }).toList();
    } on PlatformException catch (e) {
      logger.e('Failed to get STT languages: $e');
      return [];
    }
  }
  
  @override
  Future<List<VoiceLanguage>> getAvailableSynthesisLanguages() async {
    try {
      final result = await _ttsChannel.invokeMethod<List>('getLanguages');
      
      if (result == null) return [];
      
      return result.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return VoiceLanguage(
          code: map['code'] as String,
          displayName: map['displayName'] as String,
          isDefault: map['isDefault'] as bool? ?? false,
        );
      }).toList();
    } on PlatformException catch (e) {
      logger.e('Failed to get TTS languages: $e');
      return [];
    }
  }
  
  @override
  Stream<SpeechRecognitionResult> startRecognition({
    required String language,
    bool continuous = false,
    bool preferOffline = true,
    bool offlineOnly = false,
  }) {
    // Cancel any existing recognition
    _cancelCurrentRecognition();
    
    _sttController = StreamController<SpeechRecognitionResult>();
    _isListening = true;
    _lastLanguage = language;
    _lastContinuous = continuous;
    _didFallbackToOnline = false;
    _lastPreferOffline = preferOffline;
    _offlineOnly = offlineOnly;
    _consecutiveNoMatch = 0;
    _restartScheduled = false;
    
    // Start recognition on platform
    _sttChannel.invokeMethod('start', {
      'language': language,
      'continuous': continuous,
      // Offline-first; we'll auto-fallback if offline pack missing.
      'preferOffline': preferOffline,
    }).catchError((error) {
      _sttController?.addError(VoiceException(
        message: 'Failed to start recognition: $error',
      ));
      _isListening = false;
    });
    
    // Listen for events from platform
    _sttSubscription = _sttEventChannel
        .receiveBroadcastStream()
        .listen(
          _handleSttEvent,
          onError: (error) {
            final errObj = error is Object
                ? error
                : VoiceException(message: error?.toString() ?? 'Speech recognition error');
            _sttController?.addError(errObj);
            _isListening = false;
          },
          onDone: () {
            _isListening = false;
            _sttController?.close();
          },
        );
    
    return _sttController!.stream;
  }
  
  void _handleSttEvent(dynamic event) {
    if (event == null) return;
    final controller = _sttController;
    if (controller == null || controller.isClosed) return;
    
    final map = Map<String, dynamic>.from(event as Map);
    final eventType = map['type'] as String;
    
    switch (eventType) {
      case 'result':
        if (controller.isClosed) return;
        final text = map['text'] as String;
        final isFinal = map['isFinal'] as bool;
        controller.add(SpeechRecognitionResult(
          text: text,
          confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
          isFinal: isFinal,
          alternatives: (map['alternatives'] as List?)
              ?.map((e) => e as String)
              .toList() ?? [],
        ));
        
        // Reset backoff counter — we got real speech.
        if (text.isNotEmpty) _consecutiveNoMatch = 0;

        if (isFinal) {
          if (_lastContinuous && _lastLanguage != null) {
            // In continuous mode, restart the recognizer for the next
            // utterance instead of closing the stream.
            _isListening = false;
            _restartForContinuous();
          } else {
            _isListening = false;
            if (!controller.isClosed) {
              controller.close();
            }
          }
        }
        break;

      case 'rms':
        // Voice level updates for UI animations
        if (controller.isClosed) return;
        controller.add(SpeechRecognitionResult(
          text: '',
          confidence: 0.0,
          isFinal: false,
          alternatives: const [],
          levelDb: (map['rmsDb'] as num?)?.toDouble(),
        ));
        break;
        
      case 'error':
        final code = (map['code'] as num?)?.toInt();
        final message = map['message'] as String? ?? 'Speech recognition error';

        // Auto-fallback: if offline pack is missing (or OEM-specific errors like code 13),
        // retry once without offline preference.
        final isPermissionError = code == 9; // SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS
        final looksLikeOfflinePackMissing =
            message.toLowerCase().contains('language pack') ||
            message.toLowerCase().contains('offline');

        final shouldFallback = !_offlineOnly &&
            !_didFallbackToOnline &&
            _lastPreferOffline &&
            !isPermissionError &&
            (_lastLanguage != null) &&
            (
              code == 5 /* ERROR_CLIENT */ ||
              code == 13 /* OEM / Soda pack error */ ||
              looksLikeOfflinePackMissing
            );

        if (shouldFallback && _lastLanguage != null) {
          _didFallbackToOnline = true;
          logger.w('STT offline failed ($message). Retrying with online recognition...');
          _lastPreferOffline = false;
          _sttChannel.invokeMethod('start', {
            'language': _lastLanguage,
            'continuous': _lastContinuous,
            'preferOffline': false,
          });
          return;
        }

        // In continuous mode, recoverable errors should silently restart
        // the recognizer instead of killing the session.
        final isRecoverableForContinuous =
            code == 6 /* ERROR_SPEECH_TIMEOUT */ ||
            code == 7 /* ERROR_NO_MATCH */ ||
            code == 5 /* ERROR_CLIENT (transient) */ ||
            code == 8 /* ERROR_RECOGNIZER_BUSY */ ||
            code == 11 /* ERROR_LANGUAGE_NOT_SUPPORTED (concurrent start race) */ ||
            code == 13 /* OEM / Soda pack error (Samsung, etc.) */;

        if (_lastContinuous &&
            isRecoverableForContinuous &&
            _lastLanguage != null) {
          _consecutiveNoMatch++;

          // Safety cap: stop restart loop after prolonged silence.
          if (_consecutiveNoMatch >= _maxConsecutiveNoMatch) {
            logger.w('STT continuous: too many consecutive no-match errors '
                '($_consecutiveNoMatch), stopping.');
            if (!controller.isClosed) {
              controller.addError(VoiceException(
                message: 'No speech detected for a long time. '
                    'Recording stopped automatically.',
                isRecoverable: true,
              ));
            }
            _isListening = false;
            return;
          }

          // Use exponential backoff: 500ms → 1s → 2s → max 3s
          final delayMs = (500 * (_consecutiveNoMatch.clamp(1, 6))).clamp(500, 3000);
          logger.d('STT continuous: recoverable error ($message), '
              'restart in ${delayMs}ms (attempt $_consecutiveNoMatch)');
          _isListening = false;
          _restartForContinuous(delayMs: delayMs);
          return;
        }

        if (controller.isClosed) return;
        final offlineTip =
            'Tip: For offline STT, install the offline speech pack for this language in Android settings.';
        controller.addError(VoiceException(
          message: _offlineOnly
              ? '$message\n\n$offlineTip'
              : (_didFallbackToOnline ? '$message\n\n$offlineTip' : message),
          isRecoverable: map['isRecoverable'] as bool? ?? false,
        ));
        _isListening = false;
        break;
        
      case 'ready':
        logger.d('STT ready');
        break;
        
      case 'end':
        // In continuous mode, 'end' fires BEFORE 'result' — do NOT restart
        // here. The restart happens from the 'result' (isFinal) or 'error'
        // handler to avoid duplicate restarts.
        _isListening = false;
        if (!_lastContinuous && !controller.isClosed) {
          controller.close();
        }
        break;
    }
  }
  
  /// Restart recognition after a delay for continuous listening.
  ///
  /// Android's SpeechRecognizer is single-shot — it stops after each
  /// utterance. This method recreates the recognizer so it keeps listening
  /// until the caller explicitly stops/cancels.
  ///
  /// Uses [_restartScheduled] guard to prevent multiple concurrent restarts
  /// (onEndOfSpeech + onResults + onError can all fire for the same utterance).
  void _restartForContinuous({int delayMs = 300}) {
    // Prevent duplicate restarts — only one may be scheduled at a time.
    if (_restartScheduled) return;
    _restartScheduled = true;

    Future.delayed(Duration(milliseconds: delayMs), () {
      _restartScheduled = false;

      final controller = _sttController;
      if (controller == null || controller.isClosed) return;
      // Don't restart if the user already stopped.
      if (!_lastContinuous) return;

      logger.d('STT continuous: restarting recognizer for next utterance...');
      _sttChannel.invokeMethod('start', {
        'language': _lastLanguage,
        'continuous': _lastContinuous,
        'preferOffline': _lastPreferOffline,
      }).catchError((error) {
        if (controller.isClosed) return;
        controller.addError(VoiceException(
          message: 'Failed to restart recognition: $error',
        ));
      });
      _isListening = true;
    });
  }

  @override
  Future<void> stopRecognition() async {
    _lastContinuous = false; // Prevent auto-restart after stop.
    _restartScheduled = false;
    try {
      await _sttChannel.invokeMethod('stop');
    } on PlatformException catch (e) {
      logger.e('Failed to stop recognition: $e');
    }
    _isListening = false;
  }
  
  @override
  Future<void> cancelRecognition() async {
    _lastContinuous = false; // Prevent auto-restart after cancel.
    _restartScheduled = false;
    _cancelCurrentRecognition();
    try {
      await _sttChannel.invokeMethod('cancel');
    } on PlatformException catch (e) {
      logger.e('Failed to cancel recognition: $e');
    }
    _isListening = false;
  }
  
  void _cancelCurrentRecognition() {
    _sttSubscription?.cancel();
    _sttSubscription = null;
    _sttController?.close();
    _sttController = null;
    _isListening = false;
  }
  
  @override
  Future<void> synthesize({
    required String text,
    required String language,
    double pitch = 1.0,
    double rate = 1.0,
  }) async {
    // Stop any ongoing synthesis
    await stopSynthesis();
    
    try {
      _isSpeaking = true;
      await _ttsChannel.invokeMethod('speak', {
        'text': text,
        'language': language,
        'pitch': pitch.clamp(0.5, 2.0),
        'rate': rate.clamp(0.5, 2.0),
      });
    } on PlatformException catch (e) {
      _isSpeaking = false;
      throw VoiceException(
        message: 'TTS synthesis failed: $e',
        isRecoverable: true,
      );
    }
  }
  
  @override
  Future<void> stopSynthesis() async {
    try {
      await _ttsChannel.invokeMethod('stop');
    } on PlatformException catch (e) {
      logger.e('Failed to stop synthesis: $e');
    }
    _isSpeaking = false;
  }

  @override
  Stream<SpeechSynthesisEvent> get synthesisEvents => _ttsEventsController.stream;
  
  @override
  bool get isSpeaking => _isSpeaking;
  
  @override
  bool get isListening => _isListening;
}
