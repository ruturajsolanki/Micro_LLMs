import '../entities/app_settings.dart';
import '../../core/utils/result.dart';

/// Repository interface for application settings.
/// 
/// Settings are persisted locally and never transmitted over the network.
/// This repository handles both regular settings (Hive) and sensitive
/// settings (Flutter Secure Storage).
abstract class SettingsRepository {
  /// Load current settings from storage.
  /// 
  /// Returns default settings if none are stored.
  AsyncResult<AppSettings> loadSettings();
  
  /// Save settings to storage.
  /// 
  /// Validates settings before saving and returns failure if invalid.
  AsyncResult<void> saveSettings(AppSettings settings);
  
  /// Update a single setting value.
  /// 
  /// More efficient than loading/saving full settings for single changes.
  AsyncResult<void> updateSetting<T>(String key, T value);
  
  /// Reset all settings to defaults.
  AsyncResult<void> resetToDefaults();
  
  /// Get a specific setting value.
  AsyncResult<T?> getSetting<T>(String key);
  
  /// Watch settings for changes.
  /// 
  /// Emits whenever settings are modified. Useful for reactive UI updates.
  Stream<AppSettings> watchSettings();
  
  /// Export settings to a map (for backup/debugging).
  AsyncResult<Map<String, dynamic>> exportSettings();
  
  /// Import settings from a map (for restore).
  AsyncResult<void> importSettings(Map<String, dynamic> settings);
}
