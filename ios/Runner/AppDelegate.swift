import Flutter
import ImageIO
import UIKit
import UniformTypeIdentifiers
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
        let maskData = try createSubjectMaskPng(photo: photo.data).map { FlutterStandardTypedData(bytes: $0) }
        DispatchQueue.main.async { result(maskData) }
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
  /// Vision が返したマスクの画素の形式 (CVPixelBuffer の pixel format type) を読めない。
  case unsupportedMaskPixelFormat(OSType)

  var errorDescription: String? {
    switch self {
    case .unreadablePhoto: return "写真を読めませんでした"
    case .maskEncodingFailed: return "切り出しのマスクを画像にできませんでした"
    case .unsupportedMaskPixelFormat(let pixelFormat): return "切り出しのマスクの画素の形式 \(pixelFormat) を読めません"
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
  return try grayscalePng(mask: observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler))
}

/// Vision のマスク [mask] (1 成分の float で 0 が背景・1 が被写体、または 1 成分の 8 bit で 0〜255) を、値を 0〜255 にそのまま写した
/// 8 bit グレースケールの PNG にする。Core Image で書き出すと色空間の変換で白が 255 にならないおそれがあり、サーバーは 128 以上を
/// 被写体とみなすため (functions/src/generation/cutout.ts の SUBJECT_ALPHA_THRESHOLD)、画素の値を自分で写す。
/// 2026-10-28 に macOS の同じ API (functions/scripts/subject-mask.swift) で 1 成分の float が返ることを確かめた。それ以外の形式は失敗にする。
func grayscalePng(mask: CVPixelBuffer) throws -> Data {
  let pixelFormat = CVPixelBufferGetPixelFormatType(mask)
  guard pixelFormat == kCVPixelFormatType_OneComponent32Float || pixelFormat == kCVPixelFormatType_OneComponent8 else {
    throw SubjectMaskError.unsupportedMaskPixelFormat(pixelFormat)
  }
  CVPixelBufferLockBaseAddress(mask, .readOnly)
  defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
  guard let baseAddress = CVPixelBufferGetBaseAddress(mask) else {
    throw SubjectMaskError.maskEncodingFailed
  }
  let width = CVPixelBufferGetWidth(mask)
  let height = CVPixelBufferGetHeight(mask)
  let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
  var grayPixels = [UInt8](repeating: 0, count: width * height)
  for y in 0..<height {
    let rowAddress = baseAddress.advanced(by: y * bytesPerRow)
    for x in 0..<width {
      if pixelFormat == kCVPixelFormatType_OneComponent8 {
        grayPixels[y * width + x] = rowAddress.assumingMemoryBound(to: UInt8.self)[x]
        continue
      }
      let floatValue = rowAddress.assumingMemoryBound(to: Float32.self)[x]
      let value = floatValue.isNaN ? 0 : min(max(floatValue, 0), 1)
      grayPixels[y * width + x] = UInt8((value * 255).rounded())
    }
  }
  let pngData = NSMutableData()
  guard
    let provider = CGDataProvider(data: Data(grayPixels) as CFData),
    let image = CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 8,
      bytesPerRow: width,
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    ),
    let destination = CGImageDestinationCreateWithData(pngData, UTType.png.identifier as CFString, 1, nil)
  else {
    throw SubjectMaskError.maskEncodingFailed
  }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    throw SubjectMaskError.maskEncodingFailed
  }
  return pngData as Data
}
