// EyeOcclusionUtil.kt
//
// Detects dark glasses / eye-covering objects via pixel-level analysis.
//
// Input  : RGBA8888 byte buffer (already rotated upright) + eye contour points
//          from ML Kit face detection + optional cheek landmarks + face bounding box.
// Output : EyeOcclusionEvidence — per-eye scores, combined score, pass/fail.
//
// Three signals, each scored 0 (pass) → 1 (block) with linear interpolation:
//   1. Lum Ratio   eyeLum / cheekLum         pass ≥ 0.55 / block ≤ 0.35
//   2. StdDev      luminance σ inside eye     pass ≥ 15   / block ≤ 8
//   3. Saturation  mean max(R,G,B)−min(R,G,B) pass ≥ 20   / block ≤ 12
//
// Combined score = mean(s1, s2, s3) per eye.
// Final score    = max(leftScore, rightScore). Blocked when ≥ blockScore (0.5).

// TODO: เปลี่ยน package ให้ตรงกับ project ที่นำไปใช้
package com.your.package.name

import kotlin.math.*

// ─── Supporting types ─────────────────────────────────────────────────────────

data class OcclusionPoint(val x: Double, val y: Double)

data class OcclusionRect(val left: Double, val top: Double, val width: Double, val height: Double) {
    val right  get() = left + width
    val bottom get() = top  + height
}

// ─── Thresholds ───────────────────────────────────────────────────────────────

data class EyeOcclusionThresholds(
    // Signal 1 — luminance ratio (eye / cheek)
    val lumRatioPass:    Double = 0.55,
    val lumRatioBlock:   Double = 0.35,

    // Signal 2 — luminance std-dev inside eye region
    val stdDevPass:      Double = 15.0,
    val stdDevBlock:     Double = 8.0,

    // Signal 3 — mean per-pixel colour range max(R,G,B) − min(R,G,B)
    val saturationPass:  Double = 20.0,
    val saturationBlock: Double = 12.0,

    // Combined score threshold: blocked when combinedScore ≥ blockScore
    val blockScore:      Double = 0.5
) {
    companion object {
        val defaults = EyeOcclusionThresholds()
    }
}

// ─── Result ───────────────────────────────────────────────────────────────────

data class EyeOcclusionEvidence(
    /** Mean luminance of the cheek reference patch (0–255). */
    val referenceLuminance: Double,

    /** Eye luminance / cheek luminance (lower = darker than skin). */
    val leftLumRatio:  Double,
    val rightLumRatio: Double,

    /** Luminance std-dev inside eye region (lower = more uniform / lens-like). */
    val leftStdDev:  Double,
    val rightStdDev: Double,

    /** Mean per-pixel colour range (lower = more grey / desaturated). */
    val leftSaturation:  Double,
    val rightSaturation: Double,

    /** Per-eye combined score (0 = clearly open, 1 = clearly occluded). */
    val leftScore:  Double,
    val rightScore: Double,

    /** max(leftScore, rightScore) — worst-eye decision value. */
    val combinedScore: Double,

    /** True when combinedScore ≥ EyeOcclusionThresholds.blockScore. */
    val occluded: Boolean
)

// ─── Utility ──────────────────────────────────────────────────────────────────

object EyeOcclusionUtil {

    /**
     * Analyse a single captured frame for eye occlusion.
     *
     * @param rgba       RGBA8888 pixel buffer, row-major, already upright.
     *                   ByteArray stores signed bytes; values are read as
     *                   unsigned via `toInt() and 0xFF`.
     * @param width      Frame width in pixels.
     * @param height     Frame height in pixels.
     * @param leftEye    Contour points of the left eye (image-pixel coordinates).
     * @param rightEye   Contour points of the right eye.
     * @param leftCheek  Optional left-cheek landmark for reference luminance.
     * @param rightCheek Optional right-cheek landmark for reference luminance.
     * @param faceBox    Face bounding box (used to size reference patches).
     * @param thresholds Override signal thresholds. Defaults to standard values.
     */
    fun detect(
        rgba:        ByteArray,
        width:       Int,
        height:      Int,
        leftEye:     List<OcclusionPoint>,
        rightEye:    List<OcclusionPoint>,
        leftCheek:   OcclusionPoint? = null,
        rightCheek:  OcclusionPoint? = null,
        faceBox:     OcclusionRect,
        thresholds:  EyeOcclusionThresholds = EyeOcclusionThresholds.defaults
    ): EyeOcclusionEvidence {

        val refLum     = referenceLuminance(rgba, width, height, leftEye, rightEye, leftCheek, rightCheek, faceBox)
        val leftStats  = eyeStats(rgba, width, height, leftEye)
        val rightStats = eyeStats(rgba, width, height, rightEye)

        val leftRatio  = if (refLum > 0) leftStats.lumMean  / refLum else 1.0
        val rightRatio = if (refLum > 0) rightStats.lumMean / refLum else 1.0

        val leftScore  = combinedScore(leftRatio,  leftStats.stdDev,  leftStats.saturation,  thresholds)
        val rightScore = combinedScore(rightRatio, rightStats.stdDev, rightStats.saturation, thresholds)
        val combined   = max(leftScore, rightScore)

        return EyeOcclusionEvidence(
            referenceLuminance = refLum,
            leftLumRatio  = leftRatio,         rightLumRatio  = rightRatio,
            leftStdDev    = leftStats.stdDev,  rightStdDev    = rightStats.stdDev,
            leftSaturation  = leftStats.saturation, rightSaturation  = rightStats.saturation,
            leftScore  = leftScore,            rightScore  = rightScore,
            combinedScore = combined,
            occluded = combined >= thresholds.blockScore
        )
    }

    // ─── Private helpers ──────────────────────────────────────────────────────

    private data class PixelStats(val lumMean: Double, val stdDev: Double, val saturation: Double)

    private val fallbackStats = PixelStats(128.0, 20.0, 30.0)

    private fun combinedScore(
        lumRatio: Double, stdDev: Double, saturation: Double,
        t: EyeOcclusionThresholds
    ): Double {
        val s1 = signalScore(lumRatio,   t.lumRatioPass,   t.lumRatioBlock)
        val s2 = signalScore(stdDev,     t.stdDevPass,     t.stdDevBlock)
        val s3 = signalScore(saturation, t.saturationPass, t.saturationBlock)
        return (s1 + s2 + s3) / 3.0
    }

    /** Linear 0 (pass) → 1 (block). Higher value = better for all three signals. */
    private fun signalScore(value: Double, passThreshold: Double, blockThreshold: Double): Double {
        if (value >= passThreshold) return 0.0
        if (value <= blockThreshold) return 1.0
        return (passThreshold - value) / (passThreshold - blockThreshold)
    }

    private fun eyeStats(rgba: ByteArray, w: Int, h: Int, contour: List<OcclusionPoint>): PixelStats {
        if (contour.isEmpty) return fallbackStats
        val box    = bbox(contour)
        val region = inset(box, 0.15)  // 15% inset each side — stays inside lens
        return sampleRegion(rgba, w, h, region)
    }

    private fun referenceLuminance(
        rgba: ByteArray, w: Int, h: Int,
        leftEye: List<OcclusionPoint>, rightEye: List<OcclusionPoint>,
        leftCheek: OcclusionPoint?, rightCheek: OcclusionPoint?,
        faceBox: OcclusionRect
    ): Double {
        val patchSize  = faceBox.width * 0.08  // 8% of face width
        val lumValues  = mutableListOf<Double>()

        for (cheek in listOf(leftCheek, rightCheek)) {
            if (cheek == null) continue
            val rect = OcclusionRect(
                left   = cheek.x - patchSize / 2,
                top    = cheek.y - patchSize / 2,
                width  = patchSize,
                height = patchSize
            )
            lumValues.add(sampleRegion(rgba, w, h, rect).lumMean)
        }

        if (lumValues.isEmpty) {
            // Fallback: strip just below each eye bbox
            val fallbackH = faceBox.height * 0.10
            for (contour in listOf(leftEye, rightEye)) {
                if (contour.isEmpty) continue
                val eyeBox = bbox(contour)
                val rect = OcclusionRect(
                    left   = eyeBox.left,
                    top    = eyeBox.bottom + 4.0,
                    width  = eyeBox.width,
                    height = fallbackH
                )
                lumValues.add(sampleRegion(rgba, w, h, rect).lumMean)
            }
        }

        if (lumValues.isEmpty) return 180.0
        return lumValues.sum() / lumValues.size
    }

    private fun bbox(pts: List<OcclusionPoint>): OcclusionRect {
        var minX = Double.MAX_VALUE;  var minY = Double.MAX_VALUE
        var maxX = -Double.MAX_VALUE; var maxY = -Double.MAX_VALUE
        for (p in pts) {
            if (p.x < minX) minX = p.x;  if (p.y < minY) minY = p.y
            if (p.x > maxX) maxX = p.x;  if (p.y > maxY) maxY = p.y
        }
        return OcclusionRect(minX, minY, maxX - minX, maxY - minY)
    }

    private fun inset(r: OcclusionRect, factor: Double): OcclusionRect {
        val dx = r.width  * factor
        val dy = r.height * factor
        return OcclusionRect(r.left + dx, r.top + dy, r.width - 2 * dx, r.height - 2 * dy)
    }

    /**
     * Sample RGBA8888 pixels in [rect] at stride-2 (every other row and column).
     * Returns per-pixel luminance mean, std-dev, and colour range (saturation proxy).
     *
     * Note: ByteArray bytes are signed in Kotlin — convert via `toInt() and 0xFF`.
     */
    private fun sampleRegion(rgba: ByteArray, imgW: Int, imgH: Int, rect: OcclusionRect): PixelStats {
        val left   = rect.left.roundToInt().coerceIn(0, imgW - 1)
        val top    = rect.top.roundToInt().coerceIn(0, imgH - 1)
        val right  = rect.right.roundToInt().coerceIn(0, imgW)
        val bottom = rect.bottom.roundToInt().coerceIn(0, imgH)

        if (left >= right || top >= bottom) return fallbackStats

        var sumY = 0.0; var sumY2 = 0.0; var sumSat = 0.0
        var count = 0

        var y = top
        while (y < bottom) {
            var x = left
            while (x < right) {
                val i = 4 * (y * imgW + x)
                val r = (rgba[i].toInt()     and 0xFF).toDouble()
                val g = (rgba[i + 1].toInt() and 0xFF).toDouble()
                val b = (rgba[i + 2].toInt() and 0xFF).toDouble()
                val lum = 0.299 * r + 0.587 * g + 0.114 * b  // BT.601
                val mx  = max(r, max(g, b))
                val mn  = min(r, min(g, b))
                sumY   += lum
                sumY2  += lum * lum
                sumSat += mx - mn
                count  += 1
                x += 2
            }
            y += 2
        }

        if (count == 0) return fallbackStats

        val mean     = sumY / count
        val variance = max(0.0, (sumY2 / count) - mean * mean)
        return PixelStats(mean, sqrt(variance), sumSat / count)
    }
}

// ─── Extension helpers ────────────────────────────────────────────────────────

private fun Double.roundToInt(): Int = Math.round(this).toInt()
