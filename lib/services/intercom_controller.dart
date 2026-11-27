import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/mesh_state.dart';
import '../models/rider_peer.dart';
import 'audio_pipeline.dart';
import 'mesh_bridge.dart';

class IntercomController extends ChangeNotifier {
  final AudioPipeline _audio = AudioPipeline();
  final MeshBridge _mesh = MeshBridge();

  MeshState _state = const MeshState();
  List<RiderPeer> _peers = [];
  StreamSubscription<List<RiderPeer>>? _peersSub;

  MeshState get state => _state;
  List<RiderPeer> get peers => _peers;

  Future<void> initialize() async {
    _peersSub = _mesh.peersStream.listen((updatedPeers) {
      _peers = updatedPeers;
      notifyListeners();
    });

    _audio.onVoiceFrameReady = (frame) {
      _mesh.sendVoiceFrame(frame);
    };

    _audio.onSpeakingStateChanged = (speaking) {
      _state = _state.copyWith(isSpeakingNow: speaking);
      notifyListeners();
    };

    _mesh.onAudioPacketReceived = (_, payload) {
      _audio.playRemotePcmFrame(payload);
    };
  }

  Future<void> connectToRodada({
    required String groupCode,
    required String alias,
  }) async {
    _state = _state.copyWith(
      groupCode: groupCode,
      myAlias: alias,
      connectionStatus: MeshConnectionStatus.scanningBle,
      statusMessage: 'Solicitando permisos de Bluetooth, Wi-Fi y Micrófono...',
    );
    notifyListeners();

    final permissionsGranted = await _requestRequiredPermissions();
    if (!permissionsGranted) {
      _state = _state.copyWith(
        connectionStatus: MeshConnectionStatus.disconnected,
        statusMessage: 'Faltan permisos de Bluetooth, Ubicación o Micrófono.',
      );
      notifyListeners();
      return;
    }

    await WakelockPlus.enable();

    _state = _state.copyWith(
      helmetStatus: HelmetAudioStatus.connectingSco,
      statusMessage: 'Conectando audio al casco Bluetooth...',
    );
    notifyListeners();

    final helmetInfo = await _audio.startHelmetBluetoothAudio();
    final bool helmetOk = helmetInfo['connected'] == true;

    _state = _state.copyWith(
      helmetStatus: helmetOk
          ? HelmetAudioStatus.helmetConnected
          : HelmetAudioStatus.phoneSpeakerOnly,
      connectedHelmetName: helmetInfo['deviceName'] as String?,
      connectionStatus: MeshConnectionStatus.formingGroup,
      statusMessage: 'Creando malla offline sin internet...',
    );
    notifyListeners();

    await _mesh.startOfflineMesh(groupCode: groupCode, myAlias: alias);
    _audio.startCaptureLoop();

    _state = _state.copyWith(
      connectionStatus: MeshConnectionStatus.connectedOffline,
      statusMessage: 'Malla Offline Activa · Manos Libres (VOX)',
    );
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _mesh.stopOfflineMesh();
    await _audio.stopHelmetBluetoothAudio();
    await WakelockPlus.disable();
    _peers = [];
    _state = _state.copyWith(
      connectionStatus: MeshConnectionStatus.disconnected,
      helmetStatus: HelmetAudioStatus.phoneSpeakerOnly,
      isSpeakingNow: false,
      statusMessage: 'Desconectado',
    );
    notifyListeners();
  }

  void toggleMute() {
    final next = !_state.isLocalMuted;
    _audio.isMuted = next;
    _state = _state.copyWith(
      isLocalMuted: next,
      isSpeakingNow: next ? false : _state.isSpeakingNow,
    );
    notifyListeners();
  }

  void toggleDeafen() {
    final next = !_state.isDeafened;
    _audio.isDeafened = next;
    _state = _state.copyWith(isDeafened: next);
    notifyListeners();
  }

  void updateVoxThreshold(double value) {
    _audio.voxThreshold = value;
    _state = _state.copyWith(voxThreshold: value);
    notifyListeners();
  }

  Future<bool> _requestRequiredPermissions() async {
    if (Platform.isIOS) {
      // En iOS, AVAudioSession y MultipeerConnectivity solicitan nativamente
      // Micrófono, Bluetooth y Red Local sin depender de macros de Podfile.
      return true;
    }

    final statuses = await [
      Permission.microphone,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.nearbyWifiDevices,
      Permission.locationWhenInUse,
    ].request();

    return statuses[Permission.microphone]?.isGranted == true &&
        statuses[Permission.bluetoothConnect]?.isGranted != false;
  }

  @override
  void dispose() {
    _peersSub?.cancel();
    _mesh.dispose();
    super.dispose();
  }
}
