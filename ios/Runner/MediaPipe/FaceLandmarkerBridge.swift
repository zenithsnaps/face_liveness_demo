import Foundation
import MediaPipeTasksVision
import UIKit

/// Wraps MediaPipe Tasks [FaceLandmarker] in IMAGE running mode.
///
/// The `.task` model file must be bundled into the Runner target's resources:
///   1. Drag `face_landmarker.task` into the Runner folder in Xcode.
///   2. Ensure "Copy items if needed" and the Runner target checkbox are ticked.
///
/// Returns a single dict per call:
///   { "found": Bool, "landmarks": [[x, y, z, visibility, presence] × 478] }
///
/// Only the first detected face is returned. `found: false` when no face is visible.
final class FaceLandmarkerBridge {
    private let landmarker: FaceLandmarker

    init() throws {
        let modelPath = try Self.requireModelPath(name: "face_landmarker", ext: "task")
        let options = FaceLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .image
        options.numFaces = 1
        options.minFaceDetectionConfidence = 0.5
        options.minFacePresenceConfidence = 0.5
        options.minTrackingConfidence = 0.5
        landmarker = try FaceLandmarker(options: options)
    }

    func detect(frame: FrameArgs) throws -> [String: Any] {
        guard let uiImage = FrameDecoder.decodeUprightImage(frame: frame) else {
            return ["found": false, "landmarks": [[Any]]()]
        }
        let mpImage = try MPImage(uiImage: uiImage)
        let result = try landmarker.detect(image: mpImage)

        guard let faceLandmarks = result.faceLandmarks.first else {
            return ["found": false, "landmarks": [[Any]]()]
        }

        let landmarks: [[Double]] = faceLandmarks.map { lm in
            [
                Double(lm.x),
                Double(lm.y),
                Double(lm.z),
                Double(lm.visibility?.floatValue ?? 0),
                Double(lm.presence?.floatValue ?? 0),
            ]
        }
        return ["found": true, "landmarks": landmarks]
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
