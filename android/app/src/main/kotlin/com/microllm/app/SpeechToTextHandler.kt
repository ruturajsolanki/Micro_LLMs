package com.microllm.app

import android.content.Context
import android.content.Intent
import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Handler for speech-to-text operations using Android's SpeechRecognizer.
 * 
 * Supports offline recognition on Android 10+ with downloaded language packs.
 */
class SpeechToTextHandler(
    private val context: Context
) : EventChannel.StreamHandler, RecognitionListener {

    private var speechRecognizer: SpeechRecognizer? = null
    private var eventSink: EventChannel.EventSink? = null
    private var isListening = false
    private var lastRmsSentAtMs: Long = 0

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> {
                val available = SpeechRecognizer.isRecognitionAvailable(context)
                result.success(available)
            }
            
            "getLanguages" -> {
                // Get available recognition languages
                val languages = getAvailableLanguages()
                result.success(languages)
            }
            
            "start" -> {
                val language = call.argument<String>("language") ?: "en-US"
                val continuous = call.argument<Boolean>("continuous") ?: false
                val preferOffline = call.argument<Boolean>("preferOffline") ?: true
                startRecognition(language, continuous, preferOffline)
                result.success(null)
            }
            
            "stop" -> {
                stopRecognition()
                result.success(null)
            }
            
            "cancel" -> {
                cancelRecognition()
                result.success(null)
            }
            
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun getAvailableLanguages(): List<Map<String, Any>> {
        val defaultLocale = Locale.getDefault()
        // Include common languages. The device-default locale variant is listed
        // first so that _pickBestLanguageTag on the Dart side picks it up
        // before other variants of the same base language.
        val languages = mutableListOf<Map<String, Any>>()

        // Add the device's own locale first (e.g. en-IN, hi-IN) so it gets
        // priority when resolving a base code like "en" or "hi".
        val deviceTag = "${defaultLocale.language}-${defaultLocale.country}"
        if (defaultLocale.country.isNotEmpty()) {
            languages.add(mapOf(
                "code" to deviceTag,
                "displayName" to defaultLocale.displayName,
                "isDefault" to true
            ))
        }

        // Standard set of well-known locales.
        val knownLocales = listOf(
            "en-US" to "English (United States)",
            "en-IN" to "English (India)",
            "en-GB" to "English (United Kingdom)",
            "hi-IN" to "Hindi (India)",
            "es-ES" to "Spanish (Spain)",
            "fr-FR" to "French (France)",
            "de-DE" to "German (Germany)",
            "zh-CN" to "Chinese (Simplified)",
            "ja-JP" to "Japanese (Japan)",
            "ko-KR" to "Korean (South Korea)",
            "pt-BR" to "Portuguese (Brazil)",
            "ru-RU" to "Russian (Russia)",
            "ar-SA" to "Arabic (Saudi Arabia)",
            "it-IT" to "Italian (Italy)"
        )

        for ((code, displayName) in knownLocales) {
            // Skip if we already added the device locale with the same code.
            if (code == deviceTag) continue
            languages.add(mapOf(
                "code" to code,
                "displayName" to displayName,
                "isDefault" to (code.startsWith(defaultLocale.language))
            ))
        }

        return languages
    }

    private fun startRecognition(language: String, continuous: Boolean, preferOffline: Boolean) {
        // Always destroy the previous recognizer to free native resources.
        // This prevents resource leaks during continuous-mode restart cycles.
        speechRecognizer?.destroy()
        speechRecognizer = null
        isListening = false

        // Permission check (defensive) - main activity should have requested it.
        val granted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            eventSink?.success(mapOf(
                "type" to "error",
                "message" to "Insufficient permissions",
                "code" to SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS,
                "isRecoverable" to false
            ))
            isListening = false
            return
        }

        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(context).apply {
            setRecognitionListener(this@SpeechToTextHandler)
        }

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            
            // Request offline recognition (Android 10+)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, preferOffline)
        }

        isListening = true
        speechRecognizer?.startListening(intent)
    }

    private fun stopRecognition() {
        speechRecognizer?.stopListening()
        isListening = false
    }

    private fun cancelRecognition() {
        speechRecognizer?.cancel()
        isListening = false
    }

    fun destroy() {
        speechRecognizer?.destroy()
        speechRecognizer = null
    }

    // EventChannel.StreamHandler implementation
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // RecognitionListener implementation
    override fun onReadyForSpeech(params: Bundle?) {
        eventSink?.success(mapOf("type" to "ready"))
    }

    override fun onBeginningOfSpeech() {
        // User started speaking
    }

    override fun onRmsChanged(rmsdB: Float) {
        // Volume level changed - used for visual feedback (throttled)
        val now = System.currentTimeMillis()
        if (now - lastRmsSentAtMs > 60) {
            lastRmsSentAtMs = now
            eventSink?.success(mapOf(
                "type" to "rms",
                "rmsDb" to rmsdB.toDouble()
            ))
        }
    }

    override fun onBufferReceived(buffer: ByteArray?) {
        // Audio buffer received
    }

    override fun onEndOfSpeech() {
        eventSink?.success(mapOf("type" to "end"))
    }

    override fun onError(error: Int) {
        val errorMessage = when (error) {
            SpeechRecognizer.ERROR_AUDIO -> "Audio recording error"
            SpeechRecognizer.ERROR_CLIENT -> "Client error"
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Insufficient permissions"
            SpeechRecognizer.ERROR_NETWORK -> "Network error"
            SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Network timeout"
            SpeechRecognizer.ERROR_NO_MATCH -> "No speech match"
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Recognizer busy"
            SpeechRecognizer.ERROR_SERVER -> "Server error"
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech input"
            else -> "Unknown error"
        }

        isListening = false
        // Always include numeric code so Flutter can make decisions / show useful UI.
        eventSink?.success(mapOf(
            "type" to "error",
            "message" to "$errorMessage (code=$error)",
            "code" to error,
            "isRecoverable" to (error == SpeechRecognizer.ERROR_NO_MATCH ||
                               error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT)
        ))
    }

    override fun onResults(results: Bundle?) {
        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        val confidences = results?.getFloatArray(SpeechRecognizer.CONFIDENCE_SCORES)

        if (!matches.isNullOrEmpty()) {
            eventSink?.success(mapOf(
                "type" to "result",
                "text" to matches[0],
                "confidence" to (confidences?.getOrNull(0) ?: 0.0f).toDouble(),
                "isFinal" to true,
                "alternatives" to matches.drop(1)
            ))
        }

        isListening = false
    }

    override fun onPartialResults(partialResults: Bundle?) {
        val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)

        if (!matches.isNullOrEmpty()) {
            eventSink?.success(mapOf(
                "type" to "result",
                "text" to matches[0],
                "confidence" to 0.5, // Partial results don't have confidence
                "isFinal" to false,
                "alternatives" to emptyList<String>()
            ))
        }
    }

    override fun onEvent(eventType: Int, params: Bundle?) {
        // Additional events
    }
}
