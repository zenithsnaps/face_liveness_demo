package com.example.face_liveness_demo.mediapipe

import android.graphics.Bitmap
import java.io.File
import java.io.FileOutputStream

/**
 * Encodes a [FrameArgs] payload as an upright JPEG written to [outPath].
 *
 * Reuses [FrameDecoder.decodeUprightBitmap] (NV21 / YUV / BGRA / RGBA → upright RGB
 * Bitmap) and pipes the result through [Bitmap.compress] at the given quality.
 *
 * Returns the absolute path on success, or null if decode/compression failed.
 */
object JpegEncoderBridge {
    fun encode(frame: FrameArgs, quality: Int, outPath: String): String? {
        val bitmap = FrameDecoder.decodeUprightBitmap(frame) ?: return null
        try {
            FileOutputStream(File(outPath)).use { fos ->
                if (!bitmap.compress(Bitmap.CompressFormat.JPEG, quality, fos)) {
                    return null
                }
                fos.flush()
            }
        } finally {
            bitmap.recycle()
        }
        return outPath
    }
}
