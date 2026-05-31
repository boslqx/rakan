package com.example.rakan

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {

    private val POSE_CHANNEL = "com.example.rakan/pose_landmarks"
    private var poseHandler: PoseDetectorHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            POSE_CHANNEL
        ).setStreamHandler(
            PoseDetectorHandler(this, this).also { poseHandler = it }
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        poseHandler?.cleanup()
    }
}