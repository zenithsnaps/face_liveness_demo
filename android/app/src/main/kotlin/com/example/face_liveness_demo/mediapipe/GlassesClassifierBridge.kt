package com.example.face_liveness_demo.mediapipe

import android.content.Context
import android.graphics.RectF
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.ImageProcessingOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.imageclassifier.ImageClassifier

/**
 * Wraps MediaPipe Tasks [ImageClassifier] for the sunglasses model.
 *
 * Runs on MediaPipe's OWN embedded TFLite — the same runtime hand/object/face
 * use — so there is no second TFLite dependency to manage.
 *
 * The model must be the MediaPipe-shaped export (see
 * `tools/glasses_export/export_onnx_mediapipe.py`): NHWC, with `/255` +
 * ImageNet normalization in NormalizationOptions metadata and a 1-label map
 * `["sunglasses"]`. The single category's score is `P(sunglasses)`.
 *
 * Model file must be bundled at
 * `android/app/src/main/assets/glasses_sunglasses.tflite`.
 */
class GlassesClassifierBridge(context: Context) {
    private val classifier: ImageClassifier

    init {
        val options = ImageClassifier.ImageClassifierOptions.builder()
            .setBaseOptions(
                BaseOptions.builder()
                    .setModelAssetPath(MODEL_ASSET_PATH)
                    .build(),
            )
            .setRunningMode(RunningMode.IMAGE)
            .setMaxResults(MAX_RESULTS)
            .build()
        classifier = ImageClassifier.createFromOptions(context, options)
    }

    /**
     * Returns `P(sunglasses)` in `[0, 1]`, or `null` when the frame can't be
     * decoded. [roi] (when non-null) is the face box in NORMALIZED `[0,1]`
     * coordinates of the upright frame; MediaPipe crops + resizes + normalizes.
     */
    fun classify(frame: FrameArgs, roi: RectF?): Double? {
        val bitmap = FrameDecoder.decodeUprightBitmap(frame) ?: return null
        val mpImage = BitmapImageBuilder(bitmap).build()

        val result = if (roi != null) {
            val ipo = ImageProcessingOptions.builder()
                .setRegionOfInterest(roi)
                .build()
            classifier.classify(mpImage, ipo)
        } else {
            classifier.classify(mpImage)
        }

        // No category above threshold → treat as "not sunglasses" (0).
        val score = result.classificationResult()
            .classifications().firstOrNull()
            ?.categories()?.firstOrNull()
            ?.score()
        return (score ?: 0f).toDouble()
    }

    fun close() {
        try {
            classifier.close()
        } catch (_: Throwable) {
        }
    }

    companion object {
        private const val MODEL_ASSET_PATH = "glasses_sunglasses.tflite"
        private const val MAX_RESULTS = 1
    }
}
