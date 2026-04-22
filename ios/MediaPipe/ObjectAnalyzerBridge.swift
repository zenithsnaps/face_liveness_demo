import Foundation
import MediaPipeTasksVision
import UIKit

/// Wraps MediaPipe Tasks [ObjectDetector] in IMAGE running mode.
///
/// The `.tflite` model file must be bundled into the Runner target's resources.
final class ObjectAnalyzerBridge {
    private let detector: ObjectDetector

    init() throws {
        let modelPath = try Self.requireModelPath(name: "efficientdet_lite0", ext: "tflite")
        let options = ObjectDetectorOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .image
        options.maxResults = 5
        options.scoreThreshold = 0.5
        detector = try ObjectDetector(options: options)
    }

    func detect(frame: FrameArgs) throws -> [[String: Any]] {
        guard let uiImage = FrameDecoder.decodeUprightImage(frame: frame) else {
            return []
        }
        let mpImage = try MPImage(uiImage: uiImage)
        let result = try detector.detect(image: mpImage)

        var out: [[String: Any]] = []
        for detection in result.detections {
            let category = detection.categories.first
            let box = detection.boundingBox
            out.append([
                "label": category?.categoryName ?? "unknown",
                "confidence": Double(category?.score ?? 0),
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
