import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:udp/udp.dart';
import '../models/rider_peer.dart';

/// Coordina la malla offline sin internet ni Hotspot manual:
/// - Android: BLE Discovery + Wi-Fi Direct automático + transporte de voz UDP.
/// - iOS: Apple MultipeerConnectivity (AWDL + Bluetooth) iPhone <-> iPhone,
///   más soporte para unirse a grupos Wi-Fi Direct si hay un líder Android.
class MeshBridge {
  static const MethodChannel _meshChannel =
      MethodChannel('com.motointercom.app/mesh');
  static const EventChannel _meshEventsChannel =
      EventChannel('com.motointercom.app/mesh_events');

  static const int audioUdpPort = 45454;
  static const String bleServiceUuid = '0000m0t0-0000-1000-8000-00805f9b34fb';

  UDP? _udpSocket;
  StreamSubscription<List<ScanResult>>? _bleScanSub;
  StreamSubscription<dynamic>? _nativeMeshSub;
  Timer? _heartbeatTimer;

  final Map<String, RiderPeer> _peers = {};
  final StreamController<List<RiderPeer>> _peersController =
      StreamController<List<RiderPeer>>.broadcast();

  Stream<List<RiderPeer>> get peersStream => _peersController.stream;
  void Function(String senderId, Uint8List audioPayload)? onAudioPacketReceived;

  final String _myId = 'rider_${DateTime.now().millisecondsSinceEpoch % 10000}';
  String _myAlias = 'Piloto';
  String _groupCode = 'RODA-01';
  int _seqNumber = 0;

  Future<void> startOfflineMesh({
    required String groupCode,
    required String myAlias,
  }) async {
    _groupCode = groupCode.trim().toUpperCase();
    _myAlias = myAlias;

    await _startUdpTransport();

    if (Platform.isIOS) {
      await _startIosMultipeerMesh();
    } else {
      await _startBleDiscovery();
      if (Platform.isAndroid) {
        try {
          await _meshChannel.invokeMethod('ensureWifiDirectGroup', {
            'groupCode': _groupCode,
            'alias': _myAlias,
          });
        } catch (_) {}
      }
    }

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _broadcastHeartbeat(),
    );
  }

  Future<void> _startIosMultipeerMesh() async {
    await _nativeMeshSub?.cancel();
    _nativeMeshSub =
        _meshEventsChannel.receiveBroadcastStream().listen((event) {
      if (event is! Map) return;
      final type = event['event'] as String?;
      final peerId = event['peerId'] as String? ?? '';
      if (peerId.isEmpty) return;

      if (type == 'peerState') {
        final state = event['state'] as String? ?? 'disconnected';
        final alias = event['alias'] as String? ?? peerId;
        if (state == 'connected') {
          _upsertPeer(
            RiderPeer(
              id: peerId,
              alias: alias,
              rssi: -55,
              lastSeen: DateTime.now(),
            ),
          );
        } else if (state == 'disconnected') {
          _peers.remove(peerId);
          _peersController.add(_peers.values.toList());
        }
      } else if (type == 'audio') {
        final audio = event['data'];
        if (audio is Uint8List) {
          onAudioPacketReceived?.call(peerId, audio);
          final existing = _peers[peerId];
          if (existing != null) {
            _upsertPeer(existing.copyWith(
              isSpeaking: true,
              lastSeen: DateTime.now(),
            ));
          }
        }
      }
    });

    try {
      await _meshChannel.invokeMethod('startMultipeerMesh', {
        'groupCode': _groupCode,
        'alias': _myAlias,
      });
    } catch (_) {}
  }

  Future<void> stopOfflineMesh() async {
    _heartbeatTimer?.cancel();
    await _bleScanSub?.cancel();
    await _nativeMeshSub?.cancel();
    _nativeMeshSub = null;
    if (!Platform.isIOS) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
    _udpSocket?.close();
    _udpSocket = null;
    _peers.clear();
    _peersController.add([]);

    try {
      await _meshChannel.invokeMethod('leaveWifiDirectGroup');
    } catch (_) {}
  }

  Future<void> _startUdpTransport() async {
    _udpSocket?.close();
    _udpSocket = await UDP.bind(Endpoint.any(port: const Port(audioUdpPort)));
    _udpSocket!.asStream().listen((datagram) {
      if (datagram == null || datagram.data.length < 4) return;
      _handleIncomingDatagram(datagram);
    });
  }

  Future<void> _startBleDiscovery() async {
    await _bleScanSub?.cancel();
    _bleScanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName;
        if (name.startsWith('MM:$_groupCode:')) {
          final parts = name.split(':');
          final peerId = r.device.remoteId.str;
          final alias = parts.length >= 3 ? parts[2] : 'Moto';
          _upsertPeer(
            RiderPeer(
              id: peerId,
              alias: alias,
              rssi: r.rssi,
              lastSeen: DateTime.now(),
            ),
          );
        }
      }
    });

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      androidScanMode: AndroidScanMode.lowLatency,
    );
  }

  Future<void> connectIosToLeaderWifi({
    required String ssid,
    required String passphrase,
  }) async {
    if (!Platform.isIOS) return;
    await _meshChannel.invokeMethod('joinWifiDirectSsid', {
      'ssid': ssid,
      'passphrase': passphrase,
    });
  }

  void sendVoiceFrame(Uint8List frame) {
    if (Platform.isIOS) {
      _meshChannel.invokeMethod('sendMultipeerAudio', frame).catchError((_) {});
    }

    final socket = _udpSocket;
    if (socket == null) return;

    // Paquete: [0x01 = AUDIO] + [seq 2 bytes] + [idLen 1 byte] + [id] + [payload]
    final idBytes = utf8.encode(_myId);
    final header = BytesBuilder()
      ..addByte(0x01)
      ..addByte((_seqNumber >> 8) & 0xFF)
      ..addByte(_seqNumber & 0xFF)
      ..addByte(idBytes.length)
      ..add(idBytes)
      ..add(frame);

    _seqNumber = (_seqNumber + 1) & 0xFFFF;
    final bytes = header.toBytes();

    socket.send(
      bytes,
      Endpoint.broadcast(port: const Port(audioUdpPort)),
    );
  }

  void _broadcastHeartbeat() {
    final socket = _udpSocket;
    if (socket != null) {
      final payload = utf8.encode(jsonEncode({
        'id': _myId,
        'alias': _myAlias,
        'group': _groupCode,
      }));

      final packet = BytesBuilder()
        ..addByte(0x02) // HEARTBEAT
        ..add(payload);

      socket.send(
        packet.toBytes(),
        Endpoint.broadcast(port: const Port(audioUdpPort)),
      );
    }

    if (!Platform.isIOS) {
      final cutoff = DateTime.now().subtract(const Duration(seconds: 10));
      _peers.removeWhere((_, peer) => peer.lastSeen.isBefore(cutoff));
      _peersController.add(_peers.values.toList());
    }
  }

  void _handleIncomingDatagram(Datagram datagram) {
    final data = datagram.data;
    final type = data[0];

    if (type == 0x01 && data.length > 5) {
      final idLen = data[3];
      if (data.length <= 4 + idLen) return;
      final senderId = utf8.decode(data.sublist(4, 4 + idLen));
      if (senderId == _myId) return;

      final audioPayload = Uint8List.sublistView(data, 4 + idLen);
      onAudioPacketReceived?.call(senderId, audioPayload);

      final existing = _peers[senderId];
      if (existing != null) {
        _upsertPeer(existing.copyWith(
          isSpeaking: true,
          ipAddress: datagram.address,
          lastSeen: DateTime.now(),
        ));
      }
    } else if (type == 0x02 && data.length > 2) {
      try {
        final jsonMap =
            jsonDecode(utf8.decode(data.sublist(1))) as Map<String, dynamic>;
        final senderId = jsonMap['id'] as String? ?? '';
        if (senderId.isEmpty || senderId == _myId) return;
        if (jsonMap['group'] != _groupCode) return;

        _upsertPeer(
          RiderPeer(
            id: senderId,
            alias: jsonMap['alias'] as String? ?? 'Piloto',
            ipAddress: datagram.address,
            lastSeen: DateTime.now(),
          ),
        );
      } catch (_) {}
    }
  }

  void _upsertPeer(RiderPeer peer) {
    _peers[peer.id] = peer;
    _peersController.add(_peers.values.toList());
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _bleScanSub?.cancel();
    _nativeMeshSub?.cancel();
    _udpSocket?.close();
    _peersController.close();
  }
}
