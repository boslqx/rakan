package com.example.rakan

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    private val POSE_CHANNEL = "com.example.rakan/pose_landmarks"
    private val PERMISSION_CHANNEL = "com.example.rakan/permissions"
    private val CAMERA_PERMISSION_CODE = 1001

    private var poseHandler: PoseDetectorHandler? = null
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Create pose handler first so previewView exists before factory is called
        val handler = PoseDetectorHandler(this, this)
        poseHandler = handler

        // Register camera preview as a Flutter platform view
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.example.rakan/camera_preview",
            CameraPreviewFactory { handler.previewView }
        )

        // Pose EventChannel
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            POSE_CHANNEL
        ).setStreamHandler(handler)

        // Permission MethodChannel
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PERMISSION_CHANNEL
        ).setMethodCallHandler { call, result ->
            if (call.method == "requestCamera") {
                if (ContextCompat.checkSelfPermission(
                        this, Manifest.permission.CAMERA
                    ) == PackageManager.PERMISSION_GRANTED
                ) {
                    result.success(true)
                } else {
                    permissionResult = result
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.CAMERA),
                        CAMERA_PERMISSION_CODE
                    )
                }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_PERMISSION_CODE) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            permissionResult?.success(granted)
            permissionResult = null
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        poseHandler?.cleanup()
    }
}