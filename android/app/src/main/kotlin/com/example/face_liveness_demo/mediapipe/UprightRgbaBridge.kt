package com.example.face_liveness_demo.mediapipe

import java.nio.ByteBuffer

/**
 * Decodes a [FrameArgs] payload into upright RGBA8888 bytes plus the upright
 * dimensions. Reused by the Dart side to feed ML Kit / pixel-analysis paths
 * that expect rotation=0 RGBA (the easy path on both ML Kit and our
 * EyeOcclusionUtil pixel logic).
 *
 * Returns null when decode fails (unsupported format / corrupt bytes).
 */
object UprightRgbaBridge {
    data class Result(val bytes: ByteArray, val width: Int, val height: Int)

    fun decode(frame: FrameArgs): Result? {
        val bitmap = FrameDecoder.decodeUprightBitmap(frame) ?: return null
        try {
            val w = bitmap.width
            val h = bitmap.height
            val argb = IntArray(w * h)
            bitmap.getPixels(argb, 0, w, 0, 0, w, h)
            val rgba = ByteArray(w * h * 4)
            var dst = 0
            for (px in argb) {
                rgba[dst] = ((px shr 16) and 0xFF).toByte()      // R
                rgba[dst + 1] = ((px shr 8) and 0xFF).toByte()   // G
                rgba[dst + 2] = (px and 0xFF).toByte()           // B
                rgba[dst + 3] = ((px shr 24) and 0xFF).toByte()  // A
                dst += 4
            }
            return Result(rgba, w, h)
        } finally {
            bitmap.recycle()
        }
    }

    /** Builds a Flutter-compatible map result. */
    fun toMap(result: Result): Map<String, Any> = mapOf(
        "bytes" to result.bytes,
        "width" to result.width,
        "height" to result.height,
    )

    @Suppress("unused")
    private fun discardBuffer(buf: ByteBuffer) {
        // Reserved for future direct-buffer optimisation. No-op for now.
    }
}
