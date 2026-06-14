import Foundation
import MediaPipeTasksVision
import UIKit

/// Wraps MediaPipe Tasks [ImageClassifier] in IMAGE running mode for the
/// sunglasses model.
///
/// Runs on MediaPipe's OWN embedded TFLite — no second `TensorFlowLiteC`
/// framework, so it links cleanly alongside the hand/object/face tasks (avoids
/// the duplicate-symbol clash that `tflite_flutter` caused on iOS).
///
/// The model must be the MediaPipe-shaped export (see
/// `tools/glasses_export/export_onnx_mediapipe.py`): NHWC, with `/255` +
/// ImageNet normalization in `NormalizationOptions` metadata and a 1-label map
/// `["sunglasses"]`. The single category's score is `P(sunglasses)`.
///
/// The `.tflite` must be bundled into the Runner target's resources as
/// `glasses_sunglasses.tflite`.
final class GlassesClassifierBridge {
    private let classifier: ImageClassifier

    init() throws {
        let modelPath = try Self.requireModelPath(name: "glasses_sunglasses", ext: "tflite")
        let options = ImageClassifierOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .image
        options.maxResults = 1
        classifier = try ImageClassifier(options: options)
    }

    /// Returns `P(sunglasses)` in `[0, 1]`, or `nil` when the frame can't be
    /// decoded. `roi` (when provided) is the face box in NORMALIZED `[0,1]`
    /// coordinates of the upright frame; MediaPipe crops + resizes + normalizes.
    func classify(frame: FrameArgs, roi: CGRect?) throws -> Double? {
        guard let uiImage = FrameDecoder.decodeUprightImage(frame: frame) else {
            return nil
        }
        let mpImage = try MPImage(uiImage: uiImage)

        // iOS exposes the ROI directly on classify(image:regionOfInterest:)
        // (no ImageProcessingOptions type — that's the Android API).
        let result: ImageClassifierResult
        if let roi = roi {
            result = try classifier.classify(image: mpImage, regionOfInterest: roi)
        } else {
            result = try classifier.classify(image: mpImage)
        }

        let score = result.classificationResult.classifications.first?
            .categories.first?.score
        // No category above threshold → treat as "not sunglasses" (0), not an error.
        return Double(score ?? 0)
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
