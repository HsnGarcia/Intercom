package com.motointercom.moto_mesh_intercom

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var helmetAudioManager: HelmetAudioManager
    private lateinit var wifiDirectMeshManager: WifiDirectMeshManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        helmetAudioManager = HelmetAudioManager(this)
        wifiDirectMeshManager = WifiDirectMeshManager(this)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.motointercom.app/audio"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startHelmetSco" -> {
                    val res = helmetAudioManager.startHelmetSco()
                    result.success(res)
                }
                "stopHelmetSco" -> {
                    helmetAudioManager.stopHelmetSco()
                    result.success(null)
                }
                "playPcmFrame" -> {
                    val bytes = call.arguments as? ByteArray
                    if (bytes != null) {
                        helmetAudioManager.playPcmFrame(bytes)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.motointercom.app/mic_stream"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                helmetAudioManager.setMicEventSink(events)
            }

            override fun onCancel(arguments: Any?) {
                helmetAudioManager.setMicEventSink(null)
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.motointercom.app/mesh"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureWifiDirectGroup" -> {
                    wifiDirectMeshManager.ensureGroup { ok, ssid, pass ->
                        result.success(
                            mapOf(
                                "created" to ok,
                                "ssid" to ssid,
                                "passphrase" to pass
                            )
                        )
                    }
                }
                "leaveWifiDirectGroup" -> {
                    wifiDirectMeshManager.leaveGroup()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        helmetAudioManager.stopHelmetSco()
        wifiDirectMeshManager.leaveGroup()
        super.onDestroy()
    }
}
