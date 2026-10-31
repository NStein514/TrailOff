import Flutter
import UIKit
import CoreMotion

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let skyOrientation = SkyOrientationStream()
  private var skyChannel: FlutterEventChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TrailOffSky") else { return }
    skyChannel = FlutterEventChannel(name: "trailoff/sky_orientation", binaryMessenger: registrar.messenger())
    skyChannel?.setStreamHandler(skyOrientation)
  }
}

private class SkyOrientationStream: NSObject, FlutterStreamHandler {
  private let motion = CMMotionManager()

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    motion.stopDeviceMotionUpdates()
    guard motion.isDeviceMotionAvailable,
          CMMotionManager.availableAttitudeReferenceFrames().contains(.xTrueNorthZVertical) else {
      return FlutterError(code: "unavailable", message: "True-north orientation unavailable", details: nil)
    }
    motion.deviceMotionUpdateInterval = 0.05
    motion.showsDeviceMovementDisplay = true
    motion.startDeviceMotionUpdates(using: .xTrueNorthZVertical, to: .main) { data, error in
      guard let data = data, error == nil else {
        events(FlutterError(code: "unavailable", message: "Orientation unavailable", details: nil))
        return
      }
      guard data.magneticField.accuracy != .uncalibrated else { return }
      let r = data.attitude.rotationMatrix
      // Core Motion reference is north, west, up. Convert ENU -> device.
      let x = [-r.m12, r.m11, r.m13]
      let y = [-r.m22, r.m21, r.m23]
      let z = [-r.m32, r.m31, r.m33]
      let orientation = (UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene)?.interfaceOrientation
      let matrix: [Double]
      switch orientation {
      case .landscapeLeft: matrix = y.map { -$0 } + x + z
      case .landscapeRight: matrix = y + x.map { -$0 } + z
      case .portraitUpsideDown: matrix = x.map { -$0 } + y.map { -$0 } + z
      default: matrix = x + y + z
      }
      events(matrix)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    motion.stopDeviceMotionUpdates()
    return nil
  }
}
