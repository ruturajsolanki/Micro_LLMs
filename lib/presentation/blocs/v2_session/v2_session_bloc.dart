import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/utils/logger.dart';
import '../../../data/datasources/audio_recorder_service.dart';
import '../../../data/datasources/v2_session_storage.dart';
import '../../../data/repositories/cloud_llm_repository_impl.dart';
import '../../../data/services/cloud_api_key_storage.dart';
import '../../../data/services/cloud_connectivity_checker.dart';
import '../../../data/services/deepgram_streaming_service.dart';
import '../../../data/services/groq_api_service.dart';
import '../../../domain/entities/benchmark_result.dart';
import '../../../domain/entities/cloud_provider.dart';
import '../../../domain/entities/evaluation_result.dart';
import '../../../domain/entities/inference_request.dart';
import '../../../domain/entities/v2_session_record.dart';
import '../../../domain/services/system_prompt_manager.dart';

part 'v2_session_event.dart';
part 'v2_session_state.dart';

/// BLoC for the V2 cloud-first voice evaluation flow.
///
/// State machine: checking → ready → recording → transcribing → evaluating → completed
class V2SessionBloc extends Bloc<V2SessionEvent, V2SessionState> {
  final CloudConnectivityChecker _connectivityChecker;
  final CloudApiKeyStorage _keyStorage;
  final GroqApiService _groqApi;
  final CloudLLMRepositoryImpl _cloudLlmRepo;
  final AudioRecorderService _audioRecorder;
  final SystemPromptManager _promptManager;
  final V2SessionStorage _sessionStorage;
  final DeepgramStreamingService _deepgramService;

  Timer? _timer;
  String? _currentAudioPath;
  StreamSubscription<List<int>>? _audioChunkSub;
  StreamSubscription<String>? _deepgramTranscriptSub;

  V2SessionBloc({
    required CloudConnectivityChecker connectivityChecker,
    required CloudApiKeyStorage keyStorage,
    required GroqApiService groqApi,
    required CloudLLMRepositoryImpl cloudLlmRepo,
    required AudioRecorderService audioRecorder,
    required SystemPromptManager promptManager,
    required V2SessionStorage sessionStorage,
    required DeepgramStreamingService deepgramService,
  })  : _connectivityChecker = connectivityChecker,
        _keyStorage = keyStorage,
        _groqApi = groqApi,
        _cloudLlmRepo = cloudLlmRepo,
        _audioRecorder = audioRecorder,
        _promptManager = promptManager,
        _sessionStorage = sessionStorage,
        _deepgramService = deepgramService,
        super(const V2SessionState()) {
    on<V2CloudCheckRequested>(_onCloudCheck);
    on<V2RecordingStarted>(_onRecordingStarted);
    on<V2RecordingStopped>(_onRecordingStopped);
    on<V2AudioFileSelected>(_onAudioFileSelected);
    on<V2LiveTranscriptUpdated>(_onLiveTranscriptUpdated);
    on<V2SessionReset>(_onReset);
    on<V2TimerTicked>(_onTimerTicked);
  }

  // ── Cloud check ─────────────────────────────────────────────────

  Future<void> _onCloudCheck(
    V2CloudCheckRequested event,
    Emitter<V2SessionState> emit,
  ) async {
    emit(state.copyWith(status: V2SessionStatus.checking));

    try {
      // The storage always returns a key (user key or built-in default).
      final status = await _connectivityChecker.checkAny();
      if (status.isReady) {
        // Key works — go straight to ready.
        emit(state.copyWith(
          status: V2SessionStatus.ready,
          cloudReady: true,
        ));
      } else {
        // Key validation failed (quota exceeded / revoked / no network).
        // If using the default key, prompt user to enter their own.
        final usingDefault = await _keyStorage.isUsingDefaultGroqKey();
        if (usingDefault) {
          AppLogger.w(
            'V2SessionBloc: default API key failed, '
            'asking user for their own key.',
          );
          emit(state.copyWith(
            status: V2SessionStatus.needsSetup,
            cloudReady: false,
            errorMessage: status.error ??
                'Built-in API key is unavailable. Please enter your own.',
          ));
        } else {
          // User has their own key but it failed — still let them try.
          emit(state.copyWith(
            status: V2SessionStatus.needsSetup,
            cloudReady: false,
            errorMessage: status.error ??
                'API key validation failed. Please check your key.',
          ));
        }
      }
    } catch (e) {
      // Network error — still go to needsSetup so user can retry.
      emit(state.copyWith(
        status: V2SessionStatus.needsSetup,
        cloudReady: false,
        errorMessage: 'Connectivity check failed: $e',
      ));
    }
  }

  // ── Recording start ─────────────────────────────────────────────

  Future<void> _onRecordingStarted(
    V2RecordingStarted event,
    Emitter<V2SessionState> emit,
  ) async {
    try {
      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentAudioPath = '${dir.path}/v2_recording_$timestamp.wav';

      await _audioRecorder.startRecording(outputPath: _currentAudioPath!);

      _timer?.cancel();
      var seconds = 0;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        seconds++;
        add(V2TimerTicked(seconds));
      });

      emit(state.copyWith(
        status: V2SessionStatus.recording,
        recordingSeconds: 0,
        audioSource: 'mic',
        uploadedFileName: null,
        transcript: null,
        liveTranscript: null,
        evaluationResult: null,
        benchmarkResult: null,
        errorMessage: null,
      ));

      // Start Deepgram live transcription.
      _startDeepgramStreaming();
    } catch (e) {
      emit(state.copyWith(
        status: V2SessionStatus.error,
        errorMessage: 'Failed to start recording: $e',
      ));
    }
  }

  /// Start Deepgram WebSocket and pipe audio chunks into it.
  void _startDeepgramStreaming() {
    _deepgramService.start().then((_) {
      // Listen for transcript updates from Deepgram.
      _deepgramTranscriptSub =
          _deepgramService.transcriptStream?.listen((text) {
        add(V2LiveTranscriptUpdated(text));
      });

      // Pipe audio chunks from native recorder to Deepgram.
      _audioChunkSub = _audioRecorder.audioChunkStream.listen((chunk) {
        _deepgramService.addAudioData(chunk);
      });

      AppLogger.i('V2SessionBloc: Deepgram streaming started');
    }).catchError((e) {
      AppLogger.e('V2SessionBloc: failed to start Deepgram: $e');
      // Non-fatal — recording continues without live transcript.
    });
  }

  /// Stop Deepgram WebSocket and clean up subscriptions.
  Future<void> _stopDeepgramStreaming() async {
    await _audioChunkSub?.cancel();
    _audioChunkSub = null;
    await _deepgramTranscriptSub?.cancel();
    _deepgramTranscriptSub = null;
    await _deepgramService.stop();
  }

  void _onLiveTranscriptUpdated(
    V2LiveTranscriptUpdated event,
    Emitter<V2SessionState> emit,
  ) {
    if (state.status == V2SessionStatus.recording) {
      emit(state.copyWith(liveTranscript: event.text));
    }
  }

  void _onTimerTicked(
    V2TimerTicked event,
    Emitter<V2SessionState> emit,
  ) {
    if (state.status == V2SessionStatus.recording) {
      emit(state.copyWith(recordingSeconds: event.elapsedSeconds));
    }
  }

  // ── Recording stop → transcribe → evaluate ──────────────────────

  Future<void> _onRecordingStopped(
    V2RecordingStopped event,
    Emitter<V2SessionState> emit,
  ) async {
    _timer?.cancel();
    _timer = null;

    // Stop Deepgram live transcription first.
    await _stopDeepgramStreaming();

    final audioPath = await _audioRecorder.stopRecording();
    if (audioPath == null || _currentAudioPath == null) {
      emit(state.copyWith(
        status: V2SessionStatus.error,
        errorMessage: 'No audio recorded.',
      ));
      return;
    }

    // Reject very short recordings (accidental tap).
    if (state.recordingSeconds < 3) {
      emit(state.copyWith(
        status: V2SessionStatus.error,
        errorMessage:
            'Recording too short (${state.recordingSeconds}s). '
            'Please speak for at least a few seconds.',
      ));
      // Clean up the temp file.
      try {
        final f = File(_currentAudioPath!);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      return;
    }

    // Allow WAV header rewrite to fully flush to disk.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    await _processAudioFile(
      emit: emit,
      audioFilePath: _currentAudioPath!,
      audioSource: 'mic',
      recordingSeconds: state.recordingSeconds,
    );
  }

  // ── Audio file upload → transcribe → evaluate ───────────────────

  Future<void> _onAudioFileSelected(
    V2AudioFileSelected event,
    Emitter<V2SessionState> emit,
  ) async {
    emit(state.copyWith(
      audioSource: 'upload',
      uploadedFileName: event.fileName,
      recordingSeconds: 0,
      transcript: null,
      liveTranscript: null,
      evaluationResult: null,
      benchmarkResult: null,
      errorMessage: null,
    ));

    await _processAudioFile(
      emit: emit,
      audioFilePath: event.filePath,
      audioSource: 'upload',
      uploadedFileName: event.fileName,
      recordingSeconds: 0,
    );
  }

  // ── Shared pipeline: transcribe + evaluate ──────────────────────

  Future<void> _processAudioFile({
    required Emitter<V2SessionState> emit,
    required String audioFilePath,
    required String audioSource,
    String? uploadedFileName,
    int recordingSeconds = 0,
  }) async {
    final file = File(audioFilePath);
    if (!file.existsSync() || file.lengthSync() < 100) {
      emit(state.copyWith(
        status: V2SessionStatus.error,
        errorMessage: 'Audio file is too small or missing.',
      ));
      return;
    }

    final processingStart = DateTime.now();

    // ── Step 1: Transcription ──────────────────────────────────────
    emit(state.copyWith(
      status: V2SessionStatus.transcribing,
      processingStep: 'Transcribing audio...',
    ));

    String transcript;
    try {
      if (state.sttProvider == CloudSttProvider.groqWhisper &&
          state.cloudReady) {
        final key = await _keyStorage.getGroqApiKey();
        if (key == null || key.isEmpty) {
          emit(state.copyWith(
            status: V2SessionStatus.error,
            errorMessage: 'Groq API key not found.',
          ));
          return;
        }

        final sttResult = await _groqApi.transcribeAudio(
          apiKey: key,
          audioFilePath: audioFilePath,
          language: 'en',
        );
        transcript = sttResult.text.trim();

        // If uploaded file, estimate duration from audio metadata
        if (audioSource == 'upload' && sttResult.audioDurationSeconds > 0) {
          recordingSeconds = sttResult.audioDurationSeconds.round();
        }
      } else {
        emit(state.copyWith(
          status: V2SessionStatus.error,
          errorMessage: 'Local Whisper fallback not implemented in V2 yet. '
              'Please configure a Groq API key.',
        ));
        return;
      }
    } catch (e) {
      AppLogger.e('V2SessionBloc: transcription failed: $e');
      emit(state.copyWith(
        status: V2SessionStatus.error,
        errorMessage: 'Transcription failed: $e',
      ));
      return;
    }

    // ── Reject if no meaningful speech was detected ──────────────────
    final wordCount =
        transcript.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    if (transcript.isEmpty || wordCount < 3) {
      emit(state.copyWith(
        status: V2SessionStatus.error,
        errorMessage: transcript.isEmpty
            ? 'No speech detected in the audio.'
            : 'Too few words detected ($wordCount). '
                'Please speak for at least a few sentences.',
      ));
      return;
    }

    emit(state.copyWith(
      transcript: transcript,
      recordingSeconds: recordingSeconds,
      status: V2SessionStatus.evaluating,
      processingStep: 'Evaluating transcript...',
    ));

    // ── Step 2: Cloud LLM Evaluation ───────────────────────────────
    try {
      _cloudLlmRepo.setProvider(state.llmProvider);
      if (!_cloudLlmRepo.isModelLoaded) {
        await _cloudLlmRepo.loadModel(modelPath: 'cloud');
      }

      final systemPrompt = _promptManager.getPrompt(
        SystemPromptKey.cloudEvaluation,
      );

      final evalPrompt =
          'Evaluate the following spoken transcript:\n\n$transcript';

      final request = InferenceRequest(
        prompt: evalPrompt,
        systemPrompt: systemPrompt,
        maxTokens: 1024,
        temperature: 0.2,
        stream: false,
        isolated: true,
      );

      final result = await _cloudLlmRepo.generate(request);

      final evalResult = result.fold(
        (failure) {
          AppLogger.e('V2SessionBloc: evaluation failed: ${failure.message}');
          return EvaluationResult.parseError(rawOutput: failure.message);
        },
        (response) {
          AppLogger.i(
              'V2SessionBloc: raw evaluation output:\n${response.text}');
          return _parseEvaluation(response.text);
        },
      );

      final processingTimeMs =
          DateTime.now().difference(processingStart).inMilliseconds;

      final benchmarkResult = BenchmarkResult(
        transcript: transcript,
        keyIdeas: '',
        summary: evalResult.overallFeedback,
        dimensions: const [],
        recordingDurationSeconds: recordingSeconds,
        processingTimeMs: processingTimeMs,
        promptUsed: 'V2 Cloud Evaluation',
        completedAt: DateTime.now(),
        evaluationResult: evalResult,
      );

      emit(state.copyWith(
        status: V2SessionStatus.completed,
        evaluationResult: evalResult,
        benchmarkResult: benchmarkResult,
        recordingSeconds: recordingSeconds,
        processingStep: null,
      ));

      // ── Persist audio file ──────────────────────────────────────────
      String? savedAudioPath;
      try {
        savedAudioPath =
            await _persistAudioFile(audioFilePath, audioSource);
      } catch (e) {
        AppLogger.w('V2SessionBloc: could not save audio: $e');
      }

      // ── Save to history ────────────────────────────────────────────
      _saveToHistory(
        evalResult: evalResult,
        transcript: transcript,
        recordingSeconds: recordingSeconds,
        processingTimeMs: processingTimeMs,
        audioSource: audioSource,
        uploadedFileName: uploadedFileName,
        audioFilePath: savedAudioPath,
      );
    } catch (e, stack) {
      AppLogger.e('V2SessionBloc: evaluation error: $e\n$stack');
      emit(state.copyWith(
        status: V2SessionStatus.error,
        errorMessage: 'Evaluation failed: $e',
      ));
    }
  }

  // ── Save to persistent history ──────────────────────────────────

  void _saveToHistory({
    required EvaluationResult evalResult,
    required String transcript,
    required int recordingSeconds,
    required int processingTimeMs,
    required String audioSource,
    String? uploadedFileName,
    String? audioFilePath,
  }) {
    try {
      final record = V2SessionRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        completedAt: DateTime.now(),
        recordingDurationSeconds: recordingSeconds,
        processingTimeMs: processingTimeMs,
        clarityScore: evalResult.clarityScore,
        languageScore: evalResult.languageScore,
        clarityReasoning: evalResult.clarityReasoning,
        languageReasoning: evalResult.languageReasoning,
        overallFeedback: evalResult.overallFeedback,
        safetyFlag: evalResult.safetyFlag,
        safetyNotes: evalResult.safetyNotes,
        transcript: transcript,
        llmProvider: state.llmProvider.id,
        sttProvider: state.sttProvider.id,
        audioSource: audioSource,
        uploadedFileName: uploadedFileName,
        audioFilePath: audioFilePath,
      );
      _sessionStorage.save(record);
    } catch (e) {
      AppLogger.e('V2SessionBloc: failed to save history: $e');
    }
  }

  /// Copy audio to a persistent app directory so it survives temp cleanup.
  Future<String?> _persistAudioFile(
    String sourcePath,
    String audioSource,
  ) async {
    final sourceFile = File(sourcePath);
    if (!sourceFile.existsSync()) return null;

    final appDir = await getApplicationDocumentsDirectory();
    final audioDir = Directory('${appDir.path}/v2_recordings');
    if (!audioDir.existsSync()) {
      audioDir.createSync(recursive: true);
    }

    final ext = sourcePath.split('.').last;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final destPath = '${audioDir.path}/session_$timestamp.$ext';

    if (audioSource == 'mic') {
      // Move (rename) temp file to persistent dir — faster than copy.
      try {
        final moved = await sourceFile.rename(destPath);
        return moved.path;
      } catch (_) {
        // rename fails across filesystems; fall back to copy + delete.
        final copied = await sourceFile.copy(destPath);
        await sourceFile.delete();
        return copied.path;
      }
    } else {
      // For uploaded files, copy so we don't remove the user's original.
      final copied = await sourceFile.copy(destPath);
      return copied.path;
    }
  }

  // ── Reset ───────────────────────────────────────────────────────

  Future<void> _onReset(
    V2SessionReset event,
    Emitter<V2SessionState> emit,
  ) async {
    _timer?.cancel();
    _timer = null;
    await _stopDeepgramStreaming();
    _audioRecorder.cancelRecording();
    emit(const V2SessionState(
        status: V2SessionStatus.ready, cloudReady: true));
  }

  // ── Parsing helpers ─────────────────────────────────────────────

  EvaluationResult _parseEvaluation(String raw) {
    try {
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
      if (jsonMatch == null) {
        return EvaluationResult.parseError(rawOutput: raw);
      }

      final jsonStr = jsonMatch.group(0)!;
      final map = _parseJson(jsonStr);
      if (map == null) {
        return EvaluationResult.parseError(rawOutput: raw);
      }

      return EvaluationResult(
        clarityScore: _toDouble(map['clarity_score']),
        clarityReasoning:
            (map['clarity_reasoning'] as String?) ?? 'No reasoning provided.',
        languageScore: _toDouble(map['language_score']),
        languageReasoning:
            (map['language_reasoning'] as String?) ?? 'No reasoning provided.',
        safetyFlag: (map['safety_flag'] as bool?) ?? false,
        safetyNotes: (map['safety_notes'] as String?) ?? 'None',
        overallFeedback:
            (map['overall_feedback'] as String?) ?? 'No feedback provided.',
      );
    } catch (e) {
      AppLogger.e('V2SessionBloc: parse error: $e');
      return EvaluationResult.parseError(rawOutput: raw);
    }
  }

  Map<String, dynamic>? _parseJson(String jsonStr) {
    try {
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    _stopDeepgramStreaming();
    return super.close();
  }
}
