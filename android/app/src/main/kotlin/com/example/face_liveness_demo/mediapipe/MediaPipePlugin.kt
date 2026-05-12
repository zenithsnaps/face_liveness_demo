package com.example.face_liveness_demo.mediapipe

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Single MethodChannel handler that bridges Flutter to MediaPipe Tasks
 * (Hand Landmarker + Object Detector + Face Detector + Face Landmarker).
 *
 * Method names (must match infrastructure/platform_channels/mediapipe_channel.dart):
 *   - "initialize"
 *   - "detectHands"
 *   - "detectObjects"
 *   - "detectFaces"
 *   - "detectFaceLandmarks"
 *   - "dispose"
 */
object MediaPipePlugin {
    private const val CHANNEL_NAME = "app.mymo/mediapipe"

    private var channel: MethodChannel? = null
    private var handBridge: HandAnalyzerBridge? = null
    private var objectBridge: ObjectAnalyzerBridge? = null
    private var faceBridge: FaceDetectorBridge? = null
    private var faceLandmarkerBridge: FaceLandmarkerBridge? = null
    private var executor: ExecutorService? = null

    fun register(context: Context, binaryMessenger: BinaryMessenger) {
        if (channel != null) return
        val ch = MethodChannel(binaryMessenger, CHANNEL_NAME)
        channel = ch
        executor = Executors.newSingleThreadExecutor()
        ch.setMethodCallHandler { call, result -> onMethodCall(context, call, result) }
    }

    private fun onMethodCall(context: Context, call: MethodCall, result: MethodChannel.Result) {
        val exec = executor ?: run {
            result.error("NOT_REGISTERED", "Plugin not registered", null)
            return
        }
        exec.execute {
            try {
                when (call.method) {
                    "initialize" -> {
                        if (handBridge == null) handBridge = HandAnalyzerBridge(context)
                        if (objectBridge == null) objectBridge = ObjectAnalyzerBridge(context)
                        if (faceBridge == null) faceBridge = FaceDetectorBridge(context)
                        if (faceLandmarkerBridge == null) faceLandmarkerBridge = FaceLandmarkerBridge(context)
                        postResult(result, null)
                    }
                    "detectHands" -> {
                        val bridge = handBridge ?: HandAnalyzerBridge(context).also { handBridge = it }
                        val args = call.arguments as? Map<*, *>
                            ?: return@execute postError(result, "BAD_ARGS", "expected Map")
                        val frame = FrameArgs.fromMap(args)
                        val hands = bridge.detect(frame)
                        postResult(result, hands)
                    }
                    "detectObjects" -> {
                        val bridge = objectBridge ?: ObjectAnalyzerBridge(context).also { objectBridge = it }
                        val args = call.arguments as? Map<*, *>
                            ?: return@execute postError(result, "BAD_ARGS", "expected Map")
                        val frame = FrameArgs.fromMap(args)
                        val objects = bridge.detect(frame)
                        postResult(result, objects)
                    }
                    "detectFaces" -> {
                        val bridge = faceBridge ?: FaceDetectorBridge(context).also { faceBridge = it }
                        val args = call.arguments as? Map<*, *>
                            ?: return@execute postError(result, "BAD_ARGS", "expected Map")
                        val frame = FrameArgs.fromMap(args)
                        val faces = bridge.detect(frame)
                        postResult(result, faces)
                    }
                    "detectFaceLandmarks" -> {
                        val bridge = faceLandmarkerBridge ?: FaceLandmarkerBridge(context).also { faceLandmarkerBridge = it }
                        val args = call.arguments as? Map<*, *>
                            ?: return@execute postError(result, "BAD_ARGS", "expected Map")
                        val frame = FrameArgs.fromMap(args)
                        val landmarkResult = bridge.detect(frame)
                        postResult(result, landmarkResult)
                    }
                    "encodeFrameToJpeg" -> {
                        val args = call.arguments as? Map<*, *>
                            ?: return@execute postError(result, "BAD_ARGS", "expected Map")
                        val frame = FrameArgs.fromMap(args)
                        val quality = (args["quality"] as? Number)?.toInt() ?: 90
                        val outPath = args["outPath"] as? String
                            ?: return@execute postError(result, "BAD_ARGS", "missing outPath")
                        val path = JpegEncoderBridge.encode(frame, quality, outPath)
                        postResult(result, path)
                    }
                    "decodeUprightRgba" -> {
                        val args = call.arguments as? Map<*, *>
                            ?: return@execute postError(result, "BAD_ARGS", "expected Map")
                        val frame = FrameArgs.fromMap(args)
                        val decoded = UprightRgbaBridge.decode(frame)
                        postResult(result, decoded?.let { UprightRgbaBridge.toMap(it) })
                    }
                    "dispose" -> {
                        handBridge?.close()
                        objectBridge?.close()
                        faceBridge?.close()
                        faceLandmarkerBridge?.close()
                        handBridge = null
                        objectBridge = null
                        faceBridge = null
                        faceLandmarkerBridge = null
                        postResult(result, null)
                    }
                    else -> postNotImplemented(result)
                }
            } catch (e: Throwable) {
                postError(result, "MEDIAPIPE_ERROR", e.message ?: e.javaClass.simpleName, e)
            }
        }
    }

    private fun postResult(result: MethodChannel.Result, payload: Any?) {
        Handler(Looper.getMainLooper()).post { result.success(payload) }
    }

    private fun postError(result: MethodChannel.Result, code: String, message: String, cause: Throwable? = null) {
        Handler(Looper.getMainLooper()).post { result.error(code, message, cause?.toString()) }
    }

    private fun postNotImplemented(result: MethodChannel.Result) {
        Handler(Looper.getMainLooper()).post { result.notImplemented() }
    }
}

/**
 * Frame shape as sent by the Flutter side (see `MediaPipeChannel._encodeFrame`).
 */
data class FrameArgs(
    val bytes: ByteArray,
    val width: Int,
    val height: Int,
    val rotation: Int,
    val format: String,
) {
    companion object {
        fun fromMap(map: Map<*, *>): FrameArgs {
            val bytes = map["bytes"] as ByteArray
            val width = (map["width"] as Number).toInt()
            val height = (map["height"] as Number).toInt()
            val rotation = (map["rotation"] as Number).toInt()
            val format = map["format"] as String
            return FrameArgs(bytes, width, height, rotation, format)
        }
    }
}
