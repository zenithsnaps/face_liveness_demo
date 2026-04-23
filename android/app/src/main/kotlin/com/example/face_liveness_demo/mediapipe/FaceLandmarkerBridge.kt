package com.example.face_liveness_demo.mediapipe

import android.content.Context

// FaceLandmarker temporarily disabled — stub always returns no face found.
class FaceLandmarkerBridge(@Suppress("UNUSED_PARAMETER") context: Context) {

    fun detect(@Suppress("UNUSED_PARAMETER") frame: FrameArgs): Map<String, Any> =
        mapOf("found" to false, "landmarks" to emptyList<Any>())

    fun close() {}
}
