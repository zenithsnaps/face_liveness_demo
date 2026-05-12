# `isWearingSunglasses` — Fixed to Match App Logic

## Prerequisites

ML Kit face detector ต้อง configure ด้วย:

```swift
let options = FaceDetectorOptions()
options.contourMode  = .all   // ต้องเปิดเพื่อให้ได้ eye contour points
options.landmarkMode = .all   // ต้องเปิดเพื่อให้ได้ cheek landmarks
```

## Changes from Original

| Item | Before | After |
|------|--------|-------|
| Eye ROI | Hardcoded proportion จาก face bbox | ML Kit eye contour → bbox → inset 15% |
| Cheek reference | Hardcoded proportion จาก face bbox | ML Kit cheek landmarks → 8% patch, fallback strip below eye, fallback 180.0 |
| Saturation formula | HSV: `((max-min)/max)*255` | Color range: `max-min` |
| Scoring | Binary step + weighted sum | Linear interpolation + equal weight (1/3) |
| Per-eye | รวมตาทั้งสองข้าง | แยก score แต่ละตา → `max(left, right)` |
| Decision threshold | `>= 0.30` | `>= 0.50` |
| Pixel stride | Every pixel | Every other pixel (stride 2) |

## Code

```swift
private func isWearingSunglasses(
    image: UIImage,
    face: MLKit.Face,
    mlKitFrameIsMirrored: Bool = true
) -> Bool {
    guard let cgImage = image.cgImage else {
        return false
    }

    let imageWidth = cgImage.width
    let imageHeight = cgImage.height

    // MARK: - Extract contours & landmarks from ML Kit Face

    func mirrorX(_ x: CGFloat) -> CGFloat {
        mlKitFrameIsMirrored ? CGFloat(imageWidth) - x : x
    }

    func extractContour(_ type: FaceContourType) -> [CGPoint] {
        guard let contour = face.contour(ofType: type) else { return [] }
        return contour.points.map {
            CGPoint(x: mirrorX(CGFloat($0.x)), y: CGFloat($0.y))
        }
    }

    func extractLandmark(_ type: FaceLandmarkType) -> CGPoint? {
        guard let lm = face.landmark(ofType: type) else { return nil }
        return CGPoint(x: mirrorX(CGFloat(lm.position.x)), y: CGFloat(lm.position.y))
    }

    let leftEye = extractContour(.leftEye)
    let rightEye = extractContour(.rightEye)
    let leftCheek = extractLandmark(.leftCheek)
    let rightCheek = extractLandmark(.rightCheek)

    var faceRect = face.frame
    if mlKitFrameIsMirrored {
        faceRect.origin.x = CGFloat(imageWidth) - faceRect.maxX
    }

    // MARK: - Render to RGBA8888

    let bytesPerPixel = 4
    let bytesPerRow = imageWidth * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: imageHeight * bytesPerRow)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    let didDraw = pixels.withUnsafeMutableBytes { buf -> Bool in
        guard let ctx = CGContext(
            data: buf.baseAddress,
            width: imageWidth,
            height: imageHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return false }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        return true
    }

    guard didDraw else { return false }

    // MARK: - Pixel helpers

    typealias PixelStats = (lumMean: Double, stdDev: Double, saturation: Double)

    let defaultStats: PixelStats = (128.0, 20.0, 30.0)

    func bbox(of pts: [CGPoint]) -> CGRect {
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for p in pts {
            if p.x < minX { minX = p.x }
            if p.y < minY { minY = p.y }
            if p.x > maxX { maxX = p.x }
            if p.y > maxY { maxY = p.y }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func insetRect(_ rect: CGRect, factor: CGFloat) -> CGRect {
        let dx = rect.width * factor
        let dy = rect.height * factor
        return CGRect(
            x: rect.minX + dx, y: rect.minY + dy,
            width: rect.width - 2 * dx, height: rect.height - 2 * dy
        )
    }

    func sampleRegion(_ rect: CGRect) -> PixelStats {
        let left   = max(0, min(Int(rect.minX.rounded()), imageWidth - 1))
        let top    = max(0, min(Int(rect.minY.rounded()), imageHeight - 1))
        let right  = max(0, min(Int(rect.maxX.rounded()), imageWidth))
        let bottom = max(0, min(Int(rect.maxY.rounded()), imageHeight))

        guard left < right, top < bottom else { return defaultStats }

        var sumY: Double = 0, sumY2: Double = 0, sumSat: Double = 0
        var count = 0

        var y = top
        while y < bottom {
            var x = left
            while x < right {
                let i = 4 * (y * imageWidth + x)
                let r = Double(pixels[i])
                let g = Double(pixels[i + 1])
                let b = Double(pixels[i + 2])

                let lum = 0.299 * r + 0.587 * g + 0.114 * b
                let mx  = max(r, max(g, b))
                let mn  = min(r, min(g, b))

                sumY   += lum
                sumY2  += lum * lum
                sumSat += mx - mn        // color range, NOT HSV saturation
                count  += 1
                x += 2                   // stride 2
            }
            y += 2                       // stride 2
        }

        guard count > 0 else { return defaultStats }

        let mean = sumY / Double(count)
        let variance = max(0.0, (sumY2 / Double(count)) - mean * mean)
        return (mean, sqrt(variance), sumSat / Double(count))
    }

    func eyeStats(contour: [CGPoint]) -> PixelStats {
        guard !contour.isEmpty else { return defaultStats }
        let region = insetRect(bbox(of: contour), factor: 0.15)
        return sampleRegion(region)
    }

    // MARK: - Reference luminance (cheek → fallback below-eye → 180)

    func referenceLuminance() -> Double {
        let patchSize = faceRect.width * 0.08
        var lumValues: [Double] = []

        for cheek in [leftCheek, rightCheek] {
            guard let cheek = cheek else { continue }
            let rect = CGRect(
                x: cheek.x - patchSize / 2,
                y: cheek.y - patchSize / 2,
                width: patchSize,
                height: patchSize
            )
            lumValues.append(sampleRegion(rect).lumMean)
        }

        if lumValues.isEmpty {
            let fallbackH = faceRect.height * 0.10
            for contour in [leftEye, rightEye] {
                guard !contour.isEmpty else { continue }
                let eyeBox = bbox(of: contour)
                let rect = CGRect(
                    x: eyeBox.minX,
                    y: eyeBox.maxY + 4,
                    width: eyeBox.width,
                    height: fallbackH
                )
                lumValues.append(sampleRegion(rect).lumMean)
            }
        }

        if lumValues.isEmpty { return 180.0 }
        return lumValues.reduce(0, +) / Double(lumValues.count)
    }

    // MARK: - Linear signal scoring: 0 (pass) → 1 (block)

    func signalScore(value: Double, pass p: Double, block b: Double) -> Double {
        if value >= p { return 0.0 }
        if value <= b { return 1.0 }
        return (p - value) / (p - b)
    }

    // MARK: - Thresholds

    let lumRatioPass   = 0.55
    let lumRatioBlock  = 0.35
    let stdDevPass     = 15.0
    let stdDevBlock    = 8.0
    let saturationPass = 20.0
    let saturationBlock = 12.0
    let blockScore     = 0.50

    // MARK: - Score per eye, worst-eye decision

    func combinedScore(lumRatio: Double, stdDev: Double, saturation: Double) -> Double {
        let s1 = signalScore(value: lumRatio,   pass: lumRatioPass,   block: lumRatioBlock)
        let s2 = signalScore(value: stdDev,     pass: stdDevPass,     block: stdDevBlock)
        let s3 = signalScore(value: saturation, pass: saturationPass, block: saturationBlock)
        return (s1 + s2 + s3) / 3.0
    }

    let refLum     = referenceLuminance()
    let leftStats  = eyeStats(contour: leftEye)
    let rightStats = eyeStats(contour: rightEye)

    let leftRatio  = refLum > 0 ? leftStats.lumMean  / refLum : 1.0
    let rightRatio = refLum > 0 ? rightStats.lumMean / refLum : 1.0

    let leftScore  = combinedScore(lumRatio: leftRatio,  stdDev: leftStats.stdDev,  saturation: leftStats.saturation)
    let rightScore = combinedScore(lumRatio: rightRatio, stdDev: rightStats.stdDev, saturation: rightStats.saturation)
    let finalScore = max(leftScore, rightScore)

    return finalScore >= blockScore
}
```
