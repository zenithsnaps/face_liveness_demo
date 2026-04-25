// EyeOcclusionUtil.swift
//
// Detects dark glasses / eye-covering objects via pixel-level analysis.
//
// Input  : RGBA8888 byte buffer (already rotated upright) + eye contour points
//          from Vision / ML Kit + optional cheek landmarks + face bounding box.
// Output : EyeOcclusionEvidence — per-eye scores, combined score, pass/fail.
//
// Three signals, each scored 0 (pass) → 1 (block) with linear interpolation:
//   1. Lum Ratio   eyeLum / cheekLum         pass ≥ 0.55 / block ≤ 0.35
//   2. StdDev      luminance σ inside eye     pass ≥ 15   / block ≤ 8
//   3. Saturation  mean max(R,G,B)−min(R,G,B) pass ≥ 20   / block ≤ 12
//
// Combined score = mean(s1, s2, s3) per eye.
// Final score    = max(leftScore, rightScore). Blocked when ≥ blockScore (0.5).

import UIKit
import MLKitFaceDetection

// MARK: - Supporting types

struct OcclusionPoint {
    let x: Double
    let y: Double
}

struct OcclusionRect {
    let left: Double
    let top: Double
    let width: Double
    let height: Double

    var right: Double { left + width }
    var bottom: Double { top + height }
}

// MARK: - Thresholds

struct EyeOcclusionThresholds {
    // Signal 1 — luminance ratio (eye / cheek)
    var lumRatioPass: Double = 0.55
    var lumRatioBlock: Double = 0.35

    // Signal 2 — luminance std-dev inside eye region
    var stdDevPass: Double = 15.0
    var stdDevBlock: Double = 8.0

    // Signal 3 — mean per-pixel colour range max(R,G,B) − min(R,G,B)
    var saturationPass: Double = 20.0
    var saturationBlock: Double = 12.0

    // Combined score threshold: blocked when combinedScore ≥ blockScore
    var blockScore: Double = 0.5

    static let defaults = EyeOcclusionThresholds()
}

// MARK: - Result

struct EyeOcclusionEvidence {
    /// Mean luminance of the cheek reference patch (0–255).
    let referenceLuminance: Double

    /// Eye luminance / cheek luminance (lower = darker than skin).
    let leftLumRatio: Double
    let rightLumRatio: Double

    /// Luminance std-dev inside the eye region (lower = more uniform / lens-like).
    let leftStdDev: Double
    let rightStdDev: Double

    /// Mean per-pixel colour range (lower = more grey / desaturated).
    let leftSaturation: Double
    let rightSaturation: Double

    /// Per-eye combined score (0 = clearly open, 1 = clearly occluded).
    let leftScore: Double
    let rightScore: Double

    /// max(leftScore, rightScore) — worst-eye decision value.
    let combinedScore: Double

    /// True when combinedScore ≥ EyeOcclusionThresholds.blockScore.
    let occluded: Bool
}

// MARK: - Utility

enum EyeOcclusionUtil {

    // MARK: - UIImage + ML Kit Face entry point

    /// Analyse a UIImage for eye occlusion using an ML Kit `Face` object.
    ///
    /// Extracts eye contours (`leftEye`, `rightEye`) and cheek landmarks from
    /// the `Face` internally — no manual contour mapping needed at the call site.
    ///
    /// Requirements:
    /// - ML Kit face detector must be configured with `contourMode: .all` and
    ///   `landmarkMode: .all` so that eye contours and cheek landmarks are present.
    /// - UIImage orientation must already be applied (visually upright) since
    ///   ML Kit point coordinates are relative to the rendered image dimensions.
    ///
    /// Returns `nil` only if pixel extraction from the UIImage fails (e.g. no
    /// backing CGImage).
    ///
    /// Example:
    /// ```swift
    /// let result = EyeOcclusionUtil.detect(
    ///     image: capturedImage,
    ///     face:  mlKitFaces.first!
    /// )
    /// if result?.occluded == true { /* reject */ }
    /// ```
    static func detect(
        image:      UIImage,
        face:       Face,
        thresholds: EyeOcclusionThresholds = .defaults
    ) -> EyeOcclusionEvidence? {
        guard let (pixels, w, h) = toRGBA8888(image) else { return nil }

        let leftEye  = points(from: face.contour(ofType: .leftEye))
        let rightEye = points(from: face.contour(ofType: .rightEye))
        let leftCheek  = point(from: face.landmark(ofType: .leftCheek))
        let rightCheek = point(from: face.landmark(ofType: .rightCheek))
        let faceBox = OcclusionRect(
            left:   Double(face.frame.minX), top:    Double(face.frame.minY),
            width:  Double(face.frame.width), height: Double(face.frame.height)
        )

        return pixels.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return nil }
            return detect(
                rgba:       base,
                width:      w,
                height:     h,
                leftEye:    leftEye,
                rightEye:   rightEye,
                leftCheek:  leftCheek,
                rightCheek: rightCheek,
                faceBox:    faceBox,
                thresholds: thresholds
            )
        }
    }

    // MARK: - ML Kit extraction helpers

    private static func points(from contour: FaceContour?) -> [OcclusionPoint] {
        (contour?.points ?? []).map { OcclusionPoint(x: Double($0.x), y: Double($0.y)) }
    }

    private static func point(from landmark: FaceLandmark?) -> OcclusionPoint? {
        guard let lm = landmark else { return nil }
        return OcclusionPoint(x: Double(lm.position.x), y: Double(lm.position.y))
    }

    // MARK: - Raw pixel entry point

    /// Analyse a single captured frame for eye occlusion.
    ///
    /// - Parameters:
    ///   - rgba:        RGBA8888 pixel buffer, row-major, already upright.
    ///   - width:       Frame width in pixels.
    ///   - height:      Frame height in pixels.
    ///   - leftEye:     Contour points of the left eye (image-pixel coordinates).
    ///   - rightEye:    Contour points of the right eye.
    ///   - leftCheek:   Optional left-cheek landmark for reference luminance.
    ///   - rightCheek:  Optional right-cheek landmark for reference luminance.
    ///   - faceBox:     Face bounding box (used to size reference patches).
    ///   - thresholds:  Override signal thresholds. Defaults to standard values.
    static func detect(
        rgba: UnsafePointer<UInt8>,
        width: Int,
        height: Int,
        leftEye: [OcclusionPoint],
        rightEye: [OcclusionPoint],
        leftCheek: OcclusionPoint? = nil,
        rightCheek: OcclusionPoint? = nil,
        faceBox: OcclusionRect,
        thresholds: EyeOcclusionThresholds = .defaults
    ) -> EyeOcclusionEvidence {

        let refLum = referenceLuminance(
            rgba: rgba, w: width, h: height,
            leftEye: leftEye, rightEye: rightEye,
            leftCheek: leftCheek, rightCheek: rightCheek,
            faceBox: faceBox
        )

        let leftStats  = eyeStats(rgba: rgba, w: width, h: height, contour: leftEye)
        let rightStats = eyeStats(rgba: rgba, w: width, h: height, contour: rightEye)

        let leftRatio  = refLum > 0 ? leftStats.lumMean  / refLum : 1.0
        let rightRatio = refLum > 0 ? rightStats.lumMean / refLum : 1.0

        let leftScore  = combinedScore(lumRatio: leftRatio,  stdDev: leftStats.stdDev,  saturation: leftStats.saturation,  t: thresholds)
        let rightScore = combinedScore(lumRatio: rightRatio, stdDev: rightStats.stdDev, saturation: rightStats.saturation, t: thresholds)
        let combined   = max(leftScore, rightScore)

        return EyeOcclusionEvidence(
            referenceLuminance: refLum,
            leftLumRatio:  leftRatio,         rightLumRatio:  rightRatio,
            leftStdDev:    leftStats.stdDev,  rightStdDev:    rightStats.stdDev,
            leftSaturation: leftStats.saturation, rightSaturation: rightStats.saturation,
            leftScore:  leftScore,            rightScore:  rightScore,
            combinedScore: combined,
            occluded: combined >= thresholds.blockScore
        )
    }

    // MARK: - Private helpers

    /// Render UIImage into a flat RGBA8888 byte array via CGContext.
    /// Returns nil if the UIImage has no CGImage backing (e.g. CIImage-only).
    private static func toRGBA8888(_ image: UIImage) -> (pixels: [UInt8], width: Int, height: Int)? {
        guard let cgImage = image.cgImage else { return nil }
        let width  = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data:              &pixels,
            width:             width,
            height:            height,
            bitsPerComponent:  8,
            bytesPerRow:       width * 4,
            space:             CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:        CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (pixels, width, height)
    }

    private typealias PixelStats = (lumMean: Double, stdDev: Double, saturation: Double)

    private static func combinedScore(
        lumRatio: Double, stdDev: Double, saturation: Double,
        t: EyeOcclusionThresholds
    ) -> Double {
        let s1 = signalScore(value: lumRatio,    pass: t.lumRatioPass,    block: t.lumRatioBlock)
        let s2 = signalScore(value: stdDev,      pass: t.stdDevPass,      block: t.stdDevBlock)
        let s3 = signalScore(value: saturation,  pass: t.saturationPass,  block: t.saturationBlock)
        return (s1 + s2 + s3) / 3.0
    }

    /// Linear 0 (pass) → 1 (block). Higher value = better for all three signals.
    private static func signalScore(value: Double, pass passThreshold: Double, block blockThreshold: Double) -> Double {
        if value >= passThreshold { return 0.0 }
        if value <= blockThreshold { return 1.0 }
        return (passThreshold - value) / (passThreshold - blockThreshold)
    }

    private static func eyeStats(rgba: UnsafePointer<UInt8>, w: Int, h: Int, contour: [OcclusionPoint]) -> PixelStats {
        guard !contour.isEmpty else { return (128.0, 20.0, 30.0) }
        let box    = bbox(pts: contour)
        let region = inset(r: box, factor: 0.15)  // 15% inset each side — stays inside lens
        return sampleRegion(rgba: rgba, imgW: w, imgH: h, rect: region)
    }

    private static func referenceLuminance(
        rgba: UnsafePointer<UInt8>, w: Int, h: Int,
        leftEye: [OcclusionPoint], rightEye: [OcclusionPoint],
        leftCheek: OcclusionPoint?, rightCheek: OcclusionPoint?,
        faceBox: OcclusionRect
    ) -> Double {
        let patchSize = faceBox.width * 0.08  // 8% of face width
        var lumValues: [Double] = []

        for cheek in [leftCheek, rightCheek] {
            guard let cheek = cheek else { continue }
            let rect = OcclusionRect(
                left: cheek.x - patchSize / 2,
                top:  cheek.y - patchSize / 2,
                width: patchSize, height: patchSize
            )
            lumValues.append(sampleRegion(rgba: rgba, imgW: w, imgH: h, rect: rect).lumMean)
        }

        if lumValues.isEmpty {
            // Fallback: strip just below each eye bbox
            let fallbackH = faceBox.height * 0.10
            for contour in [leftEye, rightEye] {
                guard !contour.isEmpty else { continue }
                let eyeBox = bbox(pts: contour)
                let rect = OcclusionRect(
                    left: eyeBox.left, top: eyeBox.bottom + 4,
                    width: eyeBox.width, height: fallbackH
                )
                lumValues.append(sampleRegion(rgba: rgba, imgW: w, imgH: h, rect: rect).lumMean)
            }
        }

        if lumValues.isEmpty { return 180.0 }
        return lumValues.reduce(0, +) / Double(lumValues.count)
    }

    private static func bbox(pts: [OcclusionPoint]) -> OcclusionRect {
        var minX = Double.infinity,  minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for p in pts {
            if p.x < minX { minX = p.x }
            if p.y < minY { minY = p.y }
            if p.x > maxX { maxX = p.x }
            if p.y > maxY { maxY = p.y }
        }
        return OcclusionRect(left: minX, top: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func inset(r: OcclusionRect, factor: Double) -> OcclusionRect {
        let dx = r.width  * factor
        let dy = r.height * factor
        return OcclusionRect(left: r.left + dx, top: r.top + dy, width: r.width - 2 * dx, height: r.height - 2 * dy)
    }

    /// Sample RGBA8888 pixels in [rect] at stride-2 (every other row and column).
    /// Returns per-pixel luminance mean, std-dev, and colour range (saturation proxy).
    private static func sampleRegion(rgba: UnsafePointer<UInt8>, imgW: Int, imgH: Int, rect: OcclusionRect) -> PixelStats {
        let left   = max(0, min(Int(rect.left.rounded()),  imgW - 1))
        let top    = max(0, min(Int(rect.top.rounded()),   imgH - 1))
        let right  = max(0, min(Int(rect.right.rounded()), imgW))
        let bottom = max(0, min(Int(rect.bottom.rounded()), imgH))

        guard left < right, top < bottom else { return (128.0, 20.0, 30.0) }

        var sumY = 0.0, sumY2 = 0.0, sumSat = 0.0
        var count = 0

        var y = top
        while y < bottom {
            var x = left
            while x < right {
                let i = 4 * (y * imgW + x)
                let r = Double(rgba[i])
                let g = Double(rgba[i + 1])
                let b = Double(rgba[i + 2])
                let lum = 0.299 * r + 0.587 * g + 0.114 * b  // BT.601
                let mx  = max(r, max(g, b))
                let mn  = min(r, min(g, b))
                sumY   += lum
                sumY2  += lum * lum
                sumSat += mx - mn
                count  += 1
                x += 2
            }
            y += 2
        }

        guard count > 0 else { return (128.0, 20.0, 30.0) }

        let mean     = sumY / Double(count)
        let variance = max(0.0, (sumY2 / Double(count)) - mean * mean)
        return (mean, variance.squareRoot(), sumSat / Double(count))
    }
}
