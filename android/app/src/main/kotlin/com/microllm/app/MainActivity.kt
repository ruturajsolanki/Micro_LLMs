package com.microllm.app

import android.os.Bundle
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

/**
 * Main activity for the MicroLLM application.
 * 
 * Sets up platform channels for:
 * - LLM inference (via JNI)
 * - Speech-to-text (STT)
 * - Text-to-speech (TTS)
 * - Memory monitoring
 * - Device scanning
 */
class MainActivity : FlutterActivity() {
    private lateinit var llamaHandler: LlamaHandler
    private lateinit var sttHandler: SpeechToTextHandler
    private lateinit var whisperHandler: WhisperHandler
    private lateinit var ttsHandler: TextToSpeechHandler
    private lateinit var memoryHandler: MemoryHandler
    private lateinit var deviceScannerHandler: DeviceScannerHandler

    private val micPermissionRequestCode = 1001

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureMicPermission()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize handlers
        llamaHandler = LlamaHandler(this)
        sttHandler = SpeechToTextHandler(this)
        // Whisper needs a Context for permission checks and main-thread marshaling.
        whisperHandler = WhisperHandler(this)
        ttsHandler = TextToSpeechHandler(this)
        memoryHandler = MemoryHandler(this)
        deviceScannerHandler = DeviceScannerHandler(this)

        // Set up LLM method channel (via JNI, bypasses FFI struct issues)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.microllm.app/llama"
        ).setMethodCallHandler { call, result ->
            llamaHandler.handleMethodCall(call, result)
        }

        // Set up STT method channel
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.microllm.app/stt"
        ).setMethodCallHandler { call, result ->
            sttHandler.handleMethodCall(call, result)
        }

        // Set up STT event channel for streaming results
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.microllm.app/stt_events"
        ).setStreamHandler(sttHandler)

        // Whisper STT method channel (offline)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.microllm.app/whisper"
        ).setMethodCallHandler { call, result ->
            whisperHandler.handleMethodCall(call, result)
        }

        // Whisper STT event channel
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.microllm.app/whisper_events"
        ).setStreamHandler(whisperHandler)

        // Set up TTS method channel
        val ttsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.microllm.app/tts"
        )
        ttsHandler.setMethodChannel(ttsChannel)
        ttsChannel.setMethodCallHandler { call, result ->
            ttsHandler.handleMethodCall(call, result)
        }

        // Set up memory monitoring channel
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.microllm.app/memory"
        ).setMethodCallHandler { call, result ->
            memoryHandler.handleMethodCall(call, result)
        }

        // Set up device scanner channel
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.microllm.app/device_scanner"
        ).setMethodCallHandler { call, result ->
            deviceScannerHandler.handleMethodCall(call, result)
        }
    }

    private fun ensureMicPermission() {
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED

        if (!granted) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.RECORD_AUDIO),
                micPermissionRequestCode
            )
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        llamaHandler.destroy()
        sttHandler.destroy()
        whisperHandler.destroy()
        ttsHandler.destroy()
    }
}
