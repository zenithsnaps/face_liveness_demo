import CoreGraphics
import Flutter
import Foundation
import UIKit

/// Decodes a `FrameArgs` payload into upright RGBA8888 bytes plus the upright
/// dimensions. Used by the Dart side to feed analyzers that expect rotation=0
/// RGBA (ML Kit eye contour + EyeOcclusionUtil pixel analysis).
enum UprightRgbaBridge {
    static func decode(frame: FrameArgs) -> [String: Any]? {
        guard let image = FrameDecoder.decodeUprightImage(frame: frame),
              let cg = image.cgImage else {
            return nil
        }
        let width = cg.width
        let height = cg.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = pixels.withUnsafeMutableBytes({ raw -> CGContext? in
            CGContext(
                data: raw.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue,
            )
        }) else {
            return nil
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return [
            "bytes": FlutterStandardTypedData(bytes: Data(pixels)),
            "width": width,
            "height": height,
        ]
    }
}
