package com.microllm.app

/**
 * Native JNI bindings to whisper.cpp for offline speech-to-text.
 *
 * This library is optional at build time:
 * - If whisper.cpp sources are present, `isAvailable()` returns true and STT works fully offline.
 * - Otherwise, a stub lib is built and `isAvailable()` returns false.
 */
object WhisperNative {

    init {
        try {
            System.loadLibrary("whisper")
            android.util.Log.i("WhisperNative", "Loaded libwhisper.so")
        } catch (e: UnsatisfiedLinkError) {
            android.util.Log.e("WhisperNative", "Failed to load whisper library: ${e.message}")
        }
    }

    @JvmStatic
    external fun isAvailable(): Boolean

    @JvmStatic
    external fun loadModel(modelPath: String, threads: Int): Boolean

    @JvmStatic
    external fun unloadModel()

    @JvmStatic
    external fun isLoaded(): Boolean

    /**
     * Transcribe 16kHz mono PCM16 audio.
     *
     * @param pcm16 PCM16 samples at 16000 Hz
     * @param sampleRate expected 16000
     * @param languageTag BCP-47 tag (e.g. "es-ES" or "en-US")
     * @param translateToEnglish if true, translate speech to English
     */
    @JvmStatic
    external fun transcribePcm16(
        pcm16: ShortArray,
        sampleRate: Int,
        languageTag: String,
        translateToEnglish: Boolean,
    ): String?

    /**
     * Transcribe and emit partial segments via callback.
     *
     * The callback object must have a method: `fun onPartial(text: String)`.
     */
    @JvmStatic
    external fun transcribePcm16Streaming(
        pcm16: ShortArray,
        sampleRate: Int,
        languageTag: String,
        translateToEnglish: Boolean,
        callback: Any?,
    ): String?
}

