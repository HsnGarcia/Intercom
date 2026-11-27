enum MeshConnectionStatus {
  disconnected,
  scanningBle,
  formingGroup,
  connectedOffline,
  reconnecting,
}

enum HelmetAudioStatus {
  phoneSpeakerOnly,
  connectingSco,
  helmetConnected,
  error,
}

class MeshState {
  final MeshConnectionStatus connectionStatus;
  final HelmetAudioStatus helmetStatus;
  final String? connectedHelmetName;
  final String groupCode;
  final String myAlias;
  final bool isLocalMuted;
  final bool isDeafened;
  final bool isSpeakingNow;
  final double voxThreshold; // 0.05 (muy sensible) a 0.60 (alto ruido)
  final String? statusMessage;

  const MeshState({
    this.connectionStatus = MeshConnectionStatus.disconnected,
    this.helmetStatus = HelmetAudioStatus.phoneSpeakerOnly,
    this.connectedHelmetName,
    this.groupCode = 'RODA-01',
    this.myAlias = 'Piloto',
    this.isLocalMuted = false,
    this.isDeafened = false,
    this.isSpeakingNow = false,
    this.voxThreshold = 0.04,
    this.statusMessage,
  });

  MeshState copyWith({
    MeshConnectionStatus? connectionStatus,
    HelmetAudioStatus? helmetStatus,
    String? connectedHelmetName,
    String? groupCode,
    String? myAlias,
    bool? isLocalMuted,
    bool? isDeafened,
    bool? isSpeakingNow,
    double? voxThreshold,
    String? statusMessage,
  }) {
    return MeshState(
      connectionStatus: connectionStatus ?? this.connectionStatus,
      helmetStatus: helmetStatus ?? this.helmetStatus,
      connectedHelmetName: connectedHelmetName ?? this.connectedHelmetName,
      groupCode: groupCode ?? this.groupCode,
      myAlias: myAlias ?? this.myAlias,
      isLocalMuted: isLocalMuted ?? this.isLocalMuted,
      isDeafened: isDeafened ?? this.isDeafened,
      isSpeakingNow: isSpeakingNow ?? this.isSpeakingNow,
      voxThreshold: voxThreshold ?? this.voxThreshold,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}
