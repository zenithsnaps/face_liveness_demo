package com.example.face_liveness_demo.mediapipe

import android.content.Context
import android.graphics.Bitmap
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult

/**
 * Wraps MediaPipe Tasks [HandLandmarker] in IMAGE running mode.
 *
 * Model file must be bundled at `android/app/src/main/assets/hand_landmarker.task`.
 */
class HandAnalyzerBridge(context: Context) {
    private val landmarker: HandLandmarker

    init {
        val options = HandLandmarker.HandLandmarkerOptions.builder()
            .setBaseOptions(
                BaseOptions.builder()
                    .setModelAssetPath(MODEL_ASSET_PATH)
                    .build(),
            )
            .setRunningMode(RunningMode.IMAGE)
            .setNumHands(2)
            .setMinHandDetectionConfidence(0.5f)
            .setMinHandPresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .build()
        landmarker = HandLandmarker.createFromOptions(context, options)
    }

    /**
     * Detect hands in [frame] and return a serializable payload:
     *   [ { handedness, confidence, landmarks: [[x_px, y_px], ...] }, ... ]
     *
     * Landmark coordinates are returned in pixels of the rotation-applied
     * upright frame — so the Flutter side does not need to do any rotation math.
     */
    fun detect(frame: FrameArgs): List<Map<String, Any>> {
        val bitmap = FrameDecoder.decodeUprightBitmap(frame) ?: return emptyList()
        val mpImage = BitmapImageBuilder(bitmap).build()
        val result: HandLandmarkerResult = landmarker.detect(mpImage)

        val width = bitmap.width
        val height = bitmap.height
        val hands = mutableListOf<Map<String, Any>>()

        for (i in 0 until result.landmarks().size) {
            val landmarkList = result.landmarks()[i]
            val handednessList = if (i < result.handedness().size) result.handedness()[i] else emptyList()
            val categoryConfidence = handednessList.firstOrNull()?.score()?.toDouble() ?: 0.0
            val categoryLabel = handednessList.firstOrNull()?.categoryName() ?: "Unknown"

            val points = landmarkList.map { lm ->
                listOf(
                    (lm.x() * width).toDouble(),
                    (lm.y() * height).toDouble(),
                )
            }
            hands += mapOf(
                "handedness" to categoryLabel,
                "confidence" to categoryConfidence,
                "landmarks" to points,
            )
        }
        return hands
    }

    fun close() {
        try {
            landmarker.close()
        } catch (_: Throwable) {
        }
    }

    companion object {
        private const val MODEL_ASSET_PATH = "hand_landmarker.task"
    }
}
