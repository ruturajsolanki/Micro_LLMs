import 'package:dartz/dartz.dart';

import '../../core/error/failures.dart';
import '../../core/utils/result.dart';
import '../../core/utils/logger.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/settings_datasource.dart';

/// Implementation of settings repository.
class SettingsRepositoryImpl with Loggable implements SettingsRepository {
  final SettingsDataSource _settingsDataSource;
  
  SettingsRepositoryImpl({
    required SettingsDataSource settingsDataSource,
  }) : _settingsDataSource = settingsDataSource;
  
  @override
  AsyncResult<AppSettings> loadSettings() async {
    try {
      final settings = await _settingsDataSource.loadSettings();
      return Right(settings);
    } catch (e, stack) {
      logger.e('Failed to load settings', error: e, stackTrace: stack);
      return Left(StorageFailure(
        message: 'Failed to load settings: $e',
        stackTrace: stack,
      ));
    }
  }
  
  @override
  AsyncResult<void> saveSettings(AppSettings settings) async {
    try {
      // Validate before saving
      if (!settings.isValid) {
        return const Left(StorageFailure(
          message: 'Invalid settings values',
          code: 'VALIDATION_ERROR',
        ));
      }
      
      await _settingsDataSource.saveSettings(settings);
      return const Right(null);
    } catch (e, stack) {
      logger.e('Failed to save settings', error: e, stackTrace: stack);
      return Left(StorageFailure(
        message: 'Failed to save settings: $e',
        stackTrace: stack,
      ));
    }
  }
  
  @override
  AsyncResult<void> updateSetting<T>(String key, T value) async {
    try {
      await _settingsDataSource.updateSetting(key, value);
      return const Right(null);
    } catch (e, stack) {
      logger.e('Failed to update setting', error: e, stackTrace: stack);
      return Left(StorageFailure.writeError(key, e));
    }
  }
  
  @override
  AsyncResult<void> resetToDefaults() async {
    try {
      await _settingsDataSource.clearAll();
      await _settingsDataSource.saveSettings(const AppSettings());
      return const Right(null);
    } catch (e, stack) {
      logger.e('Failed to reset settings', error: e, stackTrace: stack);
      return Left(StorageFailure(
        message: 'Failed to reset settings: $e',
        stackTrace: stack,
      ));
    }
  }
  
  @override
  AsyncResult<T?> getSetting<T>(String key) async {
    try {
      final value = await _settingsDataSource.getSetting<T>(key);
      return Right(value);
    } catch (e, stack) {
      return Left(StorageFailure.readError(key, e));
    }
  }
  
  @override
  Stream<AppSettings> watchSettings() {
    return _settingsDataSource.watchSettings();
  }
  
  @override
  AsyncResult<Map<String, dynamic>> exportSettings() async {
    try {
      final settings = await _settingsDataSource.loadSettings();
      return Right({
        'sourceLanguage': settings.sourceLanguage,
        'targetLanguage': settings.targetLanguage,
        'voiceInputEnabled': settings.voiceInputEnabled,
        'voiceOutputEnabled': settings.voiceOutputEnabled,
        'temperature': settings.temperature,
        'contextWindowSize': settings.contextWindowSize,
        'maxGenerationTokens': settings.maxGenerationTokens,
        'inferenceThreads': settings.inferenceThreads,
        'autoDetectLanguage': settings.autoDetectLanguage,
        'themePreference': settings.themePreference.index,
        'showTokenCount': settings.showTokenCount,
        'keepScreenOn': settings.keepScreenOn,
      });
    } catch (e, stack) {
      return Left(StorageFailure(
        message: 'Failed to export settings: $e',
        stackTrace: stack,
      ));
    }
  }
  
  @override
  AsyncResult<void> importSettings(Map<String, dynamic> settings) async {
    try {
      final appSettings = AppSettings(
        sourceLanguage: settings['sourceLanguage'] as String? ?? 'en',
        targetLanguage: settings['targetLanguage'] as String? ?? 'es',
        voiceInputEnabled: settings['voiceInputEnabled'] as bool? ?? false,
        voiceOutputEnabled: settings['voiceOutputEnabled'] as bool? ?? false,
        temperature: (settings['temperature'] as num?)?.toDouble() ?? 0.7,
        contextWindowSize: settings['contextWindowSize'] as int?,
        maxGenerationTokens: settings['maxGenerationTokens'] as int? ?? 512,
        inferenceThreads: settings['inferenceThreads'] as int? ?? 4,
        autoDetectLanguage: settings['autoDetectLanguage'] as bool? ?? true,
        themePreference: ThemePreference.values[
            settings['themePreference'] as int? ?? 0],
        showTokenCount: settings['showTokenCount'] as bool? ?? false,
        keepScreenOn: settings['keepScreenOn'] as bool? ?? true,
      );
      
      await _settingsDataSource.saveSettings(appSettings);
      return const Right(null);
    } catch (e, stack) {
      return Left(StorageFailure(
        message: 'Failed to import settings: $e',
        stackTrace: stack,
      ));
    }
  }
}
