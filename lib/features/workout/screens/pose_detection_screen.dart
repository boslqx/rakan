import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../services/pose_service.dart';
import '../services/angle_calculator.dart';
import 'package:flutter/services.dart';

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
  dynamic _analyser;

  // Rep tracking
  int _repCount = 0;
  bool _workoutComplete = false;

  // Camera permission state
  bool _permissionGranted = false;
  bool _permissionChecked = false;

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

        // Parse landmarks from the map data sent by Kotlin
        final rawLandmarks = data['landmarks'] as List<dynamic>;
        final landmarks = rawLandmarks
            .map((l) => Landmark.fromMap(Map<String, dynamic>.from(l as Map)))
            .toList();

        // Run exercise-specific analysis
        PostureResult result;
        if (_analyser is SquatAnalyser) {
          result = (_analyser as SquatAnalyser).analyse(landmarks);
        } else if (_analyser is PushUpAnalyser) {
          result = (_analyser as PushUpAnalyser).analyse(landmarks);
        } else if (_analyser is ShoulderPressAnalyser) {
          result = (_analyser as ShoulderPressAnalyser).analyse(landmarks);
        } else {
          result = (_analyser as SquatAnalyser).analyse(landmarks);
        }

        setState(() {
          _poseDetected = true;
          _landmarks = landmarks;
          _lastResult = result;
          if (result.countRep) {
            _repCount = result.countRep
                ? (_analyser is SquatAnalyser
                    ? (_analyser as SquatAnalyser).repCount
                    : _analyser is PushUpAnalyser
                        ? (_analyser as PushUpAnalyser).repCount
                        : (_analyser as ShoulderPressAnalyser).repCount)
                : _repCount;
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
            // Background: camera placeholder
            Positioned.fill(
              child: _permissionGranted
                  ? AndroidView(
                      // WHY AndroidView? Flutter can't directly render CameraX PreviewView.
                      // AndroidView embeds the native Android view registered in MainActivity.
                      viewType: 'com.example.rakan/camera_preview',
                      layoutDirection: TextDirection.ltr,
                      creationParamsCodec: const StandardMessageCodec(),
                    )
                  : Container(color: Colors.black),
            ),

            // Skeleton overlay on top of camera
            if (_poseDetected)
              Positioned.fill(
                child: CustomPaint(
                  painter: SkeletonPainter(
                    landmarks: _landmarks,
                    isCorrect: _lastResult?.isCorrect ?? true,
                  ),
                ),
              ),

            //  No pose detected overlay
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

            //  Feedback banner
            Positioned(
              bottom: 120,
              left: 24,
              right: 24,
              child: _buildFeedbackBanner(),
            ),

            //  Instructions
            if (!_poseDetected && _permissionGranted)
              Positioned(
                bottom: 200,
                left: 24,
                right: 24,
                child: _buildInstructions(),
              ),

            //  Complete overlay 
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

// Skeleton Painter
// Draws the MediaPipe landmark skeleton on a Canvas overlay
class SkeletonPainter extends CustomPainter {
  final List<Landmark> landmarks;
  final bool isCorrect;

  const SkeletonPainter({
    required this.landmarks,
    required this.isCorrect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.isEmpty) return;

    final jointPaint = Paint()
      ..color = isCorrect ? Colors.green : Colors.redAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.fill;

    final bonePaint = Paint()
      ..color = (isCorrect ? Colors.green : Colors.redAccent).withOpacity(0.7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Draw bones (connections between landmarks)
    final connections = [
      // Torso
      [PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.rightShoulder],
      [PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.leftHip],
      [PoseLandmarkIndex.rightShoulder, PoseLandmarkIndex.rightHip],
      [PoseLandmarkIndex.leftHip, PoseLandmarkIndex.rightHip],
      // Left arm
      [PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.leftElbow],
      [PoseLandmarkIndex.leftElbow, PoseLandmarkIndex.leftWrist],
      // Right arm
      [PoseLandmarkIndex.rightShoulder, PoseLandmarkIndex.rightElbow],
      [PoseLandmarkIndex.rightElbow, PoseLandmarkIndex.rightWrist],
      // Left leg
      [PoseLandmarkIndex.leftHip, PoseLandmarkIndex.leftKnee],
      [PoseLandmarkIndex.leftKnee, PoseLandmarkIndex.leftAnkle],
      // Right leg
      [PoseLandmarkIndex.rightHip, PoseLandmarkIndex.rightKnee],
      [PoseLandmarkIndex.rightKnee, PoseLandmarkIndex.rightAnkle],
    ];

    for (final connection in connections) {
      final a = landmarks[connection[0]];
      final b = landmarks[connection[1]];
      if (a.visibility < 0.3 || b.visibility < 0.3) continue;

      canvas.drawLine(
        Offset(a.x * size.width, a.y * size.height),
        Offset(b.x * size.width, b.y * size.height),
        bonePaint,
      );
    }

    // Draw joints (circles at each visible landmark)
    for (final landmark in landmarks) {
      if (landmark.visibility < 0.3) continue;
      canvas.drawCircle(
        Offset(landmark.x * size.width, landmark.y * size.height),
        5,
        jointPaint,
      );
    }
  }

  @override
  bool shouldRepaint(SkeletonPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks ||
        oldDelegate.isCorrect != isCorrect;
  }
}