import AVFoundation
import Flutter
import ImageIO
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  private let worker = DispatchQueue(label: "app.localdrop.native", qos: .userInitiated)

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "app.localdrop/native", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "startHosting":
      // iOS cannot keep a server running indefinitely in the background.
      // Ask for the limited extra time iOS grants and keep the screen awake
      // while the app is in front. See docs/PLATFORM_NOTES.md.
      UIApplication.shared.isIdleTimerDisabled = true
      beginBackgroundTask()
      result(nil)
    case "stopHosting":
      UIApplication.shared.isIdleTimerDisabled = false
      endBackgroundTask()
      result(nil)
    case "keepScreenOn":
      UIApplication.shared.isIdleTimerDisabled = (args["on"] as? Bool) ?? false
      result(nil)
    case "thumbnail":
      guard let path = args["path"] as? String else {
        result(FlutterError(code: "bad_args", message: "path is required", details: nil))
        return
      }
      let video = (args["video"] as? Bool) ?? false
      let maxSize = (args["maxSize"] as? Int) ?? 480
      worker.async {
        let data = video ? Self.videoThumbnail(path, maxSize) : Self.imageThumbnail(path, maxSize)
        DispatchQueue.main.async { result(data.map { FlutterStandardTypedData(bytes: $0) }) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    super.applicationDidEnterBackground(application)
    if UIApplication.shared.isIdleTimerDisabled { beginBackgroundTask() }
  }

  private func beginBackgroundTask() {
    guard backgroundTask == .invalid else { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "LocalDropHosting") { [weak self] in
      self?.endBackgroundTask()
    }
  }

  private func endBackgroundTask() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }

  private static func jpeg(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
    return CGImageDestinationFinalize(dest) ? data as Data : nil
  }

  /// Handles HEIC/HEIF and applies EXIF orientation without decoding the full image.
  static func imageThumbnail(_ path: String, _ maxSize: Int) -> Data? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxSize,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
    return jpeg(cg)
  }

  static func videoThumbnail(_ path: String, _ maxSize: Int) -> Data? {
    let gen = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: path)))
    gen.appliesPreferredTrackTransform = true
    gen.maximumSize = CGSize(width: maxSize, height: maxSize)
    guard let cg = try? gen.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 600), actualTime: nil)
      ?? gen.copyCGImage(at: .zero, actualTime: nil)
    else { return nil }
    return jpeg(cg)
  }
}
