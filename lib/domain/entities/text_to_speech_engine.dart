/// Text-to-speech engine selection.
///
/// Default remains Android TTS (offline-capable).
/// ElevenLabs is optional and requires internet + API key.
enum TextToSpeechEngine {
  androidTts,
  elevenLabs,
}

extension TextToSpeechEngineX on TextToSpeechEngine {
  String get id {
    switch (this) {
      case TextToSpeechEngine.androidTts:
        return 'android';
      case TextToSpeechEngine.elevenLabs:
        return 'elevenlabs';
    }
  }

  String get displayName {
    switch (this) {
      case TextToSpeechEngine.androidTts:
        return 'Android (offline)';
      case TextToSpeechEngine.elevenLabs:
        return 'ElevenLabs (natural, online)';
    }
  }

  static TextToSpeechEngine fromId(String? id) {
    switch (id) {
      case 'elevenlabs':
        return TextToSpeechEngine.elevenLabs;
      case 'android':
      default:
        return TextToSpeechEngine.androidTts;
    }
  }
}

