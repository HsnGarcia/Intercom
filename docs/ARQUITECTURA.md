# MotoMesh Intercom — Arquitectura Técnica Offline (Android + iOS)

## 1. El Problema y la Solución
Los intercomunicadores de casco (Cardo, Sena, FreedConn, Ejeas, genéricos) usan protocolos propietarios para sus redes Mesh/Intercom, impidiendo que marcas distintas hablen en grupo. Sin embargo, **todos** soportan el perfil estándar **Bluetooth HFP (Hands-Free Profile)** para conectarse al teléfono móvil del piloto.

**Solución:** Cada piloto conecta su casco a su propio teléfono por Bluetooth estándar. Los teléfonos forman una **red Mesh automática sin internet** entre sí, capturan la voz del micrófono del casco, la comprimen con **Opus**, la transmiten por la red local offline y la reproducen mezclada en el auricular del casco de todos los integrantes.

---

## 2. Arquitectura de Conectividad Offline (Android + iOS)

Dado que iOS y Android no comparten un protocolo Wi-Fi Direct / P2P idéntico (Android usa `WifiP2pManager` / Nearby Connections y Apple usa `MultipeerConnectivity`), la arquitectura utiliza un **sistema híbrido automático en 2 capas** sin necesidad de activar Hotspot manualmente ni tener datos móviles:

### Capa 1: Descubrimiento y Señalización (BLE - Bluetooth Low Energy)
- **Propósito:** Descubrir motos cercanas del mismo grupo ("Rodada"), elegir un líder automáticamente, intercambiar credenciales de red local y mantener latidos (*heartbeats*).
- **Funcionamiento:**
  1. Todos los teléfonos anuncian y escanean un UUID de servicio BLE específico de la sala (derivado del nombre/código de la rodada, ej. `RODA-4821`).
  2. Se elige automáticamente un **Nodo Líder** (preferiblemente un Android con buena batería, por su capacidad de crear grupos Wi-Fi Direct autónomos sin intervención del usuario).
  3. Por característica GATT (o Manufacturer Data cifrado con clave de grupo), el Líder publica el `SSID` y `Passphrase` efímeros de la red local.

### Capa 2: Transporte de Voz de Baja Latencia (Wi-Fi Direct Automático + UDP/Opus)
- **Android (Líder o Par):** Usa `WifiP2pManager.createGroup()` para levantar un punto de acceso Wi-Fi Direct autónomo (sin internet, 100% offline).
- **iOS (Par):** Usa `NEHotspotConfigurationManager` para unirse automáticamente a ese SSID efímero con un único toque de confirmación del sistema operativo.
- **Protocolo de Audio:**
  - **UDP Unicast / Multicast** sobre la subred local (`192.168.49.x` en Wi-Fi Direct).
  - **Códec Opus:** 16 kHz (banda ancha de voz), frames de 20 ms, bitrate adaptativo de **16 a 24 kbps** por piloto (con soporte de **FEC** - Forward Error Correction para tolerar pérdida de paquetes en carretera).
  - **Mezclador (Audio Mixer):** Cada teléfono recibe los paquetes UDP de los demás, los decodifica desde su *Jitter Buffer* adaptativo (40–80 ms) y los suma con *soft-clipping* antes de enviarlos al casco.

> **Nota física de alcance:** En carretera abierta (línea de vista), el enlace Wi-Fi Direct entre teléfonos montados en el manubrio alcanza típicamente **50 a 150 metros**. Guardar el teléfono en el bolsillo o baúl metálico reduce el alcance.

---

## 3. Pipeline de Audio Manos Libres (VOX + Casco Bluetooth)

Para hablar sin soltar el manubrio:
1. **Enrutamiento Bluetooth SCO / HFP:**
   - **Android:** `AudioManager.MODE_IN_COMMUNICATION` + `startBluetoothSco()` (o `setCommunicationDevice()` en Android 12+).
   - **iOS:** `AVAudioSession` en categoría `.playAndRecord` con opciones `.allowBluetooth`, `.allowBluetoothA2DP` y modo `.voiceChat` (activa cancelación de eco por hardware).
2. **Supresión de Ruido de Viento y Motor:**
   - Filtro paso alto (HPF ~120 Hz) para cortar el retumbo del viento y escape.
   - **VAD (Voice Activity Detection)** con histéresis (ej. umbral de activación + *hangover* de 400 ms) para que no se corte la última sílaba al hablar, sin transmitir ruido de aire cuando el piloto está en silencio.
3. **UX "Modo Moto":**
   - Interfaz oscura de alto contraste, tipografía grande, botones gigantes aptos para guantes.
   - Sin distracciones: indicador visual claro de quién está hablando y estado de batería/señal.
