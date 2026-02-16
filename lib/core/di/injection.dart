import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/datasources/llm_native_datasource.dart';
import '../../data/datasources/llm_jni_datasource.dart';
import '../../data/datasources/llm_conversation_sync_datasource.dart';
import '../../data/datasources/voice_datasource.dart';
import '../../data/datasources/whisper_datasource.dart';
import '../../data/datasources/settings_datasource.dart';
import '../../data/datasources/model_download_datasource.dart';
import '../../data/datasources/device_scanner_datasource.dart';
import '../../data/datasources/conversation_storage.dart';
import '../../data/datasources/audio_recorder_service.dart';
import '../../data/repositories/llm_repository_impl.dart';
import '../../data/repositories/cloud_llm_repository_impl.dart';
import '../../data/repositories/voice_repository_impl.dart';
import '../../data/repositories/settings_repository_impl.dart';
import '../../data/repositories/model_repository_impl.dart';
import '../../data/services/elevenlabs_tts_service.dart';
import '../../data/services/stt_model_download_service.dart';
import '../../data/services/stt_model_path_resolver_impl.dart';
import '../../data/services/groq_api_service.dart';
import '../../data/services/gemini_api_service.dart';
import '../../data/services/cloud_api_key_storage.dart';
import '../../data/services/cloud_connectivity_checker.dart';
import '../../domain/repositories/llm_repository.dart';
import '../../domain/repositories/voice_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/model_repository.dart';
import '../../domain/services/stt_model_path_resolver.dart';
import '../../domain/usecases/generate_response_usecase.dart';
import '../../domain/usecases/translate_text_usecase.dart';
import '../../domain/usecases/speech_to_text_usecase.dart';
import '../../domain/usecases/text_to_speech_usecase.dart';
import '../../domain/usecases/download_model_usecase.dart';
import '../../domain/usecases/load_model_usecase.dart';
import '../../domain/usecases/summarize_transcript_usecase.dart';
import '../../domain/usecases/safety_preprocessor_usecase.dart';
import '../../domain/usecases/evaluation_usecase.dart';
import '../../domain/services/system_prompt_manager.dart';
import '../../domain/services/prompt_security_layer.dart';
import '../../data/datasources/benchmark_storage.dart';
import '../../data/datasources/system_prompt_storage_impl.dart';
import '../../data/datasources/v2_session_storage.dart';
import '../../presentation/blocs/chat/chat_bloc.dart';
import '../../presentation/blocs/settings/settings_bloc.dart';
import '../../presentation/blocs/model/model_bloc.dart';
import '../../presentation/blocs/voice/voice_bloc.dart';
import '../../presentation/blocs/benchmark/benchmark_bloc.dart';
import '../../presentation/blocs/v2_session/v2_session_bloc.dart';
import '../utils/logger.dart';

/// Global service locator instance.
final GetIt sl = GetIt.instance;

/// Initialize all dependencies.
/// 
/// Must be called before runApp() in main.dart.
/// Dependencies are registered in order of their dependency graph:
/// 1. External dependencies (Hive, SecureStorage)
/// 2. Data sources
/// 3. Repositories
/// 4. Use cases
/// 5. BLoCs
Future<void> initializeDependencies() async {
  AppLogger.i('Initializing dependencies...');
  
  // ============================================================
  // EXTERNAL DEPENDENCIES
  // ============================================================
  
  // Initialize Hive for local storage
  await Hive.initFlutter();
  
  // Register Hive boxes
  final settingsBox = await Hive.openBox<dynamic>('settings');
  sl.registerSingleton<Box<dynamic>>(settingsBox, instanceName: 'settingsBox');
  
  final conversationsBox = await Hive.openBox<dynamic>('conversations');
  sl.registerSingleton<Box<dynamic>>(conversationsBox, instanceName: 'conversationsBox');
  
  // Secure storage for sensitive data
  const secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );
  sl.registerSingleton<FlutterSecureStorage>(secureStorage);
  
  // ============================================================
  // DATA SOURCES
  // ============================================================
  
  // LLM native data source - uses JNI (via platform channel) for better stability
  // The JNI approach handles llama.cpp struct alignment natively in C++,
  // avoiding the FFI struct passing issues on ARM64.
  sl.registerLazySingleton<LLMNativeDataSource>(
    () => LLMJniDataSourceImpl(),
  );

  // Sync conversation history to native incremental buffer (JNI path).
  sl.registerLazySingleton(() => LlmConversationSyncDataSource());
  
  // Voice data source - interfaces with Android STT/TTS
  sl.registerLazySingleton<VoiceDataSource>(
    () => VoiceDataSourceImpl(),
  );

  // Whisper STT data source - offline STT via whisper.cpp
  sl.registerLazySingleton<WhisperDataSource>(
    () => WhisperDataSourceImpl(),
  );
  
  // Settings data source
  sl.registerLazySingleton<SettingsDataSource>(
    () => SettingsDataSourceImpl(
      settingsBox: sl(instanceName: 'settingsBox'),
      secureStorage: sl(),
    ),
  );
  
  // Model download data source
  sl.registerLazySingleton<ModelDownloadDataSource>(
    () => ModelDownloadDataSourceImpl(),
  );
  
  // Device scanner data source
  sl.registerLazySingleton<DeviceScannerDataSource>(
    () => DeviceScannerDataSourceImpl(),
  );
  
  // Conversation storage - persists the active chat history
  sl.registerLazySingleton(
    () => ConversationStorage(conversationsBox: sl(instanceName: 'conversationsBox')),
  );

  // ============================================================
  // REPOSITORIES
  // ============================================================
  
  sl.registerLazySingleton<LLMRepository>(
    () => LLMRepositoryImpl(
      nativeDataSource: sl(),
    ),
  );
  
  sl.registerLazySingleton<VoiceRepository>(
    () => VoiceRepositoryImpl(
      voiceDataSource: sl(),
      whisperDataSource: sl(),
      elevenLabsTtsService: sl(),
    ),
  );
  
  sl.registerLazySingleton<SettingsRepository>(
    () => SettingsRepositoryImpl(
      settingsDataSource: sl(),
    ),
  );
  
  sl.registerLazySingleton<ModelRepository>(
    () => ModelRepositoryImpl(
      downloadDataSource: sl(),
      secureStorage: sl(),
    ),
  );

  // ============================================================
  // SERVICES
  // ============================================================

  sl.registerLazySingleton(
    () => ElevenLabsTtsService(secureStorage: sl()),
  );
  sl.registerLazySingleton(() => SttModelDownloadService());
  sl.registerLazySingleton<SttModelPathResolver>(
    () => SttModelPathResolverImpl(downloadService: sl()),
  );
  
  // ============================================================
  // V2 CLOUD SERVICES
  // ============================================================

  sl.registerLazySingleton(() => GroqApiService());
  sl.registerLazySingleton(() => GeminiApiService());
  sl.registerLazySingleton(
    () => CloudApiKeyStorage(secureStorage: sl()),
  );
  sl.registerLazySingleton(
    () => CloudConnectivityChecker(
      keyStorage: sl(),
      groqApi: sl(),
      geminiApi: sl(),
    ),
  );
  sl.registerLazySingleton(() => AudioRecorderService());

  // Cloud LLM repository (used by V2 flow)
  sl.registerLazySingleton(
    () => CloudLLMRepositoryImpl(
      groqApi: sl(),
      geminiApi: sl(),
      keyStorage: sl(),
    ),
  );

  // ============================================================
  // USE CASES
  // ============================================================
  
  sl.registerLazySingleton(
    () => GenerateResponseUseCase(llmRepository: sl()),
  );
  
  sl.registerLazySingleton(
    () => TranslateTextUseCase(llmRepository: sl()),
  );
  
  sl.registerLazySingleton(
    () => SpeechToTextUseCase(
      voiceRepository: sl(),
      sttModelPathResolver: sl(),
    ),
  );
  
  sl.registerLazySingleton(
    () => TextToSpeechUseCase(voiceRepository: sl()),
  );
  
  sl.registerLazySingleton(
    () => DownloadModelUseCase(modelRepository: sl()),
  );
  
  sl.registerLazySingleton(
    () => LoadModelUseCase(llmRepository: sl()),
  );
  
  sl.registerLazySingleton(
    () => SummarizeTranscriptUseCase(
      llmRepository: sl(),
      safetyPreprocessor: sl(),
      evaluationUseCase: sl(),
    ),
  );

  // ============================================================
  // DATA SOURCES (benchmark & evaluation)
  // ============================================================

  sl.registerLazySingleton(
    () => BenchmarkStorage(settingsBox: sl(instanceName: 'settingsBox')),
  );

  sl.registerLazySingleton<SystemPromptStorage>(
    () => SystemPromptStorageImpl(settingsBox: sl(instanceName: 'settingsBox')),
  );

  sl.registerLazySingleton(
    () => V2SessionStorage(settingsBox: sl(instanceName: 'settingsBox')),
  );

  // ============================================================
  // DOMAIN SERVICES (evaluation & safety)
  // ============================================================

  sl.registerLazySingleton(
    () => SystemPromptManager(storage: sl()),
  );

  sl.registerLazySingleton(
    () => PromptSecurityLayer(
      promptManager: sl(),
      llmRepository: sl(),
    ),
  );

  sl.registerLazySingleton(
    () => SafetyPreprocessorUseCase(
      llmRepository: sl(),
      promptManager: sl(),
      securityLayer: sl(),
    ),
  );

  sl.registerLazySingleton(
    () => EvaluationUseCase(
      llmRepository: sl(),
      promptManager: sl(),
    ),
  );
  
  // ============================================================
  // BLOCS
  // ============================================================
  
  // BLoCs are registered as factories so each widget tree gets fresh instance
  // if needed, or singletons for app-wide state.
  
  sl.registerLazySingleton(
    () => ModelBloc(
      downloadModelUseCase: sl(),
      loadModelUseCase: sl(),
      modelRepository: sl(),
    ),
  );
  
  sl.registerLazySingleton(
    () => SettingsBloc(
      settingsRepository: sl(),
    ),
  );
  
  sl.registerFactory(
    () => ChatBloc(
      generateResponseUseCase: sl(),
      translateTextUseCase: sl(),
      settingsBox: sl(instanceName: 'settingsBox'),
      conversationStorage: sl(),
      llmConversationSync: sl(),
    ),
  );
  
  sl.registerFactory(
    () => VoiceBloc(
      speechToTextUseCase: sl(),
      textToSpeechUseCase: sl(),
    ),
  );
  
  sl.registerFactory(
    () => BenchmarkBloc(
      speechToTextUseCase: sl(),
      summarizeTranscriptUseCase: sl(),
      benchmarkStorage: sl(),
    ),
  );

  sl.registerFactory(
    () => V2SessionBloc(
      connectivityChecker: sl(),
      keyStorage: sl(),
      groqApi: sl(),
      cloudLlmRepo: sl(),
      audioRecorder: sl(),
      promptManager: sl(),
      sessionStorage: sl(),
    ),
  );
  
  AppLogger.i('Dependencies initialized successfully');
}

/// Reset all dependencies. Used for testing.
Future<void> resetDependencies() async {
  await sl.reset();
}
