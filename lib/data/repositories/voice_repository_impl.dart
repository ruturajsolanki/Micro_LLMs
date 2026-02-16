import 'package:dartz/dartz.dart';
import 'dart:async';

import '../../core/error/failures.dart';
import '../../core/utils/result.dart';
import '../../core/utils/logger.dart';
import '../../domain/repositories/voice_repository.dart';
import '../../domain/entities/speech_to_text_engine.dart';
import '../../domain/entities/text_to_speech_engine.dart';
import '../datasources/voice_datasource.dart';
import '../datasources/whisper_datasource.dart';
import '../services/elevenlabs_tts_service.dart';

/// Implementation of voice repository.
class VoiceRepositoryImpl with Loggable implements VoiceRepository {
  final VoiceDataSource _voiceDataSource;
  final WhisperDataSource _whisperDataSource;
  final ElevenLabsTtsService _elevenLabs;

  final StreamController<SpeechSynthesisEvent> _ttsEventsController =
      StreamController<SpeechSynthesisEvent>.broadcast();
  StreamSubscription<SpeechSynthesisEvent>? _platformTtsSub;
  bool _cloudSpeaking = false;
  
  VoiceRepositoryImpl({
    required VoiceDataSource voiceDataSource,
    required WhisperDataSource whisperDataSource,
    required ElevenLabsTtsService elevenLabsTtsService,
  })  : _voiceDataSource = voiceDataSource,
        _whisperDataSource = whisperDataSource,
        _elevenLabs = elevenLabsTtsService {
    // Forward platform TTS lifecycle events (Android TTS) to a unified stream.
    _platformTtsSub = _voiceDataSource.synthesisEvents.listen((e) {
      _ttsEventsController.add(e);
    });
  }
  
  @override
  AsyncResult<bool> isSpeechRecognitionAvailable() async {
    try {
      final available = await _voiceDataSource.isSpeechRecognitionAvailable();
      return Right(available);
    } catch (e, stack) {
      logger.e('STT availability check failed', error: e, stackTrace: stack);
      return Left(VoiceFailure(
        message: e.toString(),
        type: VoiceFailureType.sttUnavailable,
        stackTrace: stack,
      ));
    }
  }
  
  @override
  AsyncResult<bool> isTextToSpeechAvailable() async {
    try {
      final available = await _voiceDataSource.isTextToSpeechAvailable();
      return Right(available);
    } catch (e, stack) {
      logger.e('TTS availability check failed', error: e, stackTrace: stack);
      return Left(VoiceFailure(
        message: e.toString(),
        type: VoiceFailureType.ttsUnavailable,
        stackTrace: stack,
      ));
    }
  }
  
  @override
  AsyncResult<List<VoiceLanguage>> getAvailableRecognitionLanguages() async {
    try {
      final languages = await _voiceDataSource.getAvailableRecognitionLanguages();
      return Right(languages);
    } catch (e, stack) {
      logger.e('Failed to get STT languages', error: e, stackTrace: stack);
      return Left(VoiceFailure(
        message: e.toString(),
        type: VoiceFailureType.sttUnavailable,
        stackTrace: stack,
      ));
    }
  }
  
  @override
  AsyncResult<List<VoiceLanguage>> getAvailableSynthesisLanguages() async {
    try {
      final languages = await _voiceDataSource.getAvailableSynthesisLanguages();
      return Right(languages);
    } catch (e, stack) {
      logger.e('Failed to get TTS languages', error: e, stackTrace: stack);
      return Left(VoiceFailure(
        message: e.toString(),
        type: VoiceFailureType.ttsUnavailable,
        stackTrace: stack,
      ));
    }
  }
  
  @override
  Stream<SpeechRecognitionResult> startRecognition({
    required SpeechToTextEngine engine,
    required String language,
    bool continuous = false,
    bool preferOffline = true,
    bool offlineOnly = false,
    int whisperThreads = 4,
  }) {
    switch (engine) {
      case SpeechToTextEngine.androidSpeechRecognizer:
        return _voiceDataSource.startRecognition(
          language: language,
          continuous: continuous,
          preferOffline: preferOffline,
          offlineOnly: offlineOnly,
        );
      case SpeechToTextEngine.whisperCpp:
        // Model loading is handled by the usecase/repository helper.
        return _whisperDataSource.startRecognition(
          language: language,
          translateToEnglish: false,
          continuous: continuous,
        );
    }
  }

  @override
  AsyncResult<bool> isWhisperAvailable() async {
    try {
      final ok = await _whisperDataSource.isAvailable();
      return Right(ok);
    } catch (e, stack) {
      logger.e('Whisper availability check failed', error: e, stackTrace: stack);
      return Left(VoiceFailure(
        message: e.toString(),
        type: VoiceFailureType.sttUnavailable,
        stackTrace: stack,
      ));
    }
  }

  @override
  AsyncResult<bool> loadWhisperModel({
    required String modelPath,
    required int threads,
  }) async {
    try {
      final ok = await _whisperDataSource.loadModel(
        modelPath: modelPath,
        threads: threads,
      );
      return Right(ok);
    } catch (e, stack) {
      logger.e('Whisper loadModel failed', error: e, stackTrace: stack);
      return Left(VoiceFailure(
        message: e.toString(),
        type: VoiceFailureType.sttUnavailable,
        stackTrace: stack,
      ));
    }
  }

  @override
  Future<void> unloadWhisperModel() async {
    await _whisperDataSource.unloadModel();
  }

  @override
  AsyncResult<bool> isWhisperModelLoaded() async {
    try {
      final ok = await _whisperDataSource.isModelLoaded();
      return Right(ok);
    } catch (e, stack) {
      logger.e('Whisper model-loaded check failed', error: e, stackTrace: stack);
      return Left(VoiceFailure(
        message: e.toString(),
        type: VoiceFailureType.sttUnavailable,
        stackTrace: stack,
      ));
    }
  }
  
  @override
  Future<void> stopRecognition() async {
    // Stop both engines defensively; only one is typically active.
    try {
      await _voiceDataSource.stopRecognition();
    } catch (_) {}
    try {
      await _whisperDataSource.stopRecognition();
    } catch (_) {}
  }
  
  @override
  Future<void> cancelRecognition() async {
    try {
      await _voiceDataSource.cancelRecognition();
    } catch (_) {}
    try {
      await _whisperDataSource.cancelRecognition();
    } catch (_) {}
  }
  
  @override
  AsyncResult<void> synthesize({
    required TextToSpeechEngine engine,
    required String text,
    required String language,
    String? elevenLabsVoiceId,
    double pitch = 1.0,
    double rate = 1.0,
  }) async {
    try {
      switch (engine) {
        case TextToSpeechEngine.androidTts:
          await _voiceDataSource.synthesize(
            text: text,
            language: language,
            pitch: pitch,
            rate: rate,
          );
          break;
        case TextToSpeechEngine.elevenLabs:
          final voiceId = (elevenLabsVoiceId?.trim().isNotEmpty ?? false)
              ? elevenLabsVoiceId!.trim()
              : 'JBFqnCBsd6RMkjVDRZzb';

          // Start asynchronously; completion/error is delivered through synthesisEvents.
          _cloudSpeaking = true;
          unawaited(() async {
            try {
              await _elevenLabs.speak(
                text: text,
                voiceId: voiceId,
              );
              _cloudSpeaking = false;
              _ttsEventsController.add(const SpeechSynthesisCompleted());
            } catch (e) {
              _cloudSpeaking = false;
              _ttsEventsController.add(SpeechSynthesisError(e.toString()));
            }
          }());
          break;
      }
      return const Right(null);
    } catch (e, stack) {
      logger.e('TTS synthesis failed', error: e, stackTrace: stack);
      return Left(VoiceFailure(
        message: e.toString(),
        type: VoiceFailureType.synthesisError,
        stackTrace: stack,
      ));
    }
  }
  
  @override
  Future<void> stopSynthesis() async {
    try {
      await _voiceDataSource.stopSynthesis();
    } catch (_) {}
    try {
      await _elevenLabs.stop();
    } catch (_) {}
    _cloudSpeaking = false;
  }

  @override
  AsyncResult<void> setElevenLabsApiKey(String apiKey) async {
    try {
      await _elevenLabs.setApiKey(apiKey);
      return const Right(null);
    } catch (e, stack) {
      logger.e('Failed to store ElevenLabs API key', error: e, stackTrace: stack);
      return Left(VoiceFailure(
        message: e.toString(),
        type: VoiceFailureType.synthesisError,
        stackTrace: stack,
      ));
    }
  }

  @override
  AsyncResult<String?> getElevenLabsApiKey() async {
    try {
      final key = await _elevenLabs.getApiKey();
      return Right(key);
    } catch (e, stack) {
      return Left(VoiceFailure(
        message: e.toString(),
        type: VoiceFailureType.synthesisError,
        stackTrace: stack,
      ));
    }
  }

  @override
  Stream<SpeechSynthesisEvent> get synthesisEvents => _ttsEventsController.stream;
  
  @override
  bool get isSpeaking => _voiceDataSource.isSpeaking || _cloudSpeaking;
  
  @override
  bool get isListening => _voiceDataSource.isListening || _whisperDataSource.isListening;
}
