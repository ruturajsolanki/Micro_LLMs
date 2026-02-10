package com.microllm.app

import android.Manifest
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.SpeechRecognizer
import androidx.core.content.ContextCompat
import androidx.annotation.Keep
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max

/**
 * Offline STT handler backed by whisper.cpp (via JNI).
 *
 * Emits events compatible with the existing STT pipeline:
 * - {type:"ready"}
 * - {type:"rms", rmsDb: <double>}
 * - {type:"result", text: <string>, confidence: <double>, isFinal: <bool>, alternatives: []}
 * - {type:"error", message: <string>, code: <int>, isRecoverable: <bool>}
 * - {type:"end"}
 */
class WhisperHandler : EventChannel.StreamHandler {

    constructor(context: Context) {
        this.context = context.applicationContext
    }

    // Required for runtime permission checks. We keep the application context to avoid leaking Activity.
    private val context: Context

    // Flutter's platform messenger requires EventChannel emissions on the main thread.
    // The crash you saw comes from calling eventSink.success(...) off-main.
    private val mainHandler = Handler(Looper.getMainLooper())

    private val executor = Executors.newSingleThreadExecutor()

    private var eventSink: EventChannel.EventSink? = null
    private var audioRecord: AudioRecord? = null
    private var isListening = false

    // Model state
    private var modelLoaded = false

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> postResult(result) { it.success(WhisperNative.isAvailable()) }
            "isModelLoaded" -> postResult(result) { it.success(modelLoaded && WhisperNative.isLoaded()) }
            "loadModel" -> {
                val modelPath = call.argument<String>("modelPath")
                val threads = call.argument<Int>("threads") ?: 4
                if (modelPath.isNullOrBlank()) {
                    postResult(result) { it.error("INVALID_ARGS", "modelPath is required", null) }
                    return
                }
                try {
                    executor.execute {
                        try {
                            if (!WhisperNative.isAvailable()) {
                                postResult(result) { it.error("NOT_AVAILABLE", "Whisper is not available in this build", null) }
                                return@execute
                            }
                            val ok = WhisperNative.loadModel(modelPath, threads)
                            modelLoaded = ok
                            postResult(result) {
                                if (ok) it.success(true) else it.error("LOAD_FAILED", "Failed to load whisper model", null)
                            }
                        } catch (e: Exception) {
                            postResult(result) { it.error("LOAD_EXCEPTION", e.message, null) }
                        }
                    }
                } catch (e: RejectedExecutionException) {
                    postResult(result) { it.error("EXECUTOR_SHUTDOWN", "Whisper executor is not running", null) }
                }
            }
            "unloadModel" -> {
                try {
                    executor.execute {
                        try {
                            stopInternal()
                            WhisperNative.unloadModel()
                            modelLoaded = false
                            postResult(result) { it.success(true) }
                        } catch (e: Exception) {
                            postResult(result) { it.error("UNLOAD_EXCEPTION", e.message, null) }
                        }
                    }
                } catch (e: RejectedExecutionException) {
                    postResult(result) { it.error("EXECUTOR_SHUTDOWN", "Whisper executor is not running", null) }
                }
            }
            "start" -> {
                val language = call.argument<String>("language") ?: "en-US"
                val translateToEnglish = call.argument<Boolean>("translateToEnglish") ?: false
                startListening(language, translateToEnglish)
                postResult(result) { it.success(null) }
            }
            "stop" -> {
                stopInternal()
                postResult(result) { it.success(null) }
            }
            "cancel" -> {
                cancelInternal()
                postResult(result) { it.success(null) }
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    /**
     * Always emit EventChannel events on the main thread.
     * FlutterJNI enforces main-thread delivery for platform messages.
     */
    private fun emit(event: Map<String, Any>) {
        mainHandler.post {
            eventSink?.success(event)
        }
    }

    /**
     * Always complete MethodChannel results on the main thread.
     * This avoids rare thread-affinity issues and matches Flutter's expectations.
     */
    private fun postResult(result: MethodChannel.Result, block: (MethodChannel.Result) -> Unit) {
        mainHandler.post { block(result) }
    }

    private fun startListening(languageTag: String, translateToEnglish: Boolean) {
        val granted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.RECORD_AUDIO
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (!granted) {
            emit(
                mapOf(
                    "type" to "error",
                    "message" to "Insufficient permissions (RECORD_AUDIO not granted)",
                    "code" to SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS,
                    "isRecoverable" to false
                )
            )
            return
        }

        if (!WhisperNative.isAvailable()) {
            emit(
                mapOf(
                    "type" to "error",
                    "message" to "Whisper is not available in this build (missing whisper.cpp).",
                    "code" to -100,
                    "isRecoverable" to false
                )
            )
            return
        }
        if (!modelLoaded || !WhisperNative.isLoaded()) {
            emit(
                mapOf(
                    "type" to "error",
                    "message" to "Whisper model not loaded. Download and load an STT model first.",
                    "code" to -101,
                    "isRecoverable" to false
                )
            )
            return
        }
        if (isListening) {
            cancelInternal()
        }

        val sampleRate = 16000
        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        val minBuffer = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        val bufferSize = max(minBuffer, sampleRate / 10 * 2) // ~100ms

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            sampleRate,
            channelConfig,
            audioFormat,
            bufferSize
        )

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            emit(
                mapOf(
                    "type" to "error",
                    "message" to "Failed to initialize microphone AudioRecord",
                    "code" to SpeechRecognizer.ERROR_AUDIO,
                    "isRecoverable" to false
                )
            )
            audioRecord?.release()
            audioRecord = null
            return
        }

        isListening = true
        emit(mapOf("type" to "ready"))

        try {
            executor.execute {
            val record = audioRecord ?: return@execute
            val chunk = ShortArray(bufferSize / 2)
            val samples = ArrayList<Short>(sampleRate * 20) // cap ~20s typical utterance

            // Simple endpointer
            var started = false
            var silenceMs = 0
            val frameMs = 100
            val startThresholdDb = -35.0
            val silenceThresholdDb = -45.0
            val endSilenceMs = 1200

            try {
                record.startRecording()

                while (isListening) {
                    val read = record.read(chunk, 0, chunk.size)
                    if (read <= 0) continue

                    val rmsDb = computeRmsDb(chunk, read)
                    emit(mapOf("type" to "rms", "rmsDb" to rmsDb))

                    if (!started) {
                        if (rmsDb > startThresholdDb) {
                            started = true
                        } else {
                            continue
                        }
                    }

                    // store samples
                    for (i in 0 until read) samples.add(chunk[i])

                    if (rmsDb < silenceThresholdDb) {
                        silenceMs += frameMs
                    } else {
                        silenceMs = 0
                    }

                    if (silenceMs >= endSilenceMs && samples.size > sampleRate / 2) {
                        // end-of-utterance detected
                        break
                    }
                }
            } catch (e: Exception) {
                emit(
                    mapOf(
                        "type" to "error",
                        "message" to "Audio capture error: ${e.message}",
                        "code" to SpeechRecognizer.ERROR_AUDIO,
                        "isRecoverable" to true
                    )
                )
            } finally {
                try {
                    record.stop()
                } catch (_: Exception) {}
                record.release()
                audioRecord = null
            }

            val pcm = samples.toShortArray()
            isListening = false
            emit(mapOf("type" to "end"))

            if (pcm.isEmpty()) return@execute

            // Transcribe (stream partial segments while decoding)
            try {
                val cb = NativeCallback { partial ->
                    emit(
                        mapOf(
                            "type" to "result",
                            "text" to partial,
                            "confidence" to 0.0,
                            "isFinal" to false,
                            "alternatives" to emptyList<String>()
                        )
                    )
                }

                val text = WhisperNative.transcribePcm16Streaming(
                    pcm,
                    sampleRate,
                    languageTag,
                    translateToEnglish,
                    cb
                ) ?: ""

                emit(
                    mapOf(
                        "type" to "result",
                        "text" to text,
                        "confidence" to 0.0,
                        "isFinal" to true,
                        "alternatives" to emptyList<String>()
                    )
                )
            } catch (e: Exception) {
                emit(
                    mapOf(
                        "type" to "error",
                        "message" to "Whisper transcription failed: ${e.message}",
                        "code" to SpeechRecognizer.ERROR_CLIENT,
                        "isRecoverable" to true
                    )
                )
            }
            }
        } catch (e: RejectedExecutionException) {
            emit(
                mapOf(
                    "type" to "error",
                    "message" to "Whisper engine is not running",
                    "code" to SpeechRecognizer.ERROR_CLIENT,
                    "isRecoverable" to true
                )
            )
        }
    }

    private fun stopInternal() {
        isListening = false
        audioRecord?.let {
            try { it.stop() } catch (_: Exception) {}
            try { it.release() } catch (_: Exception) {}
        }
        audioRecord = null
    }

    private fun cancelInternal() {
        stopInternal()
    }

    private fun computeRmsDb(buf: ShortArray, n: Int): Double {
        if (n <= 0) return -120.0
        var sum = 0.0
        for (i in 0 until n) {
            val s = buf[i].toDouble()
            sum += s * s
        }
        val mean = sum / n
        val rms = kotlin.math.sqrt(mean)
        val norm = rms / 32768.0
        val db = 20.0 * log10(max(1e-9, norm))
        return db.coerceIn(-120.0, 0.0)
    }

    @Keep
    private class NativeCallback(
        private val onPartialCb: (String) -> Unit
    ) {
        @Suppress("unused")
        fun onPartial(text: String) {
            onPartialCb(text)
        }
    }

    fun destroy() {
        // Defensive cleanup to avoid leaking AudioRecord threads on activity teardown.
        try {
            stopInternal()
        } catch (_: Exception) {}
        try {
            executor.shutdownNow()
        } catch (_: Exception) {}
    }
}

