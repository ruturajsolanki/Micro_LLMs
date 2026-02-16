import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

import '../../core/error/exceptions.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/cloud_provider.dart';
import '../../domain/entities/speech_to_text_engine.dart';
import '../../domain/entities/text_to_speech_engine.dart';

/// Data source for application settings.
/// 
/// Uses Hive for regular settings and Flutter Secure Storage for
/// sensitive data that needs encryption.
abstract class SettingsDataSource {
  Future<AppSettings> loadSettings();
  Future<void> saveSettings(AppSettings settings);
  Future<void> updateSetting<T>(String key, T value);
  Future<T?> getSetting<T>(String key);
  Future<void> clearAll();
  Stream<AppSettings> watchSettings();
}

class SettingsDataSourceImpl with Loggable implements SettingsDataSource {
  final Box<dynamic> _settingsBox;
  final FlutterSecureStorage _secureStorage;
  
  SettingsDataSourceImpl({
    required Box<dynamic> settingsBox,
    required FlutterSecureStorage secureStorage,
  })  : _settingsBox = settingsBox,
        _secureStorage = secureStorage;
  
  @override
  Future<AppSettings> loadSettings() async {
    try {
      final sourceLanguage = _settingsBox.get('sourceLanguage') as String?;
      final targetLanguage = _settingsBox.get('targetLanguage') as String?;
      final voiceInputEnabled = _settingsBox.get('voiceInputEnabled') as bool?;
      final voiceOutputEnabled = _settingsBox.get('voiceOutputEnabled') as bool?;
      final voiceSttOfflineOnly = _settingsBox.get('voiceSttOfflineOnly') as bool?;
      final sttEngineId = _settingsBox.get('speechToTextEngine') as String?;
      final whisperModelId = _settingsBox.get('whisperModelId') as String?;
      final ttsEngineId = _settingsBox.get('textToSpeechEngine') as String?;
      final elevenLabsVoiceId = _settingsBox.get('elevenLabsVoiceId') as String?;
      final temperature = _settingsBox.get('temperature') as double?;
      final contextWindowSize = _settingsBox.get('contextWindowSize') as int?;
      final maxGenerationTokens = _settingsBox.get('maxGenerationTokens') as int?;
      final inferenceThreads = _settingsBox.get('inferenceThreads') as int?;
      final autoDetectLanguage = _settingsBox.get('autoDetectLanguage') as bool?;
      final themePreferenceIndex = _settingsBox.get('themePreference') as int?;
      final selectedModelPath = _settingsBox.get('selectedModelPath') as String?;
      final showTokenCount = _settingsBox.get('showTokenCount') as bool?;
      final keepScreenOn = _settingsBox.get('keepScreenOn') as bool?;
      final useCloudProcessing = _settingsBox.get('useCloudProcessing') as bool?;
      final cloudLLMProviderId = _settingsBox.get('cloudLLMProvider') as String?;
      final cloudSttProviderId = _settingsBox.get('cloudSttProvider') as String?;
      
      return AppSettings(
        sourceLanguage: sourceLanguage ?? 'en',
        targetLanguage: targetLanguage ?? 'es',
        voiceInputEnabled: voiceInputEnabled ?? false,
        voiceOutputEnabled: voiceOutputEnabled ?? false,
        voiceSttOfflineOnly: voiceSttOfflineOnly ?? true,
        speechToTextEngine: SpeechToTextEngineX.fromId(sttEngineId),
        whisperModelId: whisperModelId ?? 'small',
        textToSpeechEngine: TextToSpeechEngineX.fromId(ttsEngineId),
        elevenLabsVoiceId: elevenLabsVoiceId ?? 'JBFqnCBsd6RMkjVDRZzb',
        temperature: temperature ?? 0.7,
        contextWindowSize: contextWindowSize,
        maxGenerationTokens: maxGenerationTokens ?? 512,
        inferenceThreads: inferenceThreads ?? 4,
        autoDetectLanguage: autoDetectLanguage ?? true,
        themePreference: themePreferenceIndex != null
            ? ThemePreference.values[themePreferenceIndex]
            : ThemePreference.system,
        selectedModelPath: selectedModelPath,
        showTokenCount: showTokenCount ?? false,
        keepScreenOn: keepScreenOn ?? true,
        useCloudProcessing: useCloudProcessing ?? true,
        cloudLLMProvider: CloudLLMProviderX.fromId(cloudLLMProviderId),
        cloudSttProvider: CloudSttProviderX.fromId(cloudSttProviderId),
      );
    } catch (e, stack) {
      logger.e('Failed to load settings', error: e, stackTrace: stack);
      // Return defaults on error
      return const AppSettings();
    }
  }
  
  @override
  Future<void> saveSettings(AppSettings settings) async {
    try {
      await _settingsBox.putAll({
        'sourceLanguage': settings.sourceLanguage,
        'targetLanguage': settings.targetLanguage,
        'voiceInputEnabled': settings.voiceInputEnabled,
        'voiceOutputEnabled': settings.voiceOutputEnabled,
        'voiceSttOfflineOnly': settings.voiceSttOfflineOnly,
        'speechToTextEngine': settings.speechToTextEngine.id,
        'whisperModelId': settings.whisperModelId,
        'textToSpeechEngine': settings.textToSpeechEngine.id,
        'elevenLabsVoiceId': settings.elevenLabsVoiceId,
        'temperature': settings.temperature,
        'contextWindowSize': settings.contextWindowSize,
        'maxGenerationTokens': settings.maxGenerationTokens,
        'inferenceThreads': settings.inferenceThreads,
        'autoDetectLanguage': settings.autoDetectLanguage,
        'themePreference': settings.themePreference.index,
        'selectedModelPath': settings.selectedModelPath,
        'showTokenCount': settings.showTokenCount,
        'keepScreenOn': settings.keepScreenOn,
        'useCloudProcessing': settings.useCloudProcessing,
        'cloudLLMProvider': settings.cloudLLMProvider.id,
        'cloudSttProvider': settings.cloudSttProvider.id,
      });
    } catch (e, stack) {
      logger.e('Failed to save settings', error: e, stackTrace: stack);
      throw StorageException(
        message: 'Failed to save settings: $e',
        cause: e,
        stackTrace: stack,
      );
    }
  }
  
  @override
  Future<void> updateSetting<T>(String key, T value) async {
    try {
      await _settingsBox.put(key, value);
    } catch (e) {
      throw StorageException(
        message: 'Failed to update setting "$key"',
        key: key,
        cause: e,
      );
    }
  }
  
  @override
  Future<T?> getSetting<T>(String key) async {
    try {
      return _settingsBox.get(key) as T?;
    } catch (e) {
      logger.w('Failed to get setting "$key": $e');
      return null;
    }
  }
  
  @override
  Future<void> clearAll() async {
    await _settingsBox.clear();
    await _secureStorage.deleteAll();
  }
  
  @override
  Stream<AppSettings> watchSettings() {
    return _settingsBox.watch().asyncMap((_) => loadSettings());
  }
  
  /// Store encrypted value.
  Future<void> storeSecure(String key, String value) async {
    try {
      await _secureStorage.write(key: key, value: value);
    } catch (e) {
      throw SecurityException(
        message: 'Failed to store secure value',
        cause: e,
      );
    }
  }
  
  /// Read encrypted value.
  Future<String?> readSecure(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (e) {
      logger.e('Failed to read secure value: $e');
      return null;
    }
  }
  
  /// Store encrypted JSON object.
  Future<void> storeSecureJson(String key, Map<String, dynamic> value) async {
    await storeSecure(key, jsonEncode(value));
  }
  
  /// Read encrypted JSON object.
  Future<Map<String, dynamic>?> readSecureJson(String key) async {
    final value = await readSecure(key);
    if (value == null) return null;
    try {
      return jsonDecode(value) as Map<String, dynamic>;
    } catch (e) {
      logger.e('Failed to decode secure JSON: $e');
      return null;
    }
  }
}
