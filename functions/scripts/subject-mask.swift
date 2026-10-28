// 写真 (第 1 引数のパス) の前景の被写体のマスクを、アプリの iOS と同じ Vision の前景のマスク (ios/Runner/AppDelegate.swift の
// createSubjectMaskPng) で作り、被写体が白・背景が黒の 8 bit グレースケールの PNG を第 2 引数のパスに書く。
// 前景が複数ある時は全部を 1 つのマスクにする。前景が無ければ exit 2、写真を読めない・書けない時は exit 1。
// 見本の絵を作る scripts/build-sample-art.mjs が macOS (14 以降) で呼ぶ。
//
// 使い方: swift scripts/subject-mask.swift <写真のパス> <マスクの出力パス>
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// [message] を標準エラーに書いて [code] で終える。
func fail(message: String, code: Int32) -> Never {
  FileHandle.standardError.write(Data("\(message)\n".utf8))
  exit(code)
}

guard CommandLine.arguments.count == 3 else {
  fail(message: "使い方: swift scripts/subject-mask.swift <写真のパス> <マスクの出力パス>", code: 1)
}
guard
  let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
  let photo = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
  fail(message: "写真を読めませんでした: \(CommandLine.arguments[1])", code: 1)
}
let request = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(cgImage: photo, orientation: .up)
do {
  try handler.perform([request])
} catch {
  fail(message: "Vision の前景のマスクを作れませんでした: \(error)", code: 1)
}
guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
  fail(message: "前景の被写体が見つかりませんでした", code: 2)
}
let mask: CVPixelBuffer
do {
  mask = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
} catch {
  fail(message: "マスクを写真の大きさにできませんでした: \(error)", code: 1)
}
// 値の写し方はアプリの grayscalePng と同じ (Core Image を通すと色空間の変換で白が 255 にならないおそれがあるため)
let pixelFormat = CVPixelBufferGetPixelFormatType(mask)
guard pixelFormat == kCVPixelFormatType_OneComponent32Float || pixelFormat == kCVPixelFormatType_OneComponent8 else {
  fail(message: "マスクの画素の形式 \(pixelFormat) を読めません", code: 1)
}
CVPixelBufferLockBaseAddress(mask, .readOnly)
guard let baseAddress = CVPixelBufferGetBaseAddress(mask) else {
  fail(message: "マスクの画素を読めませんでした", code: 1)
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
CVPixelBufferUnlockBaseAddress(mask, .readOnly)
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
  let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)
else {
  fail(message: "マスクの PNG を作れませんでした", code: 1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
  fail(message: "マスクの PNG を書けませんでした: \(CommandLine.arguments[2])", code: 1)
}
