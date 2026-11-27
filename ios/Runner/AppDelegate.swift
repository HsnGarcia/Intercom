import Flutter
import UIKit

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
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    manager?.setMicEventSink(nil)
    return nil
  }
}

private final class MeshEventStreamHandler: NSObject, FlutterStreamHandler {
  private weak var manager: HelmetAudioManager?
  init(manager: HelmetAudioManager) { self.manager = manager }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    manager?.setMeshEventSink(events)
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    manager?.setMeshEventSink(nil)
    return nil
  }
}
