import CoreImage
import Flutter
import UIKit
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// OS の切り出しを Dart (lib/features/capture/subject_mask.dart) に渡す channel。engine が生きている間持つ。
  private var subjectMaskChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "snapmon/subject_mask",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler(handleSubjectMaskCall)
    subjectMaskChannel = channel
  }

  /// `createSubjectMask` (引数は生成に送る写真の JPEG) に、被写体が白・背景が黒のマスクの PNG を返す。iOS 16 以前と、被写体が
  /// 見つからなかった時は nil、Vision が失敗した時は FlutterError を返す。Vision はメインスレッドの外で動かす (数百ミリ秒かかり、画面を止めないため)。
  private func handleSubjectMaskCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "createSubjectMask", let photo = call.arguments as? FlutterStandardTypedData else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard #available(iOS 17.0, *) else {
      result(nil)
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let mask = try createSubjectMaskPng(photo: photo.data)
        DispatchQueue.main.async { result(mask.map { FlutterStandardTypedData(bytes: $0) }) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "subject_mask_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}

/// OS の切り出しのマスクを作れなかった理由。
enum SubjectMaskError: LocalizedError {
  /// 写真を画像として読めなかった。
  case unreadablePhoto
  /// マスクを PNG にできなかった。
  case maskEncodingFailed

  var errorDescription: String? {
    switch self {
    case .unreadablePhoto: return "写真を読めませんでした"
    case .maskEncodingFailed: return "切り出しのマスクを画像にできませんでした"
    }
  }
}

/// [photo] (向きを画素に反映した JPEG) の前景の被写体を、写真の長押しで被写体を持ち上げる機能と同じ Vision の前景のマスクで切り出し、
/// 被写体が白・背景が黒の 8 bit グレースケールの PNG (大きさは写真と同じ) を返す。被写体が見つからなければ nil。
/// 前景の被写体が複数ある時は、全部を 1 つのマスクにする (どれか 1 つを選ぶ操作を挟まないため)。
/// API: https://developer.apple.com/documentation/vision/vngenerateforegroundinstancemaskrequest (iOS 17.0+)
@available(iOS 17.0, *)
func createSubjectMaskPng(photo: Data) throws -> Data? {
  // Dart 側 (prepareGenerationPhoto) が向きを画素に反映して送るため、向きは .up で読む
  guard let cgImage = UIImage(data: photo)?.cgImage else {
    throw SubjectMaskError.unreadablePhoto
  }
  let request = VNGenerateForegroundInstanceMaskRequest()
  let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
  try handler.perform([request])
  guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
    return nil
  }
  let maskBuffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
  guard
    let png = CIContext().pngRepresentation(
      of: CIImage(cvPixelBuffer: maskBuffer),
      format: .L8,
      colorSpace: CGColorSpaceCreateDeviceGray()
    )
  else {
    throw SubjectMaskError.maskEncodingFailed
  }
  return png
}
