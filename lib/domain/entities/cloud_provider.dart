/// Cloud LLM provider for evaluation and summarization.
enum CloudLLMProvider {
  groq,
  gemini,
}

extension CloudLLMProviderX on CloudLLMProvider {
  String get id {
    switch (this) {
      case CloudLLMProvider.groq:
        return 'groq';
      case CloudLLMProvider.gemini:
        return 'gemini';
    }
  }

  String get displayName {
    switch (this) {
      case CloudLLMProvider.groq:
        return 'Groq (Llama 3.3 70B)';
      case CloudLLMProvider.gemini:
        return 'Gemini 2.0 Flash';
    }
  }

  String get defaultModel {
    switch (this) {
      case CloudLLMProvider.groq:
        return 'llama-3.3-70b-versatile';
      case CloudLLMProvider.gemini:
        return 'gemini-2.0-flash';
    }
  }

  static CloudLLMProvider fromId(String? id) {
    switch (id) {
      case 'gemini':
        return CloudLLMProvider.gemini;
      case 'groq':
      default:
        return CloudLLMProvider.groq;
    }
  }
}

/// Cloud STT provider for transcription.
enum CloudSttProvider {
  groqWhisper,
  localWhisper,
}

extension CloudSttProviderX on CloudSttProvider {
  String get id {
    switch (this) {
      case CloudSttProvider.groqWhisper:
        return 'groq_whisper';
      case CloudSttProvider.localWhisper:
        return 'local_whisper';
    }
  }

  String get displayName {
    switch (this) {
      case CloudSttProvider.groqWhisper:
        return 'Groq Whisper (cloud, best accuracy)';
      case CloudSttProvider.localWhisper:
        return 'Local Whisper (offline)';
    }
  }

  static CloudSttProvider fromId(String? id) {
    switch (id) {
      case 'local_whisper':
        return CloudSttProvider.localWhisper;
      case 'groq_whisper':
      default:
        return CloudSttProvider.groqWhisper;
    }
  }
}
