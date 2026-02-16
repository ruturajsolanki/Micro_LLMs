# V2: Cloud-First Voice Evaluation App

## Core Concept

V2 shifts from on-device Phi-2 inference to **cloud LLM processing** via Groq and Gemini APIs, with dramatically better scoring accuracy and faster response times. The UX is simplified to a single-flow: **open app → cloud check → mic → speak → stop → results**.

All V1 features (local LLM, on-device Whisper, settings, safety framework) remain in the codebase but are **hidden behind settings** — the default experience is cloud-powered.

---

## Bundled API Key Strategy (Zero-Friction Onboarding)

The app ships with a **bundled default Groq API key** so users can start immediately without any setup. The key is secured through multiple layers:

### Security Layers

1. **Compile-time injection** — The key is passed via `--dart-define-from-file=.env` at build time. It lives in a `.env` file that is **gitignored** (never committed to source control).
2. **XOR obfuscation** — The key is not stored as a plain string in the binary. A `KeyObfuscator` utility XOR-encodes it at build time and decodes at runtime, so decompiling the APK won't reveal the key in a simple strings search.
3. **Flutter obfuscation** — Release builds use `--obfuscate --split-debug-info=build/debug-info` which mangles Dart symbols, making reverse engineering significantly harder.
4. **Rate limiting on server side** — The bundled key should have usage limits/quotas configured on the Groq dashboard to cap abuse if extracted.
5. **Key rotation** — The bundled key can be rotated with each app update. Old keys are revoked server-side.

### Startup Flow with Bundled Key

```
App Opens
  → Try bundled (default) API key
    → Ping Groq API with bundled key
      → SUCCESS → Proceed to V2 Home (user never sees setup)
      → FAIL (key revoked/quota exceeded/network error)
        → Check if user has a saved personal key
          → YES → Try personal key
            → SUCCESS → Proceed to V2 Home
            → FAIL → Show API Setup Page
          → NO → Show API Setup Page with message:
                  "Default key unavailable. Enter your own Groq API key to continue."
```

### Key Priority Order

1. **User's personal key** (if saved) — always preferred over bundled key
2. **Bundled default key** — fallback for zero-setup experience
3. **No key** — show API Setup Page

This means: if a user has entered their own key, we always use that. The bundled key is only the "out of the box" experience.

---

## Architecture

```mermaid
flowchart TD
    AppOpen[App Opens] --> KeyCheck{Personal API Key Saved?}
    KeyCheck -->|Yes| ValidatePersonal{Validate Personal Key}
    KeyCheck -->|No| TryBundled{Try Bundled Default Key}
    ValidatePersonal -->|Valid| HomeReady[V2 Home - Mic Ready]
    ValidatePersonal -->|Invalid| TryBundled
    TryBundled -->|Valid| HomeReady
    TryBundled -->|Invalid/Missing| SetupPage["API Setup Page<br/>(Default key unavailable)"]
    SetupPage --> HomeReady
    HomeReady --> Recording[User Speaks ~2 min]
    Recording --> StopRec[User Stops]
    StopRec --> CloudSTT["Groq Whisper API (transcribe audio file)"]
    StopRec -.->|Offline| LocalSTT["Local Whisper.cpp (fallback)"]
    CloudSTT --> SafetyScan[Safety Scan - local regex]
    LocalSTT --> SafetyScan
    SafetyScan -->|Safe| CloudEval["Groq / Gemini LLM (evaluate + summarize)"]
    SafetyScan -->|Unsafe| Blocked[Safety Warning]
    CloudEval --> Results[Display Scores + Feedback]
```

---

## Key Architectural Decisions

- **LLMRepository interface stays unchanged** — we create a new `CloudLLMRepositoryImpl` that implements the same interface, so all existing use cases (`SummarizeTranscriptUseCase`, `EvaluationUseCase`, `SafetyPreprocessorUseCase`) work with zero changes.
- **Cloud STT is batch, not streaming** — user records audio to a temp WAV file, then we upload it to Groq's Whisper API. This gives superior accuracy with punctuation and filler word capture.
- **DI swap** — the DI container registers either the local or cloud `LLMRepository` implementation based on settings. A `CloudConnectivityChecker` validates API reachability at startup.
- **Audio recording** — new `AudioRecorderService` that records raw PCM and encodes to WAV for upload (reuses existing `AudioRecord` native code but saves to file instead of streaming to local Whisper).
- **Bundled key with graceful fallback** — the app ships with a default Groq key compiled into the binary (obfuscated). If the bundled key fails validation, the user is prompted to enter their own key. This removes the setup friction for new users.

---

## Cloud APIs

**Groq** (`https://api.groq.com/openai/v1`):

- `POST /audio/transcriptions` — Whisper Large V3 Turbo for STT (accepts WAV/MP3, returns text with punctuation and fillers)
- `POST /chat/completions` — Llama 3.3 70B for evaluation/summary (OpenAI-compatible format)

**Gemini** (`https://generativelanguage.googleapis.com/v1beta`):

- `POST /models/{model}:generateContent` — Gemini 2.0 Flash for evaluation/summary

Both are user-selectable in settings. Groq is default.

---

## New Files to Create

### Core — Environment & Security

- **`lib/core/config/env_config.dart`** — Reads bundled API keys from `--dart-define` compile-time constants. Provides `EnvConfig.bundledGroqApiKey` and `EnvConfig.bundledGeminiApiKey` (nullable — empty if not provided at build time). These are the obfuscated values that get decoded at runtime.

- **`lib/core/config/key_obfuscator.dart`** — Simple XOR-based obfuscation utility. Two methods:
  - `obfuscate(String plainKey, String salt)` → `String` (base64-encoded XOR result)
  - `deobfuscate(String obfuscatedKey, String salt)` → `String`

  The salt is a non-secret app identifier (e.g., package name hash). This ensures the key isn't a raw plaintext string in the compiled binary. **Not encryption** — just enough to defeat `strings` and casual APK decompiling.

- **`lib/core/config/api_key_manager.dart`** — Central manager that resolves which API key to use. Logic:
  1. Check `FlutterSecureStorage` for a user-saved personal key → use it if present
  2. Fall back to `EnvConfig.bundledGroqApiKey` (deobfuscated) → use it if non-empty
  3. Return `null` if neither is available (triggers API Setup Page)

  Also provides: `savePersonalKey(key)`, `clearPersonalKey()`, `hasPersonalKey`, `getActiveKeySource()` → `KeySource.personal | KeySource.bundled | KeySource.none`

- **`.env.example`** — Template file committed to repo (the actual `.env` is gitignored):
  ```
  # Bundled API keys (compile-time, obfuscated in binary)
  # Copy this file to .env and fill in your keys
  # NEVER commit the .env file!
  GROQ_API_KEY=gsk_your_groq_api_key_here
  GEMINI_API_KEY=your_gemini_api_key_here
  ```

### Domain Layer

- **`lib/domain/entities/cloud_provider.dart`** — `CloudLLMProvider` enum (`groq`, `gemini`) and `CloudSttProvider` enum (`groqWhisper`, `localWhisper`)

- **`lib/domain/entities/key_source.dart`** — `KeySource` enum (`bundled`, `personal`, `none`) — indicates where the active API key came from. Displayed in settings so the user knows if they're using the bundled key or their own.

### Data Layer — Cloud Services

- **`lib/data/services/groq_api_service.dart`** — Dio-based client for Groq (chat completions + Whisper STT). Maps `InferenceRequest` → Groq request format, Groq response → `InferenceResponse`. Accepts API key via constructor (injected by `ApiKeyManager`).
- **`lib/data/services/gemini_api_service.dart`** — Dio-based client for Gemini `generateContent`. Maps `InferenceRequest` → Gemini format.
- **`lib/data/services/cloud_api_key_storage.dart`** — Stores user's personal Groq/Gemini API keys in `FlutterSecureStorage` (same pattern as existing ElevenLabs key storage).
- **`lib/data/services/cloud_connectivity_checker.dart`** — Validates API key + connectivity. Takes a key string and pings the API. Used at startup to validate both bundled and personal keys. Returns `ConnectivityResult` with status and which key source succeeded.

### Data Layer — Repositories

- **`lib/data/repositories/cloud_llm_repository_impl.dart`** — Implements `LLMRepository`. Gets the active API key from `ApiKeyManager`. Delegates `generate()` to either `GroqApiService` or `GeminiApiService` based on `AppSettings.cloudLLMProvider`. `loadModel`/`unloadModel` are no-ops. `isModelLoaded` returns `true` when a valid API key is available (bundled or personal).

### Data Layer — Audio

- **`lib/data/datasources/audio_recorder_service.dart`** — Records microphone audio to a temp WAV file on disk (for cloud STT upload). Uses existing native `AudioRecord` infrastructure via a new platform channel method `recordToFile`/`stopRecording`.

### Presentation — V2 Pages

- **`lib/presentation/pages/v2_home_page.dart`** — The simplified single-screen V2 experience: cloud status indicator at top (shows "Using bundled key" or "Using your key" chip), large mic button center, results panel below. States: `ready` → `recording` → `transcribing` → `processing` → `results`.
- **`lib/presentation/pages/api_setup_page.dart`** — Shown **only when the bundled key fails**. Message at top: "The default API key is currently unavailable. Enter your own Groq API key to continue." Fields: Groq API key (required), optional Gemini key. Validates key by pinging API. Clean, minimal UI with a "Get a free API key" link to Groq's console.

### Presentation — V2 BLoC

- **`lib/presentation/blocs/v2_session/v2_session_bloc.dart`** — Manages the V2 flow state machine (idle → recording → transcribing → evaluating → done). Orchestrates audio recording, cloud STT, and cloud evaluation pipeline. At initialization, resolves the active key via `ApiKeyManager`.
- **`lib/presentation/blocs/v2_session/v2_session_event.dart`** — Events: `V2SessionStartRecording`, `V2SessionStopRecording`, `V2SessionReset`
- **`lib/presentation/blocs/v2_session/v2_session_state.dart`** — States with `status`, `transcript`, `evaluationResult`, `elapsedTime`, `error`, `keySource`

---

## Files to Modify

### `lib/domain/entities/app_settings.dart`

Add new fields:

- `cloudLLMProvider` (`CloudLLMProvider`, default `groq`)
- `cloudSttProvider` (`CloudSttProvider`, default `groqWhisper`)
- `useCloudProcessing` (`bool`, default `true` in V2)

### `lib/presentation/blocs/settings/settings_event.dart` / `settings_bloc.dart`

Add events: `CloudLLMProviderChanged`, `CloudSttProviderChanged`, `UseCloudProcessingToggled`

### `lib/core/di/injection.dart`

Register: `KeyObfuscator`, `ApiKeyManager`, `GroqApiService`, `GeminiApiService`, `CloudApiKeyStorage`, `CloudConnectivityChecker`, `CloudLLMRepositoryImpl`, `AudioRecorderService`, `V2SessionBloc`. The `ApiKeyManager` is registered as a singleton (needs to resolve key once at startup). Use a factory to register the appropriate `LLMRepository` (local vs cloud) or register both and let use cases pick via a wrapper.

### `lib/main.dart`

- Add V2 routes: `/v2-home`, `/api-setup`
- **Startup key resolution**: Before showing any UI, call `ApiKeyManager.resolveActiveKey()` which tries personal key → bundled key → none. Based on the result:
  - `KeySource.personal` or `KeySource.bundled` → show `V2HomePage`
  - `KeySource.none` → show `ApiSetupPage`
- Register `V2SessionBloc` in `MultiBlocProvider`

### `lib/core/constants/app_constants.dart`

Add to `StorageConstants`:

- `groqApiKey` — secure storage key for user's personal Groq key
- `geminiApiKey` — secure storage key for user's personal Gemini key

### `lib/presentation/pages/settings_page.dart`

Add a "Cloud" section:

- Cloud LLM provider picker (Groq / Gemini)
- Cloud STT toggle (Groq Whisper / Local Whisper)
- Groq API key field (shows "Using bundled key" or the user's masked key)
- Gemini API key field
- "Use cloud processing" master toggle
- Key source indicator (chip showing `Bundled` / `Personal`)
- "Reset to bundled key" button (clears personal key, reverts to bundled)

### Native Android — `WhisperHandler.kt`

Add a `recordToFile(path)` / `stopRecording()` method pair that saves raw PCM as WAV to a given file path (instead of streaming to JNI Whisper). This reuses the existing `AudioRecord` setup.

### `lib/domain/services/system_prompt_manager.dart`

Add cloud-optimized evaluation prompt — since cloud models (Llama 70B, Gemini 2.0 Flash) are far more capable than Phi-2 Q4, we can use a richer, more detailed prompt without token-count concerns. The stricter scoring rules will actually work properly with these models.

---

## Build Configuration

### `.env` File (gitignored — developer must create locally)

```env
GROQ_API_KEY=gsk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
GEMINI_API_KEY=AIzaSyxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### Build Commands

**Debug (with bundled keys):**
```bash
flutter run --dart-define-from-file=.env
```

**Release (with obfuscation):**
```bash
flutter build apk --release \
  --dart-define-from-file=.env \
  --obfuscate \
  --split-debug-info=build/debug-info
```

**Without bundled keys (falls back to user-provided only):**
```bash
flutter run  # Works fine, just skips bundled key
```

### `EnvConfig` Implementation Pattern

```dart
abstract final class EnvConfig {
  // Read from --dart-define at compile time
  static const String _rawGroqKey = String.fromEnvironment('GROQ_API_KEY');
  static const String _rawGeminiKey = String.fromEnvironment('GEMINI_API_KEY');

  // Obfuscated at compile time, decoded at runtime
  static String? get bundledGroqApiKey =>
      _rawGroqKey.isEmpty ? null : KeyObfuscator.deobfuscate(_rawGroqKey);

  static String? get bundledGeminiApiKey =>
      _rawGeminiKey.isEmpty ? null : KeyObfuscator.deobfuscate(_rawGeminiKey);

  static bool get hasBundledGroqKey => _rawGroqKey.isNotEmpty;
  static bool get hasBundledGeminiKey => _rawGeminiKey.isNotEmpty;
}
```

### `ApiKeyManager` Implementation Pattern

```dart
class ApiKeyManager {
  final CloudApiKeyStorage _storage;

  Future<(String? key, KeySource source)> resolveGroqKey() async {
    // 1. Try user's personal key first
    final personalKey = await _storage.getGroqApiKey();
    if (personalKey != null && personalKey.isNotEmpty) {
      return (personalKey, KeySource.personal);
    }

    // 2. Fall back to bundled key
    final bundledKey = EnvConfig.bundledGroqApiKey;
    if (bundledKey != null && bundledKey.isNotEmpty) {
      return (bundledKey, KeySource.bundled);
    }

    // 3. No key available
    return (null, KeySource.none);
  }
}
```

---

## V2 Pipeline Comparison

**V1 (local, ~25-33s):**

- Local Whisper.cpp streaming STT → 5-step local Phi-2 pipeline (merged to 2 LLM calls) → results

**V2 (cloud, target ~8-15s):**

- Record audio to WAV file (~2min recording)
- Upload to Groq Whisper API (~2-4s for a 2min clip)
- Single cloud LLM call for everything: summary + key ideas + clarity score + language score + feedback (~4-8s on Groq Llama 70B)
- Total: ~6-12s processing after recording stops

---

## V2 Home Page UX Flow

```mermaid
stateDiagram-v2
    [*] --> ResolvingKey: App opens
    ResolvingKey --> Ready: Key valid (bundled or personal)
    ResolvingKey --> ApiSetup: No valid key found
    ApiSetup --> Ready: User enters valid key
    Ready --> Recording: Tap mic
    Recording --> Recording: Timer counting up
    Recording --> Transcribing: Tap stop
    Transcribing --> Processing: Transcript received
    Processing --> Results: Scores ready
    Results --> Ready: Tap "New Session"
```

**Resolving Key state:** Brief splash/loading while `ApiKeyManager` tries bundled → personal key. Invisible if fast (<500ms).
**Ready state:** Cloud status chip (green, shows key source), large animated mic button, "Tap to start" hint.
**Recording state:** Pulsing mic, live timer, audio waveform visualization, stop button.
**Transcribing state:** "Transcribing..." with spinner, shows which STT engine is being used.
**Processing state:** "Evaluating..." with pipeline progress steps.
**Results state:** Clarity score card, Language score card, total score, feedback panel, transcript expandable, "New Session" button.
**API Setup state:** Only shown when bundled key fails. Clean form with explanation, Groq key field, validate button, link to get free key.
