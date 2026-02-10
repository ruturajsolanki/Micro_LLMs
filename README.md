# MicroLLM

**Offline-first, on-device LLM chat app for Android** — powered by llama.cpp, whisper.cpp, and Flutter.

Run large language models directly on your phone. No servers, no cloud, no data leaves your device.

---

## Features

### Chat with On-Device LLM
- Text conversations with quantized LLMs running entirely on your phone
- Streaming token generation with real-time display
- Conversation history with persistent storage
- Configurable temperature, context window, and model selection

### Voice Input & Output
- **Speech-to-Text**: Android SpeechRecognizer (online/offline) or Whisper.cpp (fully offline)
- **Text-to-Speech**: Android TTS or ElevenLabs (cloud, optional)
- Continuous listening mode for hands-free interaction

### Voice Benchmarking & Summarization
- Record 2–3 minutes of speech with live transcript display
- Automatic summarization pipeline:
  - Transcription
  - Key idea extraction
  - Configurable summarization (multiple prompt presets)
  - Optional quality evaluation with rubric scoring
- Benchmark scores across five dimensions: Relevance, Coverage, Coherence, Conciseness, Faithfulness
- Customizable system prompts with built-in presets and a prompt editor

### Model Management
- Download GGUF models directly from HuggingFace
- Device compatibility checker with RAM/storage recommendations
- Hot-swap between downloaded models

### Privacy & Security
- All inference runs on-device — no data transmitted after model download
- Encrypted metadata storage via `flutter_secure_storage`
- No telemetry, no analytics, no tracking

---

## Supported Models

| Model | Size | Min RAM | Notes |
|-------|------|---------|-------|
| SmolLM 135M | ~145 MB | 512 MB | Ultra-light, basic quality |
| Qwen2.5 0.5B | ~400 MB | 1 GB | Good for low-end devices |
| TinyLlama 1.1B | ~670 MB | 2 GB | Fast, decent quality |
| Llama 3.2 1B | ~750 MB | 2 GB | Meta's compact model |
| **Qwen2.5 1.5B** (default) | **~1.1 GB** | **2 GB** | **Best balance of quality & speed** |
| Gemma 2 2B | ~1.6 GB | 3 GB | Google's efficient model |
| Phi-2 2.7B | ~1.7 GB | 3 GB | Microsoft Research |
| Llama 3.2 3B | ~2 GB | 4 GB | Higher quality, needs more RAM |
| Phi-3 Mini 3.8B | ~2.3 GB | 4 GB | Strong reasoning |
| Mistral 7B | ~4.1 GB | 6 GB | Best quality, flagship devices only |

All models use Q4_K_M quantization (GGUF format).

---

## Architecture

Clean Architecture with strict layer separation:

```
lib/
├── core/                  # Constants, DI, error handling, utilities
│   ├── constants/         # App-wide constants (model, prompt, language)
│   ├── di/                # GetIt dependency injection setup
│   ├── error/             # Failure types and exceptions
│   └── utils/             # Logger, Result type helpers
│
├── domain/                # Business logic (pure Dart, no framework deps)
│   ├── entities/          # Message, Conversation, BenchmarkResult, etc.
│   ├── repositories/      # Abstract repository contracts
│   ├── services/          # Model catalog, compatibility calculator
│   └── usecases/          # GenerateResponse, SpeechToText, Summarize, etc.
│
├── data/                  # Implementation layer
│   ├── datasources/       # Platform channels (LLM JNI, Whisper, Voice)
│   ├── repositories/      # Repository implementations
│   └── services/          # Model download, ElevenLabs TTS
│
├── presentation/          # UI layer
│   ├── blocs/             # Chat, Model, Settings, Voice, Benchmark BLoCs
│   ├── pages/             # Chat, Settings, Benchmark, Onboarding, etc.
│   ├── widgets/           # Reusable UI components
│   └── theme/             # App theme, UI tokens, motion constants
│
└── main.dart              # Entry point
```

### Native Layer (Android/Kotlin)

```
android/app/src/main/
├── kotlin/.../            # Platform channel handlers
│   ├── MainActivity.kt    # Channel registration, permissions
│   ├── LlmHandler.kt      # llama.cpp JNI bridge
│   ├── SpeechToTextHandler.kt  # Android SpeechRecognizer
│   └── WhisperHandler.kt  # whisper.cpp JNI bridge
│
└── cpp/                   # Native C++ code
    ├── llama_jni.cpp       # JNI bindings for llama.cpp
    └── whisper_jni.cpp     # JNI bindings for whisper.cpp
```

---

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Framework | Flutter (Dart SDK >=3.2.0) |
| State Management | BLoC (`flutter_bloc`) |
| Dependency Injection | GetIt + Injectable |
| LLM Inference | llama.cpp via JNI |
| Speech-to-Text | whisper.cpp (offline) + Android SpeechRecognizer |
| Text-to-Speech | Android TTS + ElevenLabs API |
| Local Storage | Hive |
| Secure Storage | flutter_secure_storage |
| Networking | Dio (model download only) |
| Error Handling | dartz (`Either` / `Result` types) |

---

## Getting Started

### Prerequisites

- Flutter 3.16+
- Android SDK with NDK (25.x recommended)
- Android device or emulator (API 29+, ARM64)
- 4 GB+ device RAM recommended
- ~2 GB free storage for the default model

### Quick Setup

```bash
# Clone the repository
git clone https://github.com/<your-username>/MicroLLMApp.git
cd MicroLLMApp

# Run the setup script (clones llama.cpp, checks dependencies)
./setup.sh

# Or manually:
mkdir -p external
git clone --depth 1 https://github.com/ggerganov/llama.cpp.git external/llama.cpp
git clone --depth 1 https://github.com/ggerganov/whisper.cpp.git external/whisper.cpp
flutter pub get

# Run on a connected device
flutter run
```

### Build Release APK

```bash
flutter build apk --release --target-platform android-arm64
```

### First Launch

1. The app will prompt you to download a model (default: Qwen2.5-1.5B, ~1 GB)
2. Once downloaded, the model loads into memory and you can start chatting
3. Voice features require microphone permission — grant when prompted

---

## Voice Benchmark Flow

```
┌─────────┐     ┌───────────┐     ┌────────────┐     ┌──────────┐
│  IDLE   │────▶│ RECORDING │────▶│ PROCESSING │────▶│  RESULT  │
│         │     │           │     │            │     │          │
│ Configure│     │ Live      │     │ Transcribe │     │ Summary  │
│ prompt   │     │ transcript│     │ Extract    │     │ Key ideas│
│ Toggle   │     │ Timer     │     │ Summarize  │     │ Metrics  │
│ benchmark│     │ Word count│     │ Evaluate?  │     │ Scores?  │
└─────────┘     └───────────┘     └────────────┘     └──────────┘
```

**Benchmark evaluation** is optional — toggle it off for faster summarization-only mode.

---

## Permissions

| Permission | Purpose |
|-----------|---------|
| `INTERNET` | One-time model download from HuggingFace |
| `RECORD_AUDIO` | Speech-to-text input |
| `FOREGROUND_SERVICE` | Background model loading |
| `WAKE_LOCK` | Keep screen on during inference |

No data is sent to any server during normal use. Internet is only needed for the initial model download and optionally for ElevenLabs TTS.

---

## License

This project is for personal/educational use.
