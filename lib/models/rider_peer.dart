import 'dart:io';

enum IntercomBrand {
  cardo,
  sena,
  freedconn,
  ejeas,
  generic,
}

class RiderPeer {
  final String id;
  final String alias;
  final IntercomBrand helmetBrand;
  final InternetAddress? ipAddress;
  final int udpPort;
  final int rssi;
  final bool isSpeaking;
  final bool isMuted;
  final bool isLeader;
  final DateTime lastSeen;

  const RiderPeer({
    required this.id,
    required this.alias,
    this.helmetBrand = IntercomBrand.generic,
    this.ipAddress,
    this.udpPort = 45454,
    this.rssi = -65,
    this.isSpeaking = false,
    this.isMuted = false,
    this.isLeader = false,
    required this.lastSeen,
  });

  RiderPeer copyWith({
    String? alias,
    IntercomBrand? helmetBrand,
    InternetAddress? ipAddress,
    int? udpPort,
    int? rssi,
    bool? isSpeaking,
    bool? isMuted,
    bool? isLeader,
    DateTime? lastSeen,
  }) {
    return RiderPeer(
      id: id,
      alias: alias ?? this.alias,
      helmetBrand: helmetBrand ?? this.helmetBrand,
      ipAddress: ipAddress ?? this.ipAddress,
      udpPort: udpPort ?? this.udpPort,
      rssi: rssi ?? this.rssi,
      isSpeaking: isSpeaking ?? this.isSpeaking,
      isMuted: isMuted ?? this.isMuted,
      isLeader: isLeader ?? this.isLeader,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  String get signalLabel {
    if (rssi >= -60) return 'Excelente';
    if (rssi >= -75) return 'Buena';
    if (rssi >= -88) return 'Media';
    return 'Lejana';
  }
}
