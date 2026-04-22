package com.example.face_liveness_demo.mediapipe

import android.content.Context
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.objectdetector.ObjectDetector
import com.google.mediapipe.tasks.vision.objectdetector.ObjectDetectorResult

/**
 * Wraps MediaPipe Tasks [ObjectDetector].
 *
 * Model file must be bundled at `android/app/src/main/assets/efficientdet_lite0.tflite`.
 */
class ObjectAnalyzerBridge(context: Context) {
    private val detector: ObjectDetector

    init {
        val options = ObjectDetector.ObjectDetectorOptions.builder()
            .setBaseOptions(
                BaseOptions.builder()
                    .setModelAssetPath(MODEL_ASSET_PATH)
                    .build(),
            )
            .setRunningMode(RunningMode.IMAGE)
            .setMaxResults(MAX_RESULTS)
            .setScoreThreshold(SCORE_THRESHOLD)
            .build()
        detector = ObjectDetector.createFromOptions(context, options)
    }

    fun detect(frame: FrameArgs): List<Map<String, Any>> {
        val bitmap = FrameDecoder.decodeUprightBitmap(frame) ?: return emptyList()
        val mpImage = BitmapImageBuilder(bitmap).build()
        val result: ObjectDetectorResult = detector.detect(mpImage)

        val out = mutableListOf<Map<String, Any>>()
        for (detection in result.detections()) {
            val box = detection.boundingBox() ?: continue
            val category = detection.categories().firstOrNull()
            out += mapOf(
                "label" to (category?.categoryName() ?: "unknown"),
                "confidence" to (category?.score()?.toDouble() ?: 0.0),
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
        private const val MODEL_ASSET_PATH = "efficientdet_lite0.tflite"
        private const val MAX_RESULTS = 5
        private const val SCORE_THRESHOLD = 0.5f
    }
}
