package com.microllm.app

import android.Manifest
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.util.concurrent.Executors
import kotlin.math.log10
import kotlin.math.max

/**
 * Records microphone audio to a WAV file for cloud STT upload.
 *
 * Format: 16kHz, mono, 16-bit PCM → standard WAV.
 */
class AudioRecorderHandler(context: Context) : EventChannel.StreamHandler {

    private val context: Context = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()

    private var eventSink: EventChannel.EventSink? = null
    private var audioRecord: AudioRecord? = null
    private var isRecording = false
    private var outputPath: String? = null

    fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startRecording" -> {
                val path = call.argument<String>("outputPath")
                if (path.isNullOrBlank()) {
                    postResult(result) { it.error("INVALID_ARGS", "outputPath required", null) }
                    return
                }
                startRecording(path)
                postResult(result) { it.success(null) }
            }
            "stopRecording" -> {
                stopRecording()
                postResult(result) { it.success(outputPath) }
            }
            "cancelRecording" -> {
                cancelRecording()
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

    private fun emit(event: Map<String, Any>) {
        mainHandler.post { eventSink?.success(event) }
    }

    private fun postResult(result: MethodChannel.Result, block: (MethodChannel.Result) -> Unit) {
        mainHandler.post { block(result) }
    }

    private fun startRecording(path: String) {
        if (isRecording) {
            stopRecording()
        }

        val granted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.RECORD_AUDIO
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED

        if (!granted) {
            emit(mapOf("type" to "error", "message" to "RECORD_AUDIO permission not granted"))
            return
        }

        outputPath = path
        val sampleRate = 16000
        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        val minBuffer = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        val bufferSize = max(minBuffer, sampleRate / 5 * 2)

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            sampleRate,
            channelConfig,
            audioFormat,
            bufferSize
        )

        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            emit(mapOf("type" to "error", "message" to "Failed to init AudioRecord"))
            audioRecord?.release()
            audioRecord = null
            return
        }

        isRecording = true

        executor.execute {
            val record = audioRecord ?: return@execute
            val chunk = ByteArray(bufferSize)
            val file = File(path)
            file.parentFile?.mkdirs()

            var fos: FileOutputStream? = null
            var totalBytes = 0L

            try {
                fos = FileOutputStream(file)
                // Write placeholder WAV header (44 bytes)
                fos.write(ByteArray(44))

                record.startRecording()

                while (isRecording) {
                    val read = record.read(chunk, 0, chunk.size)
                    if (read > 0) {
                        fos.write(chunk, 0, read)
                        totalBytes += read

                        // Compute RMS for UI
                        val rmsDb = computeRmsDb(chunk, read)
                        emit(mapOf("type" to "rms", "rmsDb" to rmsDb))
                    }
                }
            } catch (e: Exception) {
                emit(mapOf("type" to "error", "message" to "Recording error: ${e.message}"))
            } finally {
                try { record.stop() } catch (_: Exception) {}
                record.release()
                audioRecord = null
                fos?.close()
            }

            // Write proper WAV header
            writeWavHeader(file, totalBytes, sampleRate, 1, 16)
        }
    }

    private fun stopRecording() {
        isRecording = false
    }

    private fun cancelRecording() {
        isRecording = false
        outputPath?.let {
            try { File(it).delete() } catch (_: Exception) {}
        }
        outputPath = null
    }

    private fun computeRmsDb(buf: ByteArray, n: Int): Double {
        if (n < 2) return -120.0
        var sum = 0.0
        val samples = n / 2
        for (i in 0 until samples) {
            val low = buf[i * 2].toInt() and 0xFF
            val high = buf[i * 2 + 1].toInt()
            val sample = (high shl 8 or low).toShort().toDouble()
            sum += sample * sample
        }
        val rms = kotlin.math.sqrt(sum / samples)
        val norm = rms / 32768.0
        return (20.0 * log10(max(1e-9, norm))).coerceIn(-120.0, 0.0)
    }

    private fun writeWavHeader(
        file: File,
        dataSize: Long,
        sampleRate: Int,
        channels: Int,
        bitsPerSample: Int
    ) {
        val raf = RandomAccessFile(file, "rw")
        val byteRate = sampleRate * channels * bitsPerSample / 8
        val blockAlign = channels * bitsPerSample / 8
        val totalSize = 36 + dataSize

        raf.seek(0)
        raf.writeBytes("RIFF")
        raf.writeIntLE(totalSize.toInt())
        raf.writeBytes("WAVE")
        raf.writeBytes("fmt ")
        raf.writeIntLE(16) // Subchunk1Size (PCM)
        raf.writeShortLE(1) // AudioFormat (PCM)
        raf.writeShortLE(channels)
        raf.writeIntLE(sampleRate)
        raf.writeIntLE(byteRate)
        raf.writeShortLE(blockAlign)
        raf.writeShortLE(bitsPerSample)
        raf.writeBytes("data")
        raf.writeIntLE(dataSize.toInt())
        raf.close()
    }

    private fun RandomAccessFile.writeIntLE(value: Int) {
        write(value and 0xFF)
        write((value shr 8) and 0xFF)
        write((value shr 16) and 0xFF)
        write((value shr 24) and 0xFF)
    }

    private fun RandomAccessFile.writeShortLE(value: Int) {
        write(value and 0xFF)
        write((value shr 8) and 0xFF)
    }

    fun destroy() {
        isRecording = false
        try { audioRecord?.stop() } catch (_: Exception) {}
        try { audioRecord?.release() } catch (_: Exception) {}
        audioRecord = null
        try { executor.shutdownNow() } catch (_: Exception) {}
    }
}
