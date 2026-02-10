/// Speech-to-text engine selection.
///
/// Why:
/// - `androidSpeechRecognizer`: lightweight, can be offline if language packs exist.
/// - `whisperCpp`: true in-app offline STT (whisper.cpp), heavier but reliable offline.
enum SpeechToTextEngine {
  androidSpeechRecognizer,
  whisperCpp,
}

extension SpeechToTextEngineX on SpeechToTextEngine {
  String get id {
    switch (this) {
      case SpeechToTextEngine.androidSpeechRecognizer:
        return 'android';
      case SpeechToTextEngine.whisperCpp:
        return 'whisper';
    }
  }

  String get displayName {
    switch (this) {
      case SpeechToTextEngine.androidSpeechRecognizer:
        return 'Android (SpeechRecognizer)';
      case SpeechToTextEngine.whisperCpp:
        return 'Whisper (offline)';
    }
  }

  static SpeechToTextEngine fromId(String? id) {
    switch (id) {
      case 'whisper':
        return SpeechToTextEngine.whisperCpp;
      case 'android':
      default:
        return SpeechToTextEngine.androidSpeechRecognizer;
    }
  }
}

