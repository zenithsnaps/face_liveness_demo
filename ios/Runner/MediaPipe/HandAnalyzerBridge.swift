import Foundation
import MediaPipeTasksVision
import UIKit

/// Wraps MediaPipe Tasks [HandLandmarker] in IMAGE running mode.
///
/// The `.task` model file must be bundled into the Runner target's resources:
///   1. Drag `hand_landmarker.task` into the Runner folder in Xcode.
///   2. Ensure "Copy items if needed" and the Runner target checkbox are ticked.
final class HandAnalyzerBridge {
    private let landmarker: HandLandmarker

    init() throws {
        let modelPath = try Self.requireModelPath(name: "hand_landmarker", ext: "task")
        let options = HandLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .image
        options.numHands = 2
        options.minHandDetectionConfidence = 0.5
        options.minHandPresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5
        landmarker = try HandLandmarker(options: options)
    }

    func detect(frame: FrameArgs) throws -> [[String: Any]] {
        guard let uiImage = FrameDecoder.decodeUprightImage(frame: frame) else {
            return []
        }
        let mpImage = try MPImage(uiImage: uiImage)
        let result = try landmarker.detect(image: mpImage)

        let width = Double(uiImage.size.width)
        let height = Double(uiImage.size.height)

        var hands: [[String: Any]] = []
        for (i, landmarkList) in result.landmarks.enumerated() {
            let handCategory = i < result.handedness.count ? result.handedness[i].first : nil
            let label = handCategory?.categoryName ?? "Unknown"
            let score = Double(handCategory?.score ?? 0)
            let points = landmarkList.map { lm -> [Double] in
                [Double(lm.x) * width, Double(lm.y) * height]
            }
            hands.append([
                "handedness": label,
                "confidence": score,
                "landmarks": points,
            ])
        }
        return hands
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
