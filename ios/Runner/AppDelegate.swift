import Flutter
import UIKit
import AVFoundation
import MultipeerConnectivity
import NetworkExtension

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let helmetAudioManager = HelmetAudioManager()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let audioChannel = FlutterMethodChannel(
        name: "com.motointercom.app/audio",
        binaryMessenger: controller.binaryMessenger
      )
      audioChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        switch call.method {
        case "startHelmetSco":
          result(self.helmetAudioManager.startHelmetSco())
        case "stopHelmetSco":
          self.helmetAudioManager.stopHelmetSco()
          result(nil)
        case "playPcmFrame":
          if let typedData = call.arguments as? FlutterStandardTypedData {
            self.helmetAudioManager.playPcmFrame(typedData.data)
          }
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      let micChannel = FlutterEventChannel(
        name: "com.motointercom.app/mic_stream",
        binaryMessenger: controller.binaryMessenger
      )
      micChannel.setStreamHandler(MicStreamHandler(manager: helmetAudioManager))

      let meshChannel = FlutterMethodChannel(
        name: "com.motointercom.app/mesh",
        binaryMessenger: controller.binaryMessenger
      )
      meshChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        switch call.method {
        case "startMultipeerMesh":
          if let args = call.arguments as? [String: Any] {
            let groupCode = args["groupCode"] as? String ?? "RODA-01"
            let alias = args["alias"] as? String ?? "Piloto"
            self.helmetAudioManager.startMultipeerMesh(groupCode: groupCode, alias: alias)
          }
          result(nil)
        case "sendMultipeerAudio":
          if let typedData = call.arguments as? FlutterStandardTypedData {
            self.helmetAudioManager.sendMultipeerAudio(typedData.data)
          }
          result(nil)
        case "stopMultipeerMesh", "leaveWifiDirectGroup":
          self.helmetAudioManager.stopMultipeerMesh()
          result(nil)
        case "joinWifiDirectSsid":
          if let args = call.arguments as? [String: Any],
             let ssid = args["ssid"] as? String,
             let pass = args["passphrase"] as? String {
            self.helmetAudioManager.joinOfflineGroupWifi(ssid: ssid, passphrase: pass) { ok in
              result(ok)
            }
          } else {
            result(false)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      let meshEvents = FlutterEventChannel(
        name: "com.motointercom.app/mesh_events",
        binaryMessenger: controller.binaryMessenger
      )
      meshEvents.setStreamHandler(MeshEventStreamHandler(manager: helmetAudioManager))
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

private final class MicStreamHandler: NSObject, FlutterStreamHandler {
  private weak var manager: HelmetAudioManager?
  init(manager: HelmetAudioManager) { self.manager = manager }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    manager?.setMicEventSink(events)
    let noError: FlutterError? = nil
    return noError
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    manager?.setMicEventSink(nil)
    let noError: FlutterError? = nil
    return noError
  }
}

private final class MeshEventStreamHandler: NSObject, FlutterStreamHandler {
  private weak var manager: HelmetAudioManager?
  init(manager: HelmetAudioManager) { self.manager = manager }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    manager?.setMeshEventSink(events)
    let noError: FlutterError? = nil
    return noError
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    manager?.setMeshEventSink(nil)
    let noError: FlutterError? = nil
    return noError
  }
}

// MARK: - HelmetAudioManager & Multipeer Mesh Implementation

final class HelmetAudioManager: NSObject {
    private let audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: true
    )!

    private var micEventSink: FlutterEventSink?
    private var meshEventSink: FlutterEventSink?
    private var isCapturing = false

    private let serviceType = "motomesh"
    private var myPeerId: MCPeerID?
    private var mcSession: MCSession?
    private var mcAdvertiser: MCNearbyServiceAdvertiser?
    private var mcBrowser: MCNearbyServiceBrowser?
    private var activeGroupCode: String = "RODA-01"

    func setMicEventSink(_ sink: FlutterEventSink?) {
        micEventSink = sink
        if sink == nil {
            stopAudioEngine()
        }
    }

    func setMeshEventSink(_ sink: FlutterEventSink?) {
        meshEventSink = sink
    }

    func startHelmetSco() -> [String: Any] {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            try session.setPreferredSampleRate(16000)
            try session.setActive(true)

            let btInput = session.availableInputs?.first { input in
                input.portType == .bluetoothHFP
            }
            if let bt = btInput {
                try session.setPreferredInput(bt)
            }

            startAudioEngine()

            if let bt = btInput {
                return ["connected": true, "deviceName": bt.portName]
            }
            return ["connected": false, "deviceName": NSNull()]
        } catch {
            return ["connected": false, "error": error.localizedDescription]
        }
    }

    func stopHelmetSco() {
        stopAudioEngine()
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func startAudioEngine() {
        if isCapturing { return }
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        if !audioEngine.attachedNodes.contains(playerNode) {
            audioEngine.attach(playerNode)
        }
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: targetFormat)

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            return
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, let sink = self.micEventSink else { return }
            let ratio = self.targetFormat.sampleRate / inputFormat.sampleRate
            let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let converted = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: outCapacity) else {
                return
            }

            var error: NSError?
            var inputConsumed = false
            converter.convert(to: converted, error: &error) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil, converted.frameLength > 0, let channelData = converted.int16ChannelData {
                let byteCount = Int(converted.frameLength) * MemoryLayout<Int16>.size
                let data = Data(bytes: channelData[0], count: byteCount)
                DispatchQueue.main.async {
                    sink(FlutterStandardTypedData(bytes: data))
                }
            }
        }

        do {
            try audioEngine.start()
            playerNode.play()
            isCapturing = true
        } catch {
            isCapturing = false
        }
    }

    private func stopAudioEngine() {
        if !isCapturing { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        playerNode.stop()
        audioEngine.stop()
        isCapturing = false
    }

    func playPcmFrame(_ data: Data) {
        if !isCapturing || data.count < 2 { return }
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else {
            return
        }
        buffer.frameLength = frameCount
        if let dst = buffer.int16ChannelData {
            data.withUnsafeBytes { rawPtr in
                if let src = rawPtr.bindMemory(to: Int16.self).baseAddress {
                    dst[0].update(from: src, count: Int(frameCount))
                }
            }
            playerNode.scheduleBuffer(buffer, completionHandler: nil)
        }
    }

    // MARK: MultipeerConnectivity

    func startMultipeerMesh(groupCode: String, alias: String) {
        stopMultipeerMesh()
        activeGroupCode = groupCode.uppercased()

        let peer = MCPeerID(displayName: alias.isEmpty ? UIDevice.current.name : alias)
        myPeerId = peer

        let session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self
        mcSession = session

        let advertiser = MCNearbyServiceAdvertiser(
            peer: peer,
            discoveryInfo: ["group": activeGroupCode],
            serviceType: serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        mcAdvertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        mcBrowser = browser
    }

    func sendMultipeerAudio(_ data: Data) {
        guard let session = mcSession, !session.connectedPeers.isEmpty else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .unreliable)
    }

    func stopMultipeerMesh() {
        mcAdvertiser?.stopAdvertisingPeer()
        mcAdvertiser = nil
        mcBrowser?.stopBrowsingForPeers()
        mcBrowser = nil
        mcSession?.disconnect()
        mcSession = nil
        myPeerId = nil
    }

    func joinOfflineGroupWifi(ssid: String, passphrase: String, completion: @escaping (Bool) -> Void) {
        let config = NEHotspotConfiguration(ssid: ssid, passphrase: passphrase, isWEP: false)
        config.joinOnce = true
        NEHotspotConfigurationManager.shared.apply(config) { error in
            completion(error == nil)
        }
    }
}

extension HelmetAudioManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let statusStr: String
        switch state {
        case .connected:
            statusStr = "connected"
        case .connecting:
            statusStr = "connecting"
        case .notConnected:
            statusStr = "disconnected"
        @unknown default:
            statusStr = "disconnected"
        }
        DispatchQueue.main.async { [weak self] in
            self?.meshEventSink?([
                "event": "peerState",
                "peerId": peerID.displayName,
                "alias": peerID.displayName,
                "state": statusStr
            ])
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            self?.meshEventSink?([
                "event": "audio",
                "peerId": peerID.displayName,
                "data": FlutterStandardTypedData(bytes: data)
            ])
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension HelmetAudioManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, mcSession)
    }
}

extension HelmetAudioManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let session = mcSession else { return }
        if info?["group"] == activeGroupCode {
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
