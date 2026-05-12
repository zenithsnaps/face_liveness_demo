import Foundation
import UIKit

/// Encodes a `FrameArgs` payload as an upright JPEG written to `outPath`.
///
/// Reuses `FrameDecoder.decodeUprightImage` (BGRA / RGBA / YUV → upright UIImage)
/// and emits a JPEG at the requested quality. Returns the path on success or
/// `nil` if decoding/encoding failed.
enum JpegEncoderBridge {
    static func encode(frame: FrameArgs, quality: Int, outPath: String) -> String? {
        guard let image = FrameDecoder.decodeUprightImage(frame: frame) else {
            return nil
        }
        let q = max(1, min(100, quality))
        let cq = CGFloat(q) / 100.0
        guard let data = image.jpegData(compressionQuality: cq) else { return nil }
        do {
            try data.write(to: URL(fileURLWithPath: outPath), options: .atomic)
            return outPath
        } catch {
            return nil
        }
    }
}
