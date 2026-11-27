import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Pipeline de audio manos libres para intercomunicador en moto:
/// - Enruta micrófono y altavoz al casco Bluetooth vía canal nativo (SCO/HFP).
/// - Aplica filtro básico de energía (VOX) con hangover para evitar cortes de palabras
///   y no transmitir ruido constante de viento en carretera.
class AudioPipeline {
  static const MethodChannel _audioChannel =
      MethodChannel('com.motointercom.app/audio');
  static const EventChannel _micStreamChannel =
      EventChannel('com.motointercom.app/mic_stream');

  StreamSubscription<dynamic>? _micSub;
  DateTime _lastVoiceDetectedAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration voxHangover = const Duration(milliseconds: 450);

  double voxThreshold = 0.18;
  bool isMuted = false;
  bool isDeafened = false;

  void Function(Uint8List pcmFrame)? onVoiceFrameReady;
  void Function(bool speaking)? onSpeakingStateChanged;
  bool _currentlySpeaking = false;

  Future<Map<String, dynamic>> startHelmetBluetoothAudio() async {
    try {
      final result =
          await _audioChannel.invokeMapMethod<String, dynamic>('startHelmetSco');
      return result ?? {'connected': false, 'deviceName': null};
    } on PlatformException catch (e) {
      return {'connected': false, 'error': e.message};
    }
  }

  Future<void> stopHelmetBluetoothAudio() async {
    await _micSub?.cancel();
    _micSub = null;
    try {
      await _audioChannel.invokeMethod('stopHelmetSco');
    } catch (_) {}
  }

  void startCaptureLoop() {
    _micSub?.cancel();
    _micSub = _micStreamChannel.receiveBroadcastStream().listen((event) {
      if (isMuted || event is! Uint8List) return;
      _processPcm16Frame(event);
    });
  }

  Future<void> playRemotePcmFrame(Uint8List pcm16Frame) async {
    if (isDeafened) return;
    try {
      await _audioChannel.invokeMethod('playPcmFrame', pcm16Frame);
    } catch (_) {}
  }

  void _processPcm16Frame(Uint8List pcmBytes) {
    final double rms = _computeNormalizedRms(pcmBytes);
    final now = DateTime.now();

    if (rms >= voxThreshold) {
      _lastVoiceDetectedAt = now;
    }

    final bool shouldTransmit =
        now.difference(_lastVoiceDetectedAt) <= voxHangover;

    if (shouldTransmit != _currentlySpeaking) {
      _currentlySpeaking = shouldTransmit;
      onSpeakingStateChanged?.call(shouldTransmit);
    }

    if (shouldTransmit) {
      onVoiceFrameReady?.call(pcmBytes);
    }
  }

  double _computeNormalizedRms(Uint8List pcmBytes) {
    if (pcmBytes.length < 2) return 0.0;
    final byteData = ByteData.sublistView(pcmBytes);
    final int sampleCount = pcmBytes.length ~/ 2;
    double sumSquares = 0.0;

    for (int i = 0; i < sampleCount; i++) {
      final int sample = byteData.getInt16(i * 2, Endian.little);
      final double norm = sample / 32768.0;
      sumSquares += norm * norm;
    }
    return math.sqrt(sumSquares / sampleCount);
  }
}
