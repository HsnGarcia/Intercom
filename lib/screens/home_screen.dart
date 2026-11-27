import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/mesh_state.dart';
import '../services/intercom_controller.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _groupController = TextEditingController(text: 'RODA-01');
  final _aliasController = TextEditingController(text: 'Piloto 1');

  @override
  void dispose() {
    _groupController.dispose();
    _aliasController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<IntercomController>();
    final state = controller.state;
    final peers = controller.peers;
    final isConnected =
        state.connectionStatus == MeshConnectionStatus.connectedOffline;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'MotoMesh Offline',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Chip(
                backgroundColor: state.helmetStatus ==
                        HelmetAudioStatus.helmetConnected
                    ? Colors.green.shade800
                    : Colors.orange.shade900,
                label: Text(
                  state.helmetStatus == HelmetAudioStatus.helmetConnected
                      ? (state.connectedHelmetName ?? 'Casco BT OK')
                      : 'Sin Casco BT',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tarjeta de estado de conexión offline
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isConnected
                        ? const Color(0xFF00E676)
                        : Colors.white24,
                    width: 2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isConnected ? Icons.wifi_tethering : Icons.podcasts,
                          color: isConnected
                              ? const Color(0xFF00E676)
                              : const Color(0xFFFF6B00),
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            state.statusMessage ??
                                'Listo para rodar sin internet',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!isConnected) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _aliasController,
                              decoration: const InputDecoration(
                                labelText: 'Tu Nombre / Moto',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _groupController,
                              decoration: const InputDecoration(
                                labelText: 'Código Rodada',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Control de sensibilidad VOX (Manos libres contra viento)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Filtro Viento / Sensibilidad VOX',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (state.isSpeakingNow)
                          const Text(
                            'TRANSMITIENDO',
                            style: TextStyle(
                              color: Color(0xFF00E676),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                    Slider(
                      value: state.voxThreshold.clamp(0.01, 0.30),
                      min: 0.01,
                      max: 0.30,
                      divisions: 15,
                      label:
                          'Umbral ${(state.voxThreshold * 100).round()}%',
                      onChanged: controller.updateVoxThreshold,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Lista de pilotos en la malla
              Text(
                'Pilotos en el grupo (${peers.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: peers.isEmpty
                    ? Center(
                        child: Text(
                          isConnected
                              ? 'Buscando motos cercanas con código ${state.groupCode}...'
                              : 'Conecta tu casco por Bluetooth y presiona INICIAR RODADA.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 16,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: peers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          final peer = peers[index];
                          return ListTile(
                            tileColor: const Color(0xFF161B22),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: peer.isSpeaking
                                    ? const Color(0xFF00E676)
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            leading: CircleAvatar(
                              backgroundColor: peer.isSpeaking
                                  ? const Color(0xFF00E676)
                                  : const Color(0xFFFF6B00),
                              child: Icon(
                                peer.isSpeaking
                                    ? Icons.graphic_eq
                                    : Icons.sports_motorsports,
                                color: Colors.black,
                              ),
                            ),
                            title: Text(
                              peer.alias,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            subtitle: Text('Señal: ${peer.signalLabel}'),
                          );
                        },
                      ),
              ),

              // Botones grandes aptos para guantes de moto
              const SizedBox(height: 12),
              if (isConnected)
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 68,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: state.isLocalMuted
                                ? Colors.red.shade700
                                : const Color(0xFF21262D),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: controller.toggleMute,
                          icon: Icon(
                            state.isLocalMuted ? Icons.mic_off : Icons.mic,
                            size: 28,
                          ),
                          label: Text(
                            state.isLocalMuted ? 'MUTEADO' : 'MIC ON',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 68,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade900,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: controller.disconnect,
                          icon: const Icon(Icons.call_end, size: 28),
                          label: const Text(
                            'SALIR',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  height: 72,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B00),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      controller.connectToRodada(
                        groupCode: _groupController.text,
                        alias: _aliasController.text,
                      );
                    },
                    icon: const Icon(Icons.sports_motorsports, size: 30),
                    label: const Text(
                      'INICIAR RODADA OFFLINE',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
