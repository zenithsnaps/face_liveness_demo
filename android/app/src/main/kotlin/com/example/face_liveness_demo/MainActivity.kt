package com.example.face_liveness_demo

import com.example.face_liveness_demo.mediapipe.MediaPipePlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MediaPipePlugin.register(
            context = applicationContext,
            binaryMessenger = flutterEngine.dartExecutor.binaryMessenger,
        )
    }
}
