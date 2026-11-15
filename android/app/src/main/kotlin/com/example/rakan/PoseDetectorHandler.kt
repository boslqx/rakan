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
import com.google.mediapipe.framework.image.BitmapExtractor
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker.PoseLandmarkerOptions
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

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

    // Last timestamp handed to MediaPipe, which rejects any that don't
    // increase. Written on the main thread (setup), read on cameraExecutor.
    @Volatile private var lastTimestampMs: Long = -1

    /** Who the user is among everyone in frame. Replaced on main, used on MediaPipe's thread. */
    @Volatile private var tracker = TargetTracker()

    val previewView: PreviewView = PreviewView(context).apply {
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        scaleType = PreviewView.ScaleType.FILL_CENTER
        // Remove mirror - keep natural camera orientation
        scaleX = 1f
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        eventSink = sink
        val exerciseType = arguments as? String ?: "squat"
        if (setupMediaPipe()) startCamera(exerciseType)
    }

    override fun onCancel(arguments: Any?) {
        cleanup()
        eventSink = null
    }

    /** Loads the pose model. Returns false — after telling Flutter — if it can't. */
    private fun setupMediaPipe(): Boolean {
        // A new landmarker accepts any first timestamp.
        lastTimestampMs = -1
        // Each stream (one per set) locks onto the user afresh.
        tracker = TargetTracker()
        try {
            val baseOptions = BaseOptions.builder()
                .setModelAssetPath("pose_landmarker.task")
                .build()

            val options = PoseLandmarkerOptions.builder()
                .setBaseOptions(baseOptions)
                .setRunningMode(RunningMode.LIVE_STREAM)
                // Several people, so TargetTracker — not MediaPipe — picks
                // which one is the user (a busy gym has others in frame).
                .setNumPoses(MAX_POSES)
                .setMinPoseDetectionConfidence(0.5f)
                .setMinPosePresenceConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .setResultListener { result: PoseLandmarkerResult, input: MPImage ->
                    handlePoseResult(result, input)
                }
                .setErrorListener { error: RuntimeException ->
                    Log.e("PoseDetector", "MediaPipe error: ${error.message}")
                    sendEvent(mapOf("detected" to false))
                }
                .build()

            poseLandmarker = PoseLandmarker.createFromOptions(context, options)
            Log.d("PoseDetector", "MediaPipe initialized")
            return true
        } catch (e: Exception) {
            Log.e("PoseDetector", "Failed to initialize MediaPipe: ${e.message}")
            sendError("model_unavailable", e.message)
            return false
        }
    }

    private fun handlePoseResult(result: PoseLandmarkerResult, input: MPImage) {
        val poses = result.landmarks()
        val bitmap = try { BitmapExtractor.extract(input) } catch (e: Exception) { null }

        val people = poses.mapIndexedNotNull { i, pose ->
            val pts = pose.map {
                TargetTracker.Pt(it.x(), it.y(), it.visibility().orElse(0f))
            }
            TargetTracker.describe(i, pts, frameWidth, frameHeight, bitmap?.let { torsoColour(it, pts) })
        }

        val wasLocked = tracker.isLocked
        val outcome = tracker.update(people, frameWidth, frameHeight, result.timestampMs())
        logTrackerChange(wasLocked, outcome, people.size)
        when (outcome) {
            TargetTracker.Outcome.NoOne -> sendEvent(mapOf("detected" to false))
            // The user stepped out (or is blocked); others may be in frame
            // but are ignored. Flutter pauses rep counting on this.
            TargetTracker.Outcome.Lost ->
                sendEvent(mapOf("detected" to false, "reason" to "target_lost"))
            is TargetTracker.Outcome.Target -> sendPose(poses[outcome.index])
        }
    }

    private var lastOutcomeKind: String? = null

    /** Logs lock / lost / found only when they change — not every frame. */
    private fun logTrackerChange(wasLocked: Boolean, outcome: TargetTracker.Outcome, seen: Int) {
        val kind = when (outcome) {
            TargetTracker.Outcome.NoOne -> "no_one"
            TargetTracker.Outcome.Lost -> "lost"
            is TargetTracker.Outcome.Target -> if (tracker.isLocked) "tracking" else "acquiring"
        }
        if (!wasLocked && tracker.isLocked) Log.d(TAG, "locked onto user ($seen in frame)")
        if (kind != lastOutcomeKind) {
            Log.d(TAG, "tracker: $kind ($seen in frame)")
            lastOutcomeKind = kind
        }
    }

    /**
     * Mean colour of the middle of the torso (the shirt), RGB 0..1 — lets
     * the tracker tell the user from a stranger of the same build. Landmarks
     * are normalised to [bitmap], which is the unrotated camera frame.
     */
    private fun torsoColour(bitmap: Bitmap, lm: List<TargetTracker.Pt>): FloatArray? {
        val ls = lm[11]; val rs = lm[12]; val lh = lm[23]; val rh = lm[24]
        var r = 0f; var g = 0f; var b = 0f; var n = 0
        val steps = 6
        for (i in 0 until steps) {
            // Inner 20–80% of the torso, away from arms and background.
            val v = 0.2f + 0.6f * i / (steps - 1)
            for (j in 0 until steps) {
                val u = 0.2f + 0.6f * j / (steps - 1)
                val topX = ls.x + (rs.x - ls.x) * u
                val topY = ls.y + (rs.y - ls.y) * u
                val botX = lh.x + (rh.x - lh.x) * u
                val botY = lh.y + (rh.y - lh.y) * u
                val px = ((topX + (botX - topX) * v) * bitmap.width).toInt()
                val py = ((topY + (botY - topY) * v) * bitmap.height).toInt()
                if (px !in 0 until bitmap.width || py !in 0 until bitmap.height) continue
                val c = bitmap.getPixel(px, py)
                r += ((c shr 16) and 0xFF) / 255f
                g += ((c shr 8) and 0xFF) / 255f
                b += (c and 0xFF) / 255f
                n++
            }
        }
        return if (n < 8) null else floatArrayOf(r / n, g / n, b / n)
    }

    private fun sendPose(personLandmarks: List<NormalizedLandmark>) {
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
            // Getting the provider can fail too (no camera service), not
            // only binding — both are reported to Flutter below.
            try {
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
                sendError("camera_unavailable", e.message)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun processFrame(imageProxy: ImageProxy) {
        try {
            // Record actual frame dimensions and rotation. Logged only when
            // they change — logging every frame flooded logcat ~30 times a second.
            val width = imageProxy.width
            val height = imageProxy.height
            val rotation = imageProxy.imageInfo.rotationDegrees
            if (width != frameWidth || height != frameHeight || rotation != frameRotation) {
                Log.d("PoseDetector", "Frame: ${width}x${height} rotation=${rotation}")
            }
            frameWidth = width
            frameHeight = height
            frameRotation = rotation

            // detectAsync takes MILLISECONDS; CameraX timestamps are
            // nanoseconds. Passed raw, frames ~33 ms apart looked ~9 hours
            // apart to MediaPipe, which switched off its landmark smoothing.
            val timestampMs = TimeUnit.NANOSECONDS.toMillis(imageProxy.imageInfo.timestamp)
            if (timestampMs <= lastTimestampMs) return
            lastTimestampMs = timestampMs

            val bitmap = imageProxy.toBitmap()

            // Use bitmap as-is - both preview and landmarks in natural coordinates
            val mpImage = BitmapImageBuilder(bitmap).build()
            poseLandmarker?.detectAsync(mpImage, timestampMs)

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

    /**
     * Tells Flutter the pipeline couldn't start. [code] ("model_unavailable",
     * "camera_unavailable") picks the message the app shows; [details] is
     * for logs only.
     */
    private fun sendError(code: String, details: String?) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            eventSink?.error(code, details, null)
        }
    }

    fun cleanup() {
        cameraProvider?.unbindAll()
        poseLandmarker?.close()
        Log.d("PoseDetector", "Stopped")
    }

    companion object {
        /** People MediaPipe reports per frame; the tracker picks the user. */
        private const val MAX_POSES = 3
        private const val TAG = "PoseTracker"
    }
}