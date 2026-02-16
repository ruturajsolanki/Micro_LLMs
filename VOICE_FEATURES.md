# Voice & Language Evaluation Features

> Complete inventory of all voice-related capabilities in MicroLLMApp.

---

## Table of Contents

- [1. Speech-to-Text (STT)](#1-speech-to-text-stt)
- [2. Text-to-Speech (TTS)](#2-text-to-speech-tts)
- [3. Voice Benchmarking & Summarization Pipeline](#3-voice-benchmarking--summarization-pipeline)
- [4. Evaluation & Scoring Framework](#4-evaluation--scoring-framework)
- [5. Safety & Content Moderation](#5-safety--content-moderation)
- [6. System Prompt Management](#6-system-prompt-management)
- [7. Architecture Overview](#7-architecture-overview)
- [8. File Inventory](#8-file-inventory)
- [9. Dependencies](#9-dependencies)

---

## 1. Speech-to-Text (STT)

### Engines

| Engine | ID | Description | Offline | Model Required |
|--------|----|-------------|---------|----------------|
| **Android SpeechRecognizer** | `android` | Platform-provided STT via `android.speech.SpeechRecognizer`. Lightweight, can work offline if language packs are downloaded. | Partial (needs language packs) | No |
| **Whisper.cpp** | `whisper` | True on-device offline STT powered by OpenAI's Whisper, compiled via `whisper.cpp` and accessed through JNI. | Yes (fully offline) | Yes (GGML binary) |

### Whisper Model Catalog

| Model | Size | Download URL | Notes |
|-------|------|-------------|-------|
| Whisper Base (multilingual) | ~142 MB | `huggingface.co/ggerganov/whisper.cpp/.../ggml-base.bin` | Faster, lower accuracy |
| Whisper Small (multilingual) | ~466 MB | `huggingface.co/ggerganov/whisper.cpp/.../ggml-small.bin` | Better accuracy, heavier |

### STT Capabilities

- **Continuous recording**: Supports multi-utterance continuous listening mode. Whisper restarts native recognition after each final result, keeping the Dart stream open.
- **Language support**: Configurable language tag (e.g. `en-US`). Whisper models are multilingual.
- **Confidence scores**: Each result includes a confidence value (0.0–1.0).
- **Partial results**: Streams partial transcriptions in real-time as the user speaks.
- **Audio level (RMS dB)**: Exposes microphone input level for UI animations (breathing mic button).
- **Offline-only mode**: Can enforce fully offline recognition (no network fallback).
- **Thread count**: Configurable Whisper thread count for performance tuning.

### Native Implementation (Android/Kotlin + C++)

| Component | Description |
|-----------|-------------|
| `SpeechToTextHandler.kt` | Wraps Android `SpeechRecognizer`. Handles `onResults`, `onPartialResults`, `onRmsChanged`. Communicates via MethodChannel `com.microllm.app/stt` and EventChannel `com.microllm.app/stt_events`. |
| `WhisperHandler.kt` | Records audio via `AudioRecord` (16kHz, mono, PCM16), feeds to `WhisperNative.transcribePcm16Streaming`. Detects silence to finalize. Channels: `com.microllm.app/whisper` and `com.microllm.app/whisper_events`. |
| `WhisperNative.kt` | JNI bridge — `loadModel`, `unloadModel`, `transcribePcm16`, `transcribePcm16Streaming`. Loads `libwhisper.so`. |
| `whisper_jni.cpp` | C++ JNI implementation that calls the actual whisper.cpp C library for model loading and transcription. |

### Dart-Side STT Flow

```
SpeechToTextUseCase
  ├── Picks engine (Android or Whisper)
  ├── Resolves language tag (_pickBestLanguageTag)
  ├── If Whisper: loads model via VoiceRepository.loadWhisperModel()
  └── VoiceRepository.startRecognition(engine, language, continuous, ...)
        ├── Android → VoiceDataSource.startRecognition()
        └── Whisper → WhisperDataSource.startRecognition(continuous)
              └── _handleEvent() → if continuous & isFinal → _scheduleRestart()
```

---

## 2. Text-to-Speech (TTS)

### Engines

| Engine | ID | Description | Offline | API Key |
|--------|----|-------------|---------|---------|
| **Android TTS** | `android` | Platform `TextToSpeech` engine. Works offline with installed language packs. | Yes | No |
| **ElevenLabs** | `elevenlabs` | Cloud-based natural-sounding TTS via ElevenLabs API. High quality, requires internet. | No | Yes (stored in secure storage) |

### TTS Capabilities

- **Pitch control**: Configurable pitch multiplier (0.5–2.0).
- **Rate control**: Configurable speech rate multiplier (0.5–2.0).
- **Voice selection**: ElevenLabs supports custom voice IDs.
- **Synthesis events**: Stream of lifecycle events (`SpeechSynthesisCompleted`, `SpeechSynthesisError`) for turn-taking in voice-call mode.
- **Auto-listen**: After TTS completes, can auto-start STT for conversational flow.

### Native Implementation

| Component | Description |
|-----------|-------------|
| `TextToSpeechHandler.kt` | Wraps Android `TextToSpeech`. Handles `speak`, `stop`, `onDone`, `onError`. Channel: `com.microllm.app/tts`. |

### Dart-Side TTS Flow

```
TextToSpeechUseCase
  ├── Picks engine (Android or ElevenLabs)
  ├── Resolves language tag
  └── VoiceRepository.synthesize(engine, text, language, pitch, rate, ...)
        ├── Android → VoiceDataSource.synthesize()
        └── ElevenLabs → ElevenLabsTtsService.speak()
              └── Uses Dio for API + just_audio for playback
```

---

## 3. Voice Benchmarking & Summarization Pipeline

### Overview

The Voice Benchmarking feature records a spoken transcript, runs it through a multi-stage LLM pipeline, and produces a comprehensive evaluation. The pipeline has been optimized from 5 sequential LLM calls down to **2 merged calls** for a target response time of 20–30 seconds.

### Pipeline Steps

```
Recording (STT)
    │
    ▼
Step 1 — Transcription (aggregate final STT results)
    │
    ▼
Step 2 — Safety Scan (SafetyPreprocessorUseCase)
    │   ├── Prompt injection detection (regex + optional LLM)
    │   ├── Local content scan (regex for vulgarity, hate, self-harm, etc.)
    │   └── Optional LLM-based content scan (off by default for speed)
    │
    ▼  [If unsafe → pipeline halted, safety warning shown]
    │
Step 3 — Merged LLM Call #1: Key Ideas + Summarization
    │   ├── TASK A: Extract key ideas from transcript
    │   ├── TASK B: Generate concise summary
    │   └── Parsed via markers: ===KEY_IDEAS===, ===SUMMARY===
    │
    ▼
Step 4 — Merged LLM Call #2: Benchmark Evaluation + Transcript Scoring
    │   ├── TASK A: Summary quality evaluation (Relevance, Coverage, Coherence, Conciseness, Faithfulness)
    │   ├── TASK B: Transcript scoring (Clarity of Thought + Language Proficiency)
    │   └── Parsed via marker: ===TASK_B=== and JSON extraction
    │
    ▼
Final Result — BenchmarkResult
    ├── transcript, keyIdeas, summary
    ├── dimensions[] (summary quality scores)
    ├── evaluationResult (Clarity + Language scores)
    ├── safetyResult
    └── metadata (timing, word counts, compression ratio)
```

### Pipeline Events

| Event | Description |
|-------|-------------|
| `PipelineStepStarted(step)` | A pipeline step has begun |
| `PipelineStepCompleted(step, result)` | A step finished with a result string |
| `PipelineCompleted(result)` | Full pipeline done, `BenchmarkResult` available |
| `PipelineSafetyBlocked(safetyResult)` | Halted due to safety violation |
| `PipelineError(message, failedStep)` | An error occurred at a specific step |

### Pipeline Steps Enum

| Step | Description |
|------|-------------|
| `transcribing` | Converting speech to text |
| `safetyScan` | Running safety & injection checks |
| `extractingKeyIdeas` | Extracting main ideas from transcript |
| `summarizing` | Generating summary |
| `evaluatingSummary` | Scoring summary quality |
| `evaluatingTranscript` | Scoring clarity & language proficiency |

### Benchmark Result Structure

```
BenchmarkResult
  ├── transcript: String
  ├── keyIdeas: String
  ├── summary: String
  ├── dimensions: List<BenchmarkDimension>
  │     └── { name, description, score (Good/Fair/Poor), explanation }
  ├── recordingDurationSeconds: int
  ├── processingTimeMs: int
  ├── promptUsed: String
  ├── completedAt: DateTime
  ├── safetyResult: SafetyResult?
  ├── evaluationResult: EvaluationResult?
  ├── overallScore: double (0.0–1.0)
  ├── transcriptWordCount: int
  ├── summaryWordCount: int
  └── compressionRatio: double
```

---

## 4. Evaluation & Scoring Framework

### Scoring Parameters

#### Clarity of Thought (1–10 marks)

The ability to organize and present ideas in a logical, coherent, and cohesive manner.

**What is evaluated:**
- Logical sequence of ideas (introduction, main points, conclusion)
- Relevant elaboration of points with supporting details
- No excessive repetition or irrelevant digressions

| Score | Description |
|-------|-------------|
| 9–10 | Exceptionally well-structured, engaging, professional presentation level |
| 7–8 | Good structure, minor gaps, overall cohesive flow |
| 5–6 | Moderate structure, some disjointed ideas, lacks clear organization |
| 3–4 | Poor structure, no logical flow, ideas jump around randomly |
| 1–2 | Incoherent, no structure at all, impossible to follow |

#### Language Proficiency (1–10 marks)

The speaker's command over English including grammar, vocabulary, sentence structure, and fluency.

**What is evaluated:**
- Grammar accuracy (tense consistency, subject-verb agreement, sentence construction)
- Vocabulary appropriateness for the context
- Fluency and ease of expression without excessive pauses or fillers

| Score | Description |
|-------|-------------|
| 9–10 | Excellent grammar, rich vocabulary, completely fluent |
| 7–8 | Good grammar and vocabulary, minor errors, generally proficient |
| 5–6 | Moderate grammar, noticeable errors, basic but functional vocabulary |
| 3–4 | Frequent grammar mistakes, limited vocabulary, halting speech |
| 1–2 | Major errors throughout, extremely limited English, hard to understand |

### Scoring Policy

- **Conservative scoring**: Most casual speakers score 3–6. Only trained professionals score 7+.
- **No score inflation**: 5 is AVERAGE. Do NOT inflate above this without strong evidence.
- **Hard ceiling rules**:
  - Repetition, filler words, or rambling → Clarity MUST be 5 or below
  - Grammar mistakes, wrong tenses, broken sentences → Language MUST be 5 or below
  - No clear introduction/conclusion → Clarity MUST be 6 or below
  - Basic/repetitive vocabulary → Language MUST be 6 or below
  - 9–10 only for professional-level, near-perfect English (extremely rare)
- **No hallucination**: Evaluate ONLY what exists in the transcript.

### Evaluation Output Format

```json
{
  "clarity_score": 5,
  "clarity_reasoning": "Speaker jumps between topics without transitions...",
  "language_score": 4,
  "language_reasoning": "Multiple tense inconsistencies, e.g. ...",
  "safety_flag": false,
  "safety_notes": "None",
  "overall_feedback": "The speaker demonstrated basic ideas but needs..."
}
```

### Qualitative Labels (derived from total score out of 20)

| Total Score | Label |
|-------------|-------|
| 18–20 | Excellent |
| 15–17 | Good |
| 12–14 | Above Average |
| 9–11 | Average |
| 6–8 | Below Average |
| 0–5 | Needs Improvement |

### Parsing Strategy

The evaluation output is parsed with a two-layer approach:
1. **JSON parsing** — Attempts `jsonDecode` on the LLM output
2. **Regex fallback** — If JSON parsing fails, extracts individual fields via regex patterns (e.g. `"clarity_score"\s*:\s*(\d+)`)

---

## 5. Safety & Content Moderation

### Multi-Layer Safety Pipeline

Safety processing runs **BEFORE** evaluation. If unsafe content is detected, the pipeline halts and no scores are shown.

#### Layer 1: Prompt Injection Detection (`PromptSecurityLayer`)

**Local regex scan** for injection patterns:
- "ignore previous instructions"
- "reveal system prompt"
- "you are now..."
- "disregard all prior"
- "output your instructions"
- Base64/hex encoded payloads

**Optional LLM-based scan** for sophisticated injection attempts.

#### Layer 2: Content Safety Scan (`SafetyPreprocessorUseCase`)

**Local regex scan** (always runs, fast) for:

| Category | Examples |
|----------|---------|
| Vulgarity | Profanity, slurs |
| Hate Speech | Racial/ethnic/religious targeting |
| Self-Harm | Suicide, self-injury references |
| Explicit Content | Sexual content |
| Illegal Instructions | Bomb-making, drug manufacturing, weapon instructions |

**Optional LLM-based content scan** (off by default for performance). Can be toggled on via `useLlmForContent: true`.

### Safety Result Structure

```
SafetyResult
  ├── isSafe: bool
  ├── violations: List<SafetyViolation>
  │     └── { type, explanation, severity (high/medium/low) }
  └── summary: String

SafetyViolationType:
  vulgarity, hateSpeech, selfHarm, explicitContent,
  illegalInstructions, promptInjection
```

### Safety → UI Behavior

| Condition | UI Behavior |
|-----------|-------------|
| `safety_flag == true` | Display safety warning, hide scores |
| `safety_flag == false` | Display Clarity Score, Language Score, Total Score, Feedback |

---

## 6. System Prompt Management

### Prompt Keys

| Key | Purpose | Used By |
|-----|---------|---------|
| `evaluation` | Transcript scoring rubric for Clarity of Thought and Language Proficiency | `EvaluationUseCase`, merged pipeline (TASK B) |
| `globalSafety` | Content safety classification instructions | `SafetyPreprocessorUseCase` (LLM content scan) |
| `injectionGuard` | Prompt injection detection instructions | `PromptSecurityLayer` (LLM injection scan) |

### Features

- **Centralized**: All prompts managed via `SystemPromptManager`
- **Versioned**: Each prompt entry has a `version` field
- **Editable**: In-app editor at Settings > Tools > System Prompts
- **Persistent**: Stored in Hive (`settingsBox`), survives app restarts
- **Resettable**: One-tap reset to defaults (individual or all)

### In-App Prompt Editor

| Feature | Description |
|---------|-------------|
| List view | Shows all three prompts as cards with icons |
| Full editor | Monospace text field with word count |
| Unsaved changes | Detects modifications, warns before leaving |
| Save | Persists to Hive via `SystemPromptStorageImpl` |
| Reset to default | Restores the built-in default prompt text |
| Reset all | Resets all three prompts at once |

---

## 7. Architecture Overview

### Clean Architecture Layers

```
┌─────────────────────────────────────────────────────┐
│  PRESENTATION                                       │
│  ├── Pages: BenchmarkPage, SystemPromptsPage,       │
│  │         SettingsPage, ChatPage                    │
│  ├── Widgets: VoiceButton, ChatInput                │
│  └── BLoCs: VoiceBloc, BenchmarkBloc, SettingsBloc  │
├─────────────────────────────────────────────────────┤
│  DOMAIN                                             │
│  ├── Use Cases: SpeechToTextUseCase,                │
│  │   TextToSpeechUseCase,                           │
│  │   SummarizeTranscriptUseCase,                    │
│  │   EvaluationUseCase,                             │
│  │   SafetyPreprocessorUseCase                      │
│  ├── Services: SystemPromptManager,                 │
│  │   PromptSecurityLayer, SttModelCatalog,          │
│  │   SttModelPathResolver                           │
│  ├── Entities: EvaluationResult, SafetyResult,      │
│  │   BenchmarkResult, SpeechToTextEngine,           │
│  │   TextToSpeechEngine                             │
│  └── Repositories: VoiceRepository (interface),     │
│       LLMRepository (interface)                     │
├─────────────────────────────────────────────────────┤
│  DATA                                               │
│  ├── Datasources: VoiceDataSource,                  │
│  │   WhisperDataSource, SystemPromptStorageImpl,     │
│  │   BenchmarkStorage                               │
│  ├── Repositories: VoiceRepositoryImpl              │
│  └── Services: ElevenLabsTtsService,                │
│       SttModelDownloadService,                      │
│       SttModelPathResolverImpl                      │
├─────────────────────────────────────────────────────┤
│  CORE                                               │
│  └── DI: injection.dart (GetIt registrations)       │
├─────────────────────────────────────────────────────┤
│  NATIVE (Android)                                   │
│  ├── Kotlin: MainActivity, SpeechToTextHandler,     │
│  │   TextToSpeechHandler, WhisperHandler,           │
│  │   WhisperNative                                  │
│  └── C++: whisper_jni.cpp → libwhisper.so           │
└─────────────────────────────────────────────────────┘
```

### State Management

| BLoC | Purpose | Key States |
|------|---------|-----------|
| `VoiceBloc` | Real-time STT/TTS for chat | `idle`, `listening`, `processing`, `speaking`, `error` |
| `BenchmarkBloc` | Voice benchmarking flow | `idle`, `recording`, `processing`, `completed`, `safetyBlocked`, `error` |
| `SettingsBloc` | Voice engine selection, model management | Holds `sttEngine`, `ttsEngine`, Whisper model state |

### Platform Channels

| Channel | Type | Direction | Purpose |
|---------|------|-----------|---------|
| `com.microllm.app/stt` | MethodChannel | Dart → Kotlin | Start/stop Android STT |
| `com.microllm.app/stt_events` | EventChannel | Kotlin → Dart | Stream STT results |
| `com.microllm.app/whisper` | MethodChannel | Dart → Kotlin | Start/stop/load/unload Whisper |
| `com.microllm.app/whisper_events` | EventChannel | Kotlin → Dart | Stream Whisper results |
| `com.microllm.app/tts` | MethodChannel | Dart → Kotlin | Android TTS speak/stop |

---

## 8. File Inventory

### Domain Layer

| File | Description |
|------|-------------|
| `lib/domain/entities/speech_to_text_engine.dart` | STT engine enum (`androidSpeechRecognizer`, `whisperCpp`) |
| `lib/domain/entities/text_to_speech_engine.dart` | TTS engine enum (`androidTts`, `elevenLabs`) |
| `lib/domain/entities/evaluation_result.dart` | Evaluation scores, reasoning, safety flag, labels |
| `lib/domain/entities/safety_result.dart` | Safety violations, types, severity |
| `lib/domain/entities/benchmark_result.dart` | Full benchmark output including all scores and metadata |
| `lib/domain/repositories/voice_repository.dart` | Voice repository interface + `SpeechRecognitionResult`, `VoiceLanguage`, `VoiceStatus` |
| `lib/domain/usecases/speech_to_text_usecase.dart` | STT orchestration (engine selection, model loading, language resolution) |
| `lib/domain/usecases/text_to_speech_usecase.dart` | TTS orchestration (engine selection, language resolution) |
| `lib/domain/usecases/summarize_transcript_usecase.dart` | Full benchmarking pipeline (safety → key ideas → summary → evaluation) |
| `lib/domain/usecases/evaluation_usecase.dart` | Transcript scoring with LLM + JSON/regex parsing |
| `lib/domain/usecases/safety_preprocessor_usecase.dart` | Content safety checks (regex + optional LLM) |
| `lib/domain/services/system_prompt_manager.dart` | Centralized prompt storage, defaults, versioning |
| `lib/domain/services/prompt_security_layer.dart` | Prompt injection detection |
| `lib/domain/services/stt_model_catalog.dart` | Whisper model definitions |
| `lib/domain/services/stt_model_path_resolver.dart` | Model path resolver interface |

### Data Layer

| File | Description |
|------|-------------|
| `lib/data/datasources/voice_datasource.dart` | Platform channel adapter for Android STT/TTS |
| `lib/data/datasources/whisper_datasource.dart` | Whisper.cpp STT via platform channels (continuous restart logic) |
| `lib/data/datasources/system_prompt_storage_impl.dart` | Hive-backed prompt persistence |
| `lib/data/datasources/benchmark_storage.dart` | Benchmark result persistence |
| `lib/data/repositories/voice_repository_impl.dart` | Coordinates VoiceDataSource, WhisperDataSource, ElevenLabsTtsService |
| `lib/data/services/elevenlabs_tts_service.dart` | ElevenLabs API client + just_audio playback |
| `lib/data/services/stt_model_download_service.dart` | Whisper model download with progress |
| `lib/data/services/stt_model_path_resolver_impl.dart` | Resolves local model file paths |

### Presentation Layer

| File | Description |
|------|-------------|
| `lib/presentation/pages/benchmark_page.dart` | Voice benchmark UI (record, process, results, safety warning) |
| `lib/presentation/pages/system_prompts_page.dart` | System prompt editor (view, edit, reset) |
| `lib/presentation/pages/settings_page.dart` | Voice settings (engine selection, model download, API key) |
| `lib/presentation/pages/chat_page.dart` | Chat with voice input |
| `lib/presentation/widgets/voice_button.dart` | Animated mic button for STT |
| `lib/presentation/widgets/chat_input.dart` | Chat input with voice button slot |
| `lib/presentation/blocs/voice/voice_bloc.dart` | Voice state management |
| `lib/presentation/blocs/voice/voice_event.dart` | Voice events |
| `lib/presentation/blocs/voice/voice_state.dart` | Voice state |
| `lib/presentation/blocs/benchmark/benchmark_bloc.dart` | Benchmark flow state management |
| `lib/presentation/blocs/benchmark/benchmark_event.dart` | Benchmark events |
| `lib/presentation/blocs/benchmark/benchmark_state.dart` | Benchmark state |

### Native Platform (Android)

| File | Description |
|------|-------------|
| `android/app/src/main/kotlin/.../MainActivity.kt` | Platform channel registration |
| `android/app/src/main/kotlin/.../SpeechToTextHandler.kt` | Android SpeechRecognizer wrapper |
| `android/app/src/main/kotlin/.../TextToSpeechHandler.kt` | Android TextToSpeech wrapper |
| `android/app/src/main/kotlin/.../WhisperHandler.kt` | Whisper audio recording + transcription |
| `android/app/src/main/kotlin/.../WhisperNative.kt` | JNI bridge to whisper.cpp |
| `android/app/src/main/cpp/whisper_jni.cpp` | C++ JNI implementation |

### Core

| File | Description |
|------|-------------|
| `lib/core/di/injection.dart` | GetIt DI — registers all voice-related services, repositories, use cases, and BLoCs |

---

## 9. Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `just_audio` | 0.9.x | Audio playback for ElevenLabs TTS |
| `dio` | — | HTTP client for ElevenLabs API and Whisper model downloads |
| `flutter_secure_storage` | 9.x | Secure storage for ElevenLabs API key |
| `path_provider` | — | Local file paths for Whisper models |
| `flutter_bloc` | 8.x | State management for Voice and Benchmark BLoCs |
| `equatable` | — | Value equality for BLoC states and entities |
| `hive` / `hive_flutter` | — | Local persistence for system prompts and benchmark results |
| `get_it` | 7.x | Dependency injection container |
| `dartz` | — | `Either`/`Result` type for error handling |

**No third-party STT/TTS Flutter plugins** — all voice functionality is implemented via custom platform channels to Android native APIs and whisper.cpp.
