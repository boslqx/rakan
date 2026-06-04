package com.example.rakan

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.util.Log
import android.view.Surface
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker.PoseLandmarkerOptions
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class PoseDetectorHandler(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
) : EventChannel.StreamHandler {

    private var eventSink: EventChannel.EventSink? = null
    private var poseLandmarker: PoseLandmarker? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private val cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    // Track actual image dimensions reported by CameraX
    private var frameWidth: Int = 640
    private var frameHeight: Int = 480
    private var frameRotation: Int = 0

    val previewView: PreviewView = PreviewView(context).apply {
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        scaleType = PreviewView.ScaleType.FILL_CENTER
        // Remove mirror - keep natural camera orientation
        scaleX = 1f
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        eventSink = sink
        val exerciseType = arguments as? String ?: "squat"
        setupMediaPipe()
        startCamera(exerciseType)
    }

    override fun onCancel(arguments: Any?) {
        cleanup()
        eventSink = null
    }

    private fun setupMediaPipe() {
        try {
            val baseOptions = BaseOptions.builder()
                .setModelAssetPath("pose_landmarker.task")
                .build()

            val options = PoseLandmarkerOptions.builder()
                .setBaseOptions(baseOptions)
                .setRunningMode(RunningMode.LIVE_STREAM)
                .setNumPoses(1)
                .setMinPoseDetectionConfidence(0.5f)
                .setMinPosePresenceConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .setResultListener { result: PoseLandmarkerResult, _ ->
                    handlePoseResult(result)
                }
                .setErrorListener { error: RuntimeException ->
                    Log.e("PoseDetector", "MediaPipe error: ${error.message}")
                    sendEvent(mapOf("detected" to false))
                }
                .build()

            poseLandmarker = PoseLandmarker.createFromOptions(context, options)
            Log.d("PoseDetector", "MediaPipe initialized")
        } catch (e: Exception) {
            Log.e("PoseDetector", "Failed to initialize MediaPipe: ${e.message}")
        }
    }

    private fun handlePoseResult(result: PoseLandmarkerResult) {
        if (result.landmarks().isEmpty()) {
            sendEvent(mapOf("detected" to false))
            return
        }

        val personLandmarks = result.landmarks()[0]
        val landmarkList = personLandmarks.map { landmark ->
            mapOf(
                "x" to landmark.x().toDouble(),
                "y" to landmark.y().toDouble(),
                "z" to landmark.z().toDouble(),
                "visibility" to (landmark.visibility().orElse(0.0f)).toDouble()
            )
        }

        // Send actual frame dimensions so Flutter can scale correctly
        sendEvent(mapOf(
            "detected" to true,
            "landmarks" to landmarkList,
            "frameWidth" to frameWidth,
            "frameHeight" to frameHeight,
            "frameRotation" to frameRotation
        ))
    }

    private fun startCamera(exerciseType: String) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)

        cameraProviderFuture.addListener({
            cameraProvider = cameraProviderFuture.get()

            val displayRotation = previewView.display?.rotation ?: Surface.ROTATION_0

            val preview = Preview.Builder()
                .setTargetRotation(displayRotation)
                .build().also {
                    it.setSurfaceProvider(previewView.surfaceProvider)
                }

            val imageAnalysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                .setTargetRotation(displayRotation)
                .build()

            imageAnalysis.setAnalyzer(cameraExecutor) { imageProxy ->
                processFrame(imageProxy)
            }

            try {
                cameraProvider?.unbindAll()
                cameraProvider?.bindToLifecycle(
                    lifecycleOwner,
                    CameraSelector.DEFAULT_FRONT_CAMERA,
                    preview,
                    imageAnalysis
                )
                Log.d("PoseDetector", "Camera started for: $exerciseType")
            } catch (e: Exception) {
                Log.e("PoseDetector", "Camera binding failed: ${e.message}")
            }

        }, ContextCompat.getMainExecutor(context))
    }

    private fun processFrame(imageProxy: ImageProxy) {
        try {
            // Record actual frame dimensions and rotation
            frameWidth = imageProxy.width
            frameHeight = imageProxy.height
            frameRotation = imageProxy.imageInfo.rotationDegrees

            Log.d("PoseDetector", "Frame: ${frameWidth}x${frameHeight} rotation=${frameRotation}")

            val bitmap = imageProxy.toBitmap()

            // Use bitmap as-is - both preview and landmarks in natural coordinates
            val mpImage = BitmapImageBuilder(bitmap).build()
            poseLandmarker?.detectAsync(mpImage, imageProxy.imageInfo.timestamp)

        } catch (e: Exception) {
            Log.e("PoseDetector", "Frame error: ${e.message}")
        } finally {
            imageProxy.close()
        }
    }

    private fun sendEvent(data: Map<String, Any?>) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            eventSink?.success(data)
        }
    }

    fun cleanup() {
        cameraProvider?.unbindAll()
        poseLandmarker?.close()
        if (!cameraExecutor.isShutdown) cameraExecutor.shutdown()
        Log.d("PoseDetector", "Stopped")
    }
}