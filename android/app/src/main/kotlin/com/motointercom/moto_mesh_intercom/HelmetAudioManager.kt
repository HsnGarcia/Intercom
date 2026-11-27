package com.motointercom.moto_mesh_intercom

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

/**
 * Enruta el micrófono y altavoz de la app hacia cualquier intercomunicador de casco
 * conectado por Bluetooth estándar (HFP/SCO), sin importar la marca (Cardo, Sena, FreedConn, etc.).
 * También gestiona captura AudioRecord (16kHz mono PCM16) y reproducción AudioTrack de baja latencia.
 */
class HelmetAudioManager(private val context: Context) {
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private val sampleRate = 16000
    private val frameSizeBytes = 640 // 20ms @ 16kHz PCM16 mono (320 samples * 2 bytes)

    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private val isCapturing = AtomicBoolean(false)
    private var eventSink: EventChannel.EventSink? = null

    fun setMicEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
        if (sink == null) {
            stopCapture()
        }
    }

    fun startHelmetSco(): Map<String, Any?> {
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        var connected = false
        var deviceName: String? = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val btDevice = audioManager.availableCommunicationDevices.firstOrNull { device ->
                device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                    device.type == AudioDeviceInfo.TYPE_BLE_HEADSET
            }
            if (btDevice != null) {
                connected = audioManager.setCommunicationDevice(btDevice)
                deviceName = btDevice.productName?.toString() ?: "Casco Bluetooth"
            }
        } else {
            @Suppress("DEPRECATION")
            if (audioManager.isBluetoothScoAvailableOffCall) {
                @Suppress("DEPRECATION")
                audioManager.startBluetoothSco()
                @Suppress("DEPRECATION")
                audioManager.isBluetoothScoOn = true
                connected = true
                deviceName = "Casco Bluetooth (SCO)"
            }
        }

        ensureAudioTrack()
        startCapture()

        return mapOf(
            "connected" to connected,
            "deviceName" to deviceName
        )
    }

    fun stopHelmetSco() {
        stopCapture()
        audioTrack?.let {
            try {
                it.stop()
                it.release()
            } catch (_: Exception) {}
        }
        audioTrack = null

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.clearCommunicationDevice()
        } else {
            @Suppress("DEPRECATION")
            audioManager.isBluetoothScoOn = false
            @Suppress("DEPRECATION")
            audioManager.stopBluetoothSco()
        }
        audioManager.mode = AudioManager.MODE_NORMAL
    }

    fun playPcmFrame(pcmBytes: ByteArray) {
        ensureAudioTrack()
        audioTrack?.write(pcmBytes, 0, pcmBytes.size)
    }

    private fun ensureAudioTrack() {
        if (audioTrack != null) return
        val minBuf = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        ).coerceAtLeast(frameSizeBytes * 4)

        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(minBuf)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        track.play()
        audioTrack = track
    }

    @SuppressLint("MissingPermission")
    private fun startCapture() {
        if (isCapturing.get()) return
        val minBuf = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        ).coerceAtLeast(frameSizeBytes * 4)

        val recorder = try {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                sampleRate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                minBuf
            )
        } catch (_: Exception) {
            return
        }

        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            return
        }

        audioRecord = recorder
        isCapturing.set(true)
        recorder.startRecording()

        thread(start = true, name = "MotoMeshMicCapture") {
            val buffer = ByteArray(frameSizeBytes)
            while (isCapturing.get()) {
                val read = recorder.read(buffer, 0, buffer.size)
                if (read > 0) {
                    val copy = buffer.copyOf(read)
                    mainHandler.post {
                        eventSink?.success(copy)
                    }
                }
            }
        }
    }

    private fun stopCapture() {
        isCapturing.set(false)
        audioRecord?.let {
            try {
                it.stop()
                it.release()
            } catch (_: Exception) {}
        }
        audioRecord = null
    }
}
