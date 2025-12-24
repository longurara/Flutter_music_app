import Flutter
import UIKit
import MediaPlayer
import ObjectiveC

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    setupAppleMusicPicker()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func setupAppleMusicPicker() {
    guard let controller = window?.rootViewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(name: "apple_music_picker", binaryMessenger: controller.binaryMessenger)

    channel.setMethodCallHandler { [weak controller] (call, result) in
      guard call.method == "pick" else {
        result(FlutterMethodNotImplemented)
        return
      }
      MPMediaLibrary.requestAuthorization { status in
        guard status == .authorized else {
          result(FlutterError(code: "no_permission", message: "Apple Music access denied", details: nil))
          return
        }
        DispatchQueue.main.async {
          let picker = MPMediaPickerController(mediaTypes: .music)
          picker.allowsPickingMultipleItems = true
          picker.prompt = "Chọn nhạc từ Apple Music"
          let delegate = AppleMusicPickerDelegate(result: result)
          picker.delegate = delegate
          // Hold delegate strongly by associating with picker.
          objc_setAssociatedObject(picker, Unmanaged.passUnretained(picker).toOpaque(), delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
          controller?.present(picker, animated: true)
        }
      }
    }
  }
}

private class AppleMusicPickerDelegate: NSObject, MPMediaPickerControllerDelegate {
  private let result: FlutterResult

  init(result: @escaping FlutterResult) {
    self.result = result
    super.init()
  }

  func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
    let items = mediaItemCollection.items.compactMap { item -> [String: Any]? in
      guard let url = item.assetURL else { return nil } // Stream-only tracks have nil
      var dict: [String: Any] = [
        "title": item.title ?? "",
        "artist": item.artist ?? "",
        "album": item.albumTitle ?? "",
        "duration": item.playbackDuration,
        "url": url.absoluteString
      ]
      if let art = item.artwork?.image(at: CGSize(width: 300, height: 300)),
         let data = art.pngData() {
        dict["artwork"] = data.base64EncodedString()
      }
      return dict
    }
    result(items)
    mediaPicker.dismiss(animated: true)
  }

  func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
    result([])
    mediaPicker.dismiss(animated: true)
  }
}
