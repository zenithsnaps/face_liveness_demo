package com.example.face_liveness_demo.mediapipe

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import java.io.ByteArrayOutputStream

/**
 * Decodes a [FrameArgs] payload into an upright RGB [Bitmap] suitable for
 * MediaPipe Tasks' `BitmapImageBuilder`.
 *
 * Handles:
 *   - `nv21` / `yuv420` from Android camera plugin
 *   - `bgra8888` from iOS-style frames (not typical on Android but supported)
 *   - rotation applied per [FrameArgs.rotation]
 */
object FrameDecoder {
    fun decodeUprightBitmap(frame: FrameArgs): Bitmap? {
        val decoded = when (frame.format.lowercase()) {
            "nv21", "yuv420" -> decodeNv21(frame)
            "bgra8888" -> decodeBgra(frame)
            "rgba8888" -> decodeRgba(frame)
            else -> null
        } ?: return null
        return if (frame.rotation != 0) rotate(decoded, frame.rotation) else decoded
    }

    private fun decodeNv21(frame: FrameArgs): Bitmap? {
        val yuv = YuvImage(
            frame.bytes,
            ImageFormat.NV21,
            frame.width,
            frame.height,
            null,
        )
        val out = ByteArrayOutputStream()
        if (!yuv.compressToJpeg(Rect(0, 0, frame.width, frame.height), 90, out)) {
            return null
        }
        val jpeg = out.toByteArray()
        return BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)
    }

    private fun decodeBgra(frame: FrameArgs): Bitmap {
        val pixels = IntArray(frame.width * frame.height)
        var src = 0
        var dst = 0
        val bytes = frame.bytes
        while (dst < pixels.size) {
            val b = bytes[src].toInt() and 0xFF
            val g = bytes[src + 1].toInt() and 0xFF
            val r = bytes[src + 2].toInt() and 0xFF
            val a = bytes[src + 3].toInt() and 0xFF
            pixels[dst] = (a shl 24) or (r shl 16) or (g shl 8) or b
            src += 4
            dst++
        }
        return Bitmap.createBitmap(pixels, frame.width, frame.height, Bitmap.Config.ARGB_8888)
    }

    private fun decodeRgba(frame: FrameArgs): Bitmap {
        val pixels = IntArray(frame.width * frame.height)
        var src = 0
        var dst = 0
        val bytes = frame.bytes
        while (dst < pixels.size) {
            val r = bytes[src].toInt() and 0xFF
            val g = bytes[src + 1].toInt() and 0xFF
            val b = bytes[src + 2].toInt() and 0xFF
            val a = bytes[src + 3].toInt() and 0xFF
            pixels[dst] = (a shl 24) or (r shl 16) or (g shl 8) or b
            src += 4
            dst++
        }
        return Bitmap.createBitmap(pixels, frame.width, frame.height, Bitmap.Config.ARGB_8888)
    }

    private fun rotate(src: Bitmap, degrees: Int): Bitmap {
        val matrix = Matrix().apply { postRotate(degrees.toFloat()) }
        return Bitmap.createBitmap(src, 0, 0, src.width, src.height, matrix, true)
    }
}
