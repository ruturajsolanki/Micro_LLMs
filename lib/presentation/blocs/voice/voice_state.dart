part of 'voice_bloc.dart';

/// Status of speech-to-text.
enum VoiceSttStatus {
  idle,
  listening,
  processing,
  error,
}

/// Status of text-to-speech.
enum VoiceTtsStatus {
  idle,
  speaking,
  error,
}

/// State of voice operations.
class VoiceState extends Equatable {
  /// STT status.
  final VoiceSttStatus sttStatus;
  
  /// TTS status.
  final VoiceTtsStatus ttsStatus;
  
  /// Currently recognized text.
  final String recognizedText;
  
  /// Confidence of last recognition.
  final double? lastConfidence;

  /// Current input level (RMS dB) for mic animation.
  final double? inputLevelDb;
  
  /// Error message.
  final String? errorMessage;
  
  const VoiceState({
    this.sttStatus = VoiceSttStatus.idle,
    this.ttsStatus = VoiceTtsStatus.idle,
    this.recognizedText = '',
    this.lastConfidence,
    this.inputLevelDb,
    this.errorMessage,
  });
  
  /// Create a copy with updated fields.
  VoiceState copyWith({
    VoiceSttStatus? sttStatus,
    VoiceTtsStatus? ttsStatus,
    String? recognizedText,
    double? lastConfidence,
    double? inputLevelDb,
    String? errorMessage,
  }) {
    return VoiceState(
      sttStatus: sttStatus ?? this.sttStatus,
      ttsStatus: ttsStatus ?? this.ttsStatus,
      recognizedText: recognizedText ?? this.recognizedText,
      lastConfidence: lastConfidence ?? this.lastConfidence,
      inputLevelDb: inputLevelDb ?? this.inputLevelDb,
      errorMessage: errorMessage,
    );
  }
  
  /// Whether STT is active.
  bool get isListening => sttStatus == VoiceSttStatus.listening;
  
  /// Whether TTS is active.
  bool get isSpeaking => ttsStatus == VoiceTtsStatus.speaking;
  
  /// Whether there's an STT error.
  bool get hasSttError => sttStatus == VoiceSttStatus.error;
  
  /// Whether there's a TTS error.
  bool get hasTtsError => ttsStatus == VoiceTtsStatus.error;
  
  /// Whether any voice operation is active.
  bool get isActive => isListening || isSpeaking;
  
  @override
  List<Object?> get props => [
    sttStatus,
    ttsStatus,
    recognizedText,
    lastConfidence,
    inputLevelDb,
    errorMessage,
  ];
}
