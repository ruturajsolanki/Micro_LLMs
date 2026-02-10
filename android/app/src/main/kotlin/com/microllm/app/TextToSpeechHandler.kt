package com.microllm.app

import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.UUID

/**
 * Handler for text-to-speech operations using Android's TextToSpeech API.
 * 
 * Supports offline synthesis with downloaded language packs.
 */
class TextToSpeechHandler(private val context: Context) : TextToSpeech.OnInitListener {

    private var tts: TextToSpeech? = null
    private var isInitialized = false
    private var methodChannel: MethodChannel? = null
    private val pendingOperations = mutableListOf<() -> Unit>()
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        tts = TextToSpeech(context, this)
    }

    override fun onInit(status: Int) {
        isInitialized = status == TextToSpeech.SUCCESS
        
        if (isInitialized) {
            // Set up utterance progress listener
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    // Speech started
                }

                override fun onDone(utteranceId: String?) {
                    // Speech completed - notify Flutter
                    mainHandler.post {
                        methodChannel?.invokeMethod("onTtsComplete", null)
                    }
                }

                override fun onError(utteranceId: String?) {
                    mainHandler.post {
                        methodChannel?.invokeMethod("onTtsError", "Speech synthesis error")
                    }
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?, errorCode: Int) {
                    mainHandler.post {
                        methodChannel?.invokeMethod("onTtsError", "Error code: $errorCode")
                    }
                }
            })

            // Execute any pending operations
            pendingOperations.forEach { it() }
            pendingOperations.clear()
        }
    }

    fun setMethodChannel(channel: MethodChannel) {
        methodChannel = channel
    }

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> {
                result.success(isInitialized)
            }
            
            "getLanguages" -> {
                if (!isInitialized) {
                    result.success(emptyList<Map<String, Any>>())
                    return
                }
                
                val languages = getAvailableLanguages()
                result.success(languages)
            }
            
            "speak" -> {
                val text = call.argument<String>("text")
                val language = call.argument<String>("language") ?: "en-US"
                val pitch = call.argument<Double>("pitch") ?: 1.0
                val rate = call.argument<Double>("rate") ?: 1.0
                
                if (text.isNullOrEmpty()) {
                    result.error("INVALID_ARGUMENT", "Text cannot be empty", null)
                    return
                }
                
                speak(text, language, pitch.toFloat(), rate.toFloat())
                result.success(null)
            }
            
            "stop" -> {
                stop()
                result.success(null)
            }
            
            "isSpeaking" -> {
                result.success(tts?.isSpeaking ?: false)
            }
            
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun getAvailableLanguages(): List<Map<String, Any>> {
        val availableLocales = tts?.availableLanguages ?: emptySet()
        val defaultLocale = Locale.getDefault()
        
        return availableLocales.map { locale ->
            mapOf(
                "code" to locale.toLanguageTag(),
                "displayName" to locale.displayName,
                "isDefault" to (locale.language == defaultLocale.language)
            )
        }
    }

    private fun speak(text: String, language: String, pitch: Float, rate: Float) {
        val operation: () -> Unit = {
            try {
                // Set language
                val locale = Locale.forLanguageTag(language)
                val result = tts?.setLanguage(locale)
                
                if (result == TextToSpeech.LANG_MISSING_DATA || 
                    result == TextToSpeech.LANG_NOT_SUPPORTED) {
                    // Fall back to default locale
                    tts?.setLanguage(Locale.getDefault())
                }
                
                // Set pitch and speech rate
                tts?.setPitch(pitch.coerceIn(0.5f, 2.0f))
                tts?.setSpeechRate(rate.coerceIn(0.5f, 2.0f))
                
                // Generate unique utterance ID
                val utteranceId = UUID.randomUUID().toString()
                
                // Speak
                tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, utteranceId)
            } catch (e: Exception) {
                methodChannel?.invokeMethod("onTtsError", e.message)
            }
        }
        
        if (isInitialized) {
            operation()
        } else {
            pendingOperations.add(operation)
        }
    }

    private fun stop() {
        tts?.stop()
    }

    fun destroy() {
        tts?.stop()
        tts?.shutdown()
        tts = null
    }
}
