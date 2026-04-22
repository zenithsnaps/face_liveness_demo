package com.example.face_liveness_demo.mediapipe

import android.content.Context
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facedetector.FaceDetector
import com.google.mediapipe.tasks.vision.facedetector.FaceDetectorResult

/**
 * Wraps MediaPipe Tasks [FaceDetector].
 *
 * Model file must be bundled at `android/app/src/main/assets/blaze_face_short_range.tflite`.
 * Returns [{confidence, bbox: {left, top, width, height}}] per detected face.
 */
class FaceDetectorBridge(context: Context) {
    private val detector: FaceDetector

    init {
        val options = FaceDetector.FaceDetectorOptions.builder()
            .setBaseOptions(
                BaseOptions.builder()
                    .setModelAssetPath(MODEL_ASSET_PATH)
                    .build(),
            )
            .setRunningMode(RunningMode.IMAGE)
            .setMinDetectionConfidence(MIN_SCORE)
            .build()
        detector = FaceDetector.createFromOptions(context, options)
    }

    fun detect(frame: FrameArgs): List<Map<String, Any>> {
        val bitmap = FrameDecoder.decodeUprightBitmap(frame) ?: return emptyList()
        val mpImage = BitmapImageBuilder(bitmap).build()
        val result: FaceDetectorResult = detector.detect(mpImage)

        val out = mutableListOf<Map<String, Any>>()
        for (detection in result.detections()) {
            val box = detection.boundingBox() ?: continue
            val score = detection.categories().firstOrNull()?.score()?.toDouble() ?: 0.0
            out += mapOf(
                "confidence" to score,
                "bbox" to mapOf(
                    "left" to box.left.toDouble(),
                    "top" to box.top.toDouble(),
                    "width" to box.width().toDouble(),
                    "height" to box.height().toDouble(),
                ),
            )
        }
        return out
    }

    fun close() {
        try {
            detector.close()
        } catch (_: Throwable) {
        }
    }

    companion object {
        private const val MODEL_ASSET_PATH = "blaze_face_short_range.tflite"
        private const val MIN_SCORE = 0.5f
    }
}
