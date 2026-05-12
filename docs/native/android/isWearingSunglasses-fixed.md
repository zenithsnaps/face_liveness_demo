# `isWearingSunglasses` (Kotlin) — Fixed to Match App Logic

## Prerequisites

ML Kit face detector ต้อง configure ด้วย:

```kotlin
val options = FaceDetectorOptions.Builder()
    .setContourMode(FaceDetectorOptions.CONTOUR_MODE_ALL)
    .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
    .build()
```

## Import

```kotlin
import android.graphics.Bitmap
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceContour
import com.google.mlkit.vision.face.FaceLandmark
import kotlin.math.*
```

## Changes from Original (same as iOS version)

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

```kotlin
fun isWearingSunglasses(
    bitmap: Bitmap,
    face: Face,
    mlKitFrameIsMirrored: Boolean = false
): Boolean {
    val imageWidth = bitmap.width
    val imageHeight = bitmap.height

    // ── Extract contours & landmarks from ML Kit Face ────────────────────

    fun mirrorX(x: Float): Double {
        return if (mlKitFrameIsMirrored) (imageWidth - x).toDouble() else x.toDouble()
    }

    data class Pt(val x: Double, val y: Double)
    data class Rc(val left: Double, val top: Double, val width: Double, val height: Double) {
        val right get() = left + width
        val bottom get() = top + height
    }

    fun extractContour(type: Int): List<Pt> {
        val contour = face.getContour(type) ?: return emptyList()
        return contour.points.map { Pt(mirrorX(it.x), it.y.toDouble()) }
    }

    fun extractLandmark(type: Int): Pt? {
        val lm = face.getLandmark(type) ?: return null
        return Pt(mirrorX(lm.position.x), lm.position.y.toDouble())
    }

    val leftEye = extractContour(FaceContour.LEFT_EYE)
    val rightEye = extractContour(FaceContour.RIGHT_EYE)
    val leftCheek = extractLandmark(FaceLandmark.LEFT_CHEEK)
    val rightCheek = extractLandmark(FaceLandmark.RIGHT_CHEEK)

    val fb = face.boundingBox
    val faceLeft = if (mlKitFrameIsMirrored) (imageWidth - fb.right).toDouble() else fb.left.toDouble()
    val faceBox = Rc(faceLeft, fb.top.toDouble(), fb.width().toDouble(), fb.height().toDouble())

    // ── Read pixels from Bitmap ──────────────────────────────────────────

    val pixels = IntArray(imageWidth * imageHeight)
    bitmap.getPixels(pixels, 0, imageWidth, 0, 0, imageWidth, imageHeight)

    // ── Pixel helpers ────────────────────────────────────────────────────

    data class Stats(val lumMean: Double, val stdDev: Double, val saturation: Double)

    val defaultStats = Stats(128.0, 20.0, 30.0)

    fun bbox(pts: List<Pt>): Rc {
        var minX = Double.MAX_VALUE;  var minY = Double.MAX_VALUE
        var maxX = -Double.MAX_VALUE; var maxY = -Double.MAX_VALUE
        for (p in pts) {
            if (p.x < minX) minX = p.x; if (p.y < minY) minY = p.y
            if (p.x > maxX) maxX = p.x; if (p.y > maxY) maxY = p.y
        }
        return Rc(minX, minY, maxX - minX, maxY - minY)
    }

    fun insetRect(r: Rc, factor: Double): Rc {
        val dx = r.width * factor
        val dy = r.height * factor
        return Rc(r.left + dx, r.top + dy, r.width - 2 * dx, r.height - 2 * dy)
    }

    fun sampleRegion(rect: Rc): Stats {
        val left   = rect.left.roundToInt().coerceIn(0, imageWidth - 1)
        val top    = rect.top.roundToInt().coerceIn(0, imageHeight - 1)
        val right  = rect.right.roundToInt().coerceIn(0, imageWidth)
        val bottom = rect.bottom.roundToInt().coerceIn(0, imageHeight)

        if (left >= right || top >= bottom) return defaultStats

        var sumY = 0.0; var sumY2 = 0.0; var sumSat = 0.0
        var count = 0

        var y = top
        while (y < bottom) {
            var x = left
            while (x < right) {
                val argb = pixels[y * imageWidth + x]
                val r = ((argb shr 16) and 0xFF).toDouble()
                val g = ((argb shr 8) and 0xFF).toDouble()
                val b = (argb and 0xFF).toDouble()

                val lum = 0.299 * r + 0.587 * g + 0.114 * b
                val mx = max(r, max(g, b))
                val mn = min(r, min(g, b))

                sumY += lum
                sumY2 += lum * lum
                sumSat += mx - mn        // color range, NOT HSV saturation
                count += 1
                x += 2                   // stride 2
            }
            y += 2                       // stride 2
        }

        if (count == 0) return defaultStats

        val mean = sumY / count
        val variance = max(0.0, (sumY2 / count) - mean * mean)
        return Stats(mean, sqrt(variance), sumSat / count)
    }

    fun eyeStats(contour: List<Pt>): Stats {
        if (contour.isEmpty()) return defaultStats
        val region = insetRect(bbox(contour), 0.15)
        return sampleRegion(region)
    }

    // ── Reference luminance (cheek → fallback below-eye → 180) ───────────

    fun referenceLuminance(): Double {
        val patchSize = faceBox.width * 0.08
        val lumValues = mutableListOf<Double>()

        for (cheek in listOf(leftCheek, rightCheek)) {
            if (cheek == null) continue
            val rect = Rc(
                cheek.x - patchSize / 2,
                cheek.y - patchSize / 2,
                patchSize,
                patchSize
            )
            lumValues.add(sampleRegion(rect).lumMean)
        }

        if (lumValues.isEmpty()) {
            val fallbackH = faceBox.height * 0.10
            for (contour in listOf(leftEye, rightEye)) {
                if (contour.isEmpty()) continue
                val eyeBox = bbox(contour)
                val rect = Rc(
                    eyeBox.left,
                    eyeBox.bottom + 4.0,
                    eyeBox.width,
                    fallbackH
                )
                lumValues.add(sampleRegion(rect).lumMean)
            }
        }

        if (lumValues.isEmpty()) return 180.0
        return lumValues.sum() / lumValues.size
    }

    // ── Linear signal scoring: 0 (pass) → 1 (block) ─────────────────────

    fun signalScore(value: Double, pass: Double, block: Double): Double {
        if (value >= pass) return 0.0
        if (value <= block) return 1.0
        return (pass - value) / (pass - block)
    }

    // ── Thresholds ───────────────────────────────────────────────────────

    val lumRatioPass = 0.55
    val lumRatioBlock = 0.35
    val stdDevPass = 15.0
    val stdDevBlock = 8.0
    val saturationPass = 20.0
    val saturationBlock = 12.0
    val blockScore = 0.50

    // ── Score per eye, worst-eye decision ────────────────────────────────

    fun combinedScore(lumRatio: Double, stdDev: Double, saturation: Double): Double {
        val s1 = signalScore(lumRatio, lumRatioPass, lumRatioBlock)
        val s2 = signalScore(stdDev, stdDevPass, stdDevBlock)
        val s3 = signalScore(saturation, saturationPass, saturationBlock)
        return (s1 + s2 + s3) / 3.0
    }

    val refLum = referenceLuminance()
    val leftStats = eyeStats(leftEye)
    val rightStats = eyeStats(rightEye)

    val leftRatio = if (refLum > 0) leftStats.lumMean / refLum else 1.0
    val rightRatio = if (refLum > 0) rightStats.lumMean / refLum else 1.0

    val leftScore = combinedScore(leftRatio, leftStats.stdDev, leftStats.saturation)
    val rightScore = combinedScore(rightRatio, rightStats.stdDev, rightStats.saturation)
    val finalScore = max(leftScore, rightScore)

    return finalScore >= blockScore
}

private fun Double.roundToInt(): Int = Math.round(this).toInt()
```
