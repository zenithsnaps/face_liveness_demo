import Foundation
import MediaPipeTasksVision
import UIKit

/// Wraps MediaPipe Tasks [FaceDetector] in IMAGE running mode.
///
/// Returns [{confidence, bbox: {left, top, width, height}}] per detected face.
final class FaceDetectorBridge {
    private let detector: FaceDetector

    init() throws {
        let modelPath = try Self.requireModelPath(name: "blaze_face_short_range", ext: "tflite")
        let options = FaceDetectorOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .image
        options.minDetectionConfidence = 0.5
        detector = try FaceDetector(options: options)
    }

    func detect(frame: FrameArgs) throws -> [[String: Any]] {
        guard let uiImage = FrameDecoder.decodeUprightImage(frame: frame) else {
            return []
        }
        let mpImage = try MPImage(uiImage: uiImage)
        let result = try detector.detect(image: mpImage)

        var out: [[String: Any]] = []
        for detection in result.detections {
            let score = Double(detection.categories.first?.score ?? 0)
            let box = detection.boundingBox
            out.append([
                "confidence": score,
                "bbox": [
                    "left": Double(box.origin.x),
                    "top": Double(box.origin.y),
                    "width": Double(box.size.width),
                    "height": Double(box.size.height),
                ],
            ])
        }
        return out
    }

    private static func requireModelPath(name: String, ext: String) throws -> String {
        guard let path = Bundle.main.path(forResource: name, ofType: ext) else {
            throw NSError(
                domain: "MediaPipePlugin",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Missing bundled model: \(name).\(ext)"],
            )
        }
        return path
    }
}
