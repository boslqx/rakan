import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../services/pose_service.dart';
import '../services/angle_calculator.dart';
import '../widgets/pose_countdown_overlay.dart';

class PoseDetectionScreen extends StatefulWidget {
  final String exerciseName;
  final int targetReps;

  const PoseDetectionScreen({
    super.key,
    required this.exerciseName,
    required this.targetReps,
  });

  @override
  State<PoseDetectionScreen> createState() => _PoseDetectionScreenState();
}

class _PoseDetectionScreenState extends State<PoseDetectionScreen> {
  StreamSubscription? _subscription;

  // Current landmark data from MediaPipe
  List<Landmark> _landmarks = [];
  bool _poseDetected = false;

  // Posture feedback state
  PostureResult? _lastResult;
  late final PostureAnalyser _analyser;

  // Rep tracking
  int _repCount = 0;
  bool _workoutComplete = false;

  // Camera permission state
  bool _permissionGranted = false;
  bool _permissionChecked = false;

  // Countdown state
  bool _countingDown = true;

  // Image dimensions from Kotlin (updated field names)
  int _frameWidth = 640;
  int _frameHeight = 480;
  int _frameRotation = 0;

  @override
  void initState() {
    super.initState();
    _analyser = ExerciseAnalyserFactory.getAnalyser(widget.exerciseName);
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    const platform = MethodChannel('com.example.rakan/permissions');
    try {
      final granted = await platform.invokeMethod<bool>('requestCamera') ?? false;
      setState(() {
        _permissionGranted = granted;
        _permissionChecked = true;
      });
      if (granted) {
        _startDetection();
      }
    } catch (e) {
      print('Permission error: $e');
      // Fallback — try anyway
      setState(() {
        _permissionGranted = true;
        _permissionChecked = true;
      });
      _startDetection();
    }
  }

  void _startDetection() {
    _subscription = PoseService.getLandmarkStream(widget.exerciseName).listen(
      (data) {
        if (!mounted) return;

        final detected = data['detected'] as bool? ?? false;

        if (!detected) {
          setState(() {
            _poseDetected = false;
            _landmarks = [];
          });
          return;
        }

        final rawLandmarks = data['landmarks'] as List<dynamic>;
        final landmarks = rawLandmarks
            .map((l) => Landmark.fromMap(Map<String, dynamic>.from(l as Map)))
            .toList();

        // While counting down: update the skeleton overlay so the user gets
        // positioning feedback, but NEVER call _analyser.analyse(). This is
        // the gate — the analyser object exists (freshly constructed in
        // initState) but is never invoked until the countdown finishes, so
        // its hysteresis state (_phase, _hasReachedFlexed, etc.) cannot be
        // corrupted by unstable setup-phase frames.
        if (_countingDown) {
          setState(() {
            _poseDetected = true;
            _landmarks = landmarks;
            _frameWidth = (data['frameWidth'] as int?) ?? 640;
            _frameHeight = (data['frameHeight'] as int?) ?? 480;
            _frameRotation = (data['frameRotation'] as int?) ?? 0;
          });
          return;
        }

        final result = _analyser.analyse(landmarks);

        setState(() {
          _poseDetected = true;
          _landmarks = landmarks;
          _lastResult = result;
          _frameWidth = (data['frameWidth'] as int?) ?? 640;
          _frameHeight = (data['frameHeight'] as int?) ?? 480;
          _frameRotation = (data['frameRotation'] as int?) ?? 0;

          if (result.countRep) {
            _repCount = _analyser.repCount;
            if (_repCount >= widget.targetReps) {
              _workoutComplete = true;
            }
          }
        });
      },
      onError: (error) {
        print('Pose stream error: $error');
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Background: real camera preview
            Positioned.fill(
              child: _permissionGranted
                  ? AndroidView(
                      viewType: 'com.example.rakan/camera_preview',
                      layoutDirection: TextDirection.ltr,
                      creationParamsCodec: const StandardMessageCodec(),
                    )
                  : Container(color: Colors.black),
            ),

            // Skeleton overlay on top of camera
            if (_poseDetected && _landmarks.isNotEmpty)
              Positioned.fill(
                child: CustomPaint(
                  painter: SkeletonPainter(
                    landmarks: _landmarks,
                    isCorrect: _lastResult?.isCorrect ?? true,
                    frameWidth: _frameWidth,
                    frameHeight: _frameHeight,
                    rotation: _frameRotation,
                  ),
                ),
              ),

            // No pose detected overlay
            if (!_poseDetected)
              Positioned.fill(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.accessibility_new_rounded,
                          color: Colors.white24, size: 80),
                      const SizedBox(height: 16),
                      Text(
                        _permissionChecked && !_permissionGranted
                            ? 'Camera permission required'
                            : 'Point camera at your full body',
                        style: GoogleFonts.manrope(
                          color: Colors.white38,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Countdown overlay — blocks rep counting, not the camera preview itself
            if (_countingDown && _permissionGranted)
              Positioned.fill(
                child: PoseCountdownOverlay(
                  onComplete: () => setState(() => _countingDown = false),
                ),
              ),

            // Top bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(),
            ),

            // Rep counter
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: _buildRepCounter(),
            ),

            // Feedback banner
            Positioned(
              bottom: 120,
              left: 24,
              right: 24,
              child: _buildFeedbackBanner(),
            ),

            // Instructions
            if (!_poseDetected && _permissionGranted)
              Positioned(
                bottom: 200,
                left: 24,
                right: 24,
                child: _buildInstructions(),
              ),

            // Complete overlay
            if (_workoutComplete) _buildCompleteOverlay(),

            // Close button
            Positioned(
              bottom: 40,
              left: 24,
              right: 24,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(_repCount),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.surfaceContainerLow.withOpacity(0.9),
                  foregroundColor: AppColors.onSurface,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  _workoutComplete ? 'DONE — BACK TO WORKOUT' : 'CLOSE CAMERA',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(_repCount),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.exerciseName.toUpperCase(),
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
          ),
          // Detection indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _poseDetected
                  ? Colors.green.withOpacity(0.3)
                  : Colors.red.withOpacity(0.3),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _poseDetected ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _poseDetected ? 'DETECTED' : 'SEARCHING',
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _poseDetected ? Colors.green : Colors.red,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRepCounter() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$_repCount',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 48,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            Text(
              ' / ${widget.targetReps}',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 24,
                fontWeight: FontWeight.w400,
                color: Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackBanner() {
    if (_lastResult == null) return const SizedBox.shrink();

    final isCorrect = _lastResult!.isCorrect;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isCorrect
            ? Colors.green.withOpacity(0.85)
            : AppColors.error.withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            isCorrect ? Icons.check_circle_rounded : Icons.warning_rounded,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _lastResult!.feedback,
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          if (_lastResult!.keyAngle != null)
            Text(
              '${_lastResult!.keyAngle!.toStringAsFixed(0)}°',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white70,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        ExerciseAnalyserFactory.getInstructions(widget.exerciseName),
        textAlign: TextAlign.center,
        style: GoogleFonts.manrope(
          fontSize: 13,
          color: Colors.white70,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildCompleteOverlay() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_rounded,
                color: AppColors.primary, size: 64),
            const SizedBox(height: 16),
            Text(
              'SET COMPLETE!',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$_repCount reps completed with good form',
              style: GoogleFonts.manrope(
                fontSize: 16,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Skeleton Painter — draws the MediaPipe landmark skeleton on Canvas
class SkeletonPainter extends CustomPainter {
  final List<Landmark> landmarks;
  final bool isCorrect;
  final int frameWidth;
  final int frameHeight;
  final int rotation;

  const SkeletonPainter({
    required this.landmarks,
    required this.isCorrect,
    required this.frameWidth,
    required this.frameHeight,
    required this.rotation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.isEmpty) return;

    final Color activeColor =
        isCorrect ? Colors.greenAccent : Colors.redAccent;

    final bonePaint = Paint()
      ..color = activeColor.withOpacity(0.9)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final jointPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;

    const double inputW = 480.0;
    const double inputH = 640.0;

    final double inputAspect = inputW / inputH;
    final double screenAspect = size.width / size.height;

    double scaleX, scaleY, offsetX, offsetY;

    if (screenAspect >= inputAspect) {
      scaleX = size.width;
      scaleY = size.width / inputAspect;
      offsetX = 0;
      offsetY = (size.height - scaleY) / 2;
    } else {
      scaleY = size.height;
      scaleX = size.height * inputAspect;
      offsetX = (size.width - scaleX) / 2;
      offsetY = 0;
    }

    Offset toScreen(Landmark l) {
      // Swap x↔y to correct for landscape frame containing portrait person
      // Mirror horizontally to match the camera preview (front camera flip)
      final double mappedX = 1.0 - l.y; // landmark y → screen x (mirrored)
      final double mappedY = 1.0 - l.x; // landmark x → screen y (inverted)

      return Offset(
        mappedX * scaleX + offsetX,
        mappedY * scaleY + offsetY,
      );
    }

    final connections = [
      [PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.rightShoulder],
      [PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.leftHip],
      [PoseLandmarkIndex.rightShoulder, PoseLandmarkIndex.rightHip],
      [PoseLandmarkIndex.leftHip, PoseLandmarkIndex.rightHip],
      [PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.leftElbow],
      [PoseLandmarkIndex.leftElbow, PoseLandmarkIndex.leftWrist],
      [PoseLandmarkIndex.rightShoulder, PoseLandmarkIndex.rightElbow],
      [PoseLandmarkIndex.rightElbow, PoseLandmarkIndex.rightWrist],
      [PoseLandmarkIndex.leftHip, PoseLandmarkIndex.leftKnee],
      [PoseLandmarkIndex.leftKnee, PoseLandmarkIndex.leftAnkle],
      [PoseLandmarkIndex.rightHip, PoseLandmarkIndex.rightKnee],
      [PoseLandmarkIndex.rightKnee, PoseLandmarkIndex.rightAnkle],
    ];

    for (final connection in connections) {
      final a = landmarks[connection[0]];
      final b = landmarks[connection[1]];
      if (a.visibility < 0.3 || b.visibility < 0.3) continue;
      canvas.drawLine(toScreen(a), toScreen(b), bonePaint);
    }

    for (final landmark in landmarks) {
      if (landmark.visibility < 0.3) continue;
      canvas.drawCircle(toScreen(landmark), 6, jointPaint);
    }
  }

  @override
  bool shouldRepaint(SkeletonPainter old) =>
      old.landmarks != landmarks ||
      old.isCorrect != isCorrect ||
      old.rotation != rotation ||
      old.frameWidth != frameWidth ||
      old.frameHeight != frameHeight;
}