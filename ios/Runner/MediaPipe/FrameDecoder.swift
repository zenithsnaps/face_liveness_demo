import CoreGraphics
import CoreImage
import Foundation
import UIKit

/// Decodes a `FrameArgs` into an upright `UIImage` ready for MediaPipe's
/// `MPImage` constructor.
enum FrameDecoder {
    static func decodeUprightImage(frame: FrameArgs) -> UIImage? {
        let raw: UIImage?
        switch frame.format.lowercased() {
        case "bgra8888":
            raw = imageFromBGRA(bytes: frame.bytes, width: frame.width, height: frame.height)
        case "rgba8888":
            raw = imageFromRGBA(bytes: frame.bytes, width: frame.width, height: frame.height)
        case "nv21", "yuv420":
            // iOS camera plugin sends BGRA, but support YUV→RGB for completeness.
            raw = imageFromYUV420(bytes: frame.bytes, width: frame.width, height: frame.height)
        default:
            raw = nil
        }
        guard let base = raw else { return nil }
        return rotate(image: base, degrees: frame.rotation)
    }

    private static func imageFromBGRA(bytes: Data, width: Int, height: Int) -> UIImage? {
        let bitsPerComponent = 8
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo = [
            .byteOrder32Little,
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue),
        ]
        return bytes.withUnsafeBytes { raw -> UIImage? in
            guard let base = raw.baseAddress else { return nil }
            let mutable = UnsafeMutableRawPointer(mutating: base)
            guard let ctx = CGContext(
                data: mutable,
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue,
            ), let cg = ctx.makeImage() else {
                return nil
            }
            return UIImage(cgImage: cg)
        }
    }

    private static func imageFromRGBA(bytes: Data, width: Int, height: Int) -> UIImage? {
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        return bytes.withUnsafeBytes { raw -> UIImage? in
            guard let base = raw.baseAddress else { return nil }
            let mutable = UnsafeMutableRawPointer(mutating: base)
            guard let ctx = CGContext(
                data: mutable,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue,
            ), let cg = ctx.makeImage() else {
                return nil
            }
            return UIImage(cgImage: cg)
        }
    }

    private static func imageFromYUV420(bytes: Data, width: Int, height: Int) -> UIImage? {
        // Minimal YUV→RGB conversion (BT.601). iOS camera plugin normally sends
        // BGRA so this path is rarely hit — included for symmetry.
        let pixelCount = width * height
        guard bytes.count >= pixelCount + pixelCount / 2 else { return nil }
        var rgba = [UInt8](repeating: 0, count: pixelCount * 4)
        bytes.withUnsafeBytes { rawPtr in
            guard let basePtr = rawPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let yPlane = basePtr
            let uvPlane = basePtr.advanced(by: pixelCount)
            for row in 0..<height {
                for col in 0..<width {
                    let yIdx = row * width + col
                    let uvIdx = pixelCount + (row / 2) * width + (col / 2) * 2
                    let y = Int(yPlane[yIdx])
                    let u = Int(uvPlane[uvIdx]) - 128
                    let v = Int(uvPlane[uvIdx + 1]) - 128
                    let r = clamp(y + ((91881 * v) >> 16))
                    let g = clamp(y - ((22554 * u + 46802 * v) >> 16))
                    let b = clamp(y + ((116130 * u) >> 16))
                    let offset = yIdx * 4
                    rgba[offset] = UInt8(r)
                    rgba[offset + 1] = UInt8(g)
                    rgba[offset + 2] = UInt8(b)
                    rgba[offset + 3] = 255
                }
            }
        }
        return imageFromRGBA(bytes: Data(rgba), width: width, height: height)
    }

    private static func clamp(_ v: Int) -> Int {
        return max(0, min(255, v))
    }

    private static func rotate(image: UIImage, degrees: Int) -> UIImage {
        if degrees % 360 == 0 { return image }
        let radians = CGFloat(degrees) * .pi / 180
        let newSize = CGRect(origin: .zero, size: image.size)
            .applying(CGAffineTransform(rotationAngle: radians))
            .integral
            .size
        UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return image }
        ctx.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        ctx.rotate(by: radians)
        image.draw(in: CGRect(
            x: -image.size.width / 2,
            y: -image.size.height / 2,
            width: image.size.width,
            height: image.size.height,
        ))
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
}
