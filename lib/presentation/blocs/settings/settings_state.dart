part of 'settings_bloc.dart';

/// Status of settings operations.
enum SettingsStatus {
  initial,
  loading,
  loaded,
  saving,
  error,
}

/// State of application settings.
class SettingsState extends Equatable {
  /// Current status.
  final SettingsStatus status;
  
  /// The settings.
  final AppSettings settings;
  
  /// Error message if status is error.
  final String? errorMessage;
  
  const SettingsState({
    this.status = SettingsStatus.initial,
    this.settings = const AppSettings(),
    this.errorMessage,
  });
  
  /// Create a copy with updated fields.
  SettingsState copyWith({
    SettingsStatus? status,
    AppSettings? settings,
    String? errorMessage,
  }) {
    return SettingsState(
      status: status ?? this.status,
      settings: settings ?? this.settings,
      errorMessage: errorMessage,
    );
  }
  
  /// Whether settings are loaded.
  bool get isLoaded => status == SettingsStatus.loaded;
  
  /// Whether settings are being saved.
  bool get isSaving => status == SettingsStatus.saving;
  
  /// Whether there's an error.
  bool get hasError => status == SettingsStatus.error;
  
  @override
  List<Object?> get props => [status, settings, errorMessage];
}
