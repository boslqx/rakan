import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../data/exercise_data.dart';
import '../services/pose_service.dart';
import '../services/angle_calculator.dart';
import '../services/voice_coach.dart';
import '../widgets/exercise_media.dart';
import '../widgets/form_check_hud.dart';
import '../widgets/pose_countdown_overlay.dart';
import '../widgets/stepper_card.dart';
import '../widgets/voice_toggle_button.dart';
import '../../../shared/widgets/pressable.dart';

class PoseDetectionScreen extends StatefulWidget {
  final String exerciseName;
  final int targetReps;

  /// Brief the exercise first — demo, target reps, camera set-up — and
  /// start the camera only when the user is ready, as Guided mode does
  /// before a set. Off mid-workout, where the exercise is already on show.
  final bool showPreview;

  const PoseDetectionScreen({
    super.key,
    required this.exerciseName,
    required this.targetReps,
    this.showPreview = false,
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
  late int _targetReps = widget.targetReps;

  /// The form verdict of each rep counted so far, in order.
  final List<bool> _repForm = [];

  /// False while the preview is up; the camera starts once it's true.
  late bool _started = !widget.showPreview;

  // Camera permission state
  bool _permissionGranted = false;
  bool _permissionChecked = false;

  // Countdown state
  bool _countingDown = true;

  /// Why the camera pipeline couldn't start (see PoseService); shown in
  /// place of the framing hint. Null while it's working.
  String? _cameraError;

  // Image dimensions from Kotlin (updated field names)
  int _frameWidth = 640;
  int _frameHeight = 480;
  int _frameRotation = 0;

  /// Spoken rep counts and form cues, as in Guided mode.
  final VoiceCoach _voice = VoiceCoach();

  @override
  void initState() {
    super.initState();
    _analyser = ExerciseAnalyserFactory.getAnalyser(widget.exerciseName);
    _requestCameraPermission();
    _voice.loadEnabled().then((_) {
      if (mounted) setState(() {}); // the mute toggle
    });
  }

  Future<void> _requestCameraPermission() async {
    const platform = MethodChannel('com.example.rakan/permissions');
    try {
      final granted = await platform.invokeMethod<bool>('requestCamera') ?? false;
      if (!mounted) return;
      setState(() {
        _permissionGranted = granted;
        _permissionChecked = true;
      });
      if (granted && _started) {
        _startDetection();
      }
    } catch (e) {
      debugPrint('Permission error: $e');
      if (!mounted) return;
      // Fallback — try anyway
      setState(() {
        _permissionGranted = true;
        _permissionChecked = true;
      });
      if (_started) _startDetection();
    }
  }

  /// Leaves the preview. Detection starts now, or as soon as the camera
  /// permission request (still pending) comes back granted.
  void _start() {
    HapticFeedback.lightImpact();
    setState(() => _started = true);
    if (_permissionGranted) _startDetection();
  }

  void _bumpTarget(int delta) {
    HapticFeedback.selectionClick();
    setState(() => _targetReps = (_targetReps + delta).clamp(1, 100));
  }

  void _startDetection() {
    _voice.say('Get in position.');
    _subscription = PoseService.getLandmarkStream(widget.exerciseName).listen(
      (data) {
        if (!mounted) return;

        final detected = data['detected'] as bool? ?? false;

        if (!detected) {
          setState(() {
            _poseDetected = false;
            _landmarks = [];
          });
          if (!_countingDown && !_workoutComplete) {
            _voice.fault(VoiceCoach.lostSightCue);
          }
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

        // Analyse in pixel space (equal units on both axes) — the overlay
        // keeps using the normalized `landmarks`, which its painter expects.
        final result = _analyser.analyse(AngleCalculator.toPixelSpace(
          landmarks,
          frameWidth: (data['frameWidth'] as int?) ?? 640,
          frameHeight: (data['frameHeight'] as int?) ?? 480,
          // Rotate upright so gravity-referenced checks (trunk lean, shin
          // angle) work. 270 = front camera in portrait, the same
          // orientation SkeletonPainter assumes.
          rotationDegrees: (data['frameRotation'] as int?) ?? 270,
        ));

        final wasComplete = _workoutComplete;
        setState(() {
          _poseDetected = true;
          _landmarks = landmarks;
          _lastResult = result;
          _frameWidth = (data['frameWidth'] as int?) ?? 640;
          _frameHeight = (data['frameHeight'] as int?) ?? 480;
          _frameRotation = (data['frameRotation'] as int?) ?? 0;

          if (result.countRep) {
            _repCount = _analyser.repCount;
            _repForm.add(result.repCorrect);
            if (_repCount >= _targetReps) {
              _workoutComplete = true;
            }
          }
        });

        // Quiet once the set is complete — the summary was the last word.
        if (wasComplete) return;
        _voice.fault(result.isCorrect ? null : result.feedback);
        if (!result.countRep) return;
        if (_workoutComplete) {
          _voice.say('Set complete. ${VoiceCoach.formSummary(_repForm)}');
        } else {
          _voice.rep(_repCount,
              good: result.repCorrect, verdict: result.repFeedback);
        }
      },
      onError: (Object error) {
        debugPrint('Pose stream error: $error');
        _subscription?.cancel();
        if (!mounted) return;
        setState(() {
          _poseDetected = false;
          _landmarks = [];
          _cameraError = error is PoseStreamException
              ? error.message
              : "The camera couldn't start.";
        });
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _voice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_started) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(child: _buildPreview()),
      );
    }
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
                      Icon(
                          _cameraError != null
                              ? Icons.videocam_off_rounded
                              : Icons.accessibility_new_rounded,
                          color: Colors.white24,
                          size: 80),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _cameraError != null
                              ? '$_cameraError Close the camera and log this set by hand.'
                              : _permissionChecked && !_permissionGranted
                                  ? 'Camera permission required'
                                  : 'Point camera at your full body',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(
                            color: Colors.white38,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Countdown overlay — blocks rep counting, not the camera preview itself
            if (_countingDown && _permissionGranted && _cameraError == null)
              Positioned.fill(
                child: PoseCountdownOverlay(
                  bodyVisible: _poseDetected,
                  onTick: (left) {
                    if (left <= 3) _voice.say('$left');
                  },
                  onComplete: () {
                    _voice.say('Go!');
                    setState(() => _countingDown = false);
                  },
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
            if (!_poseDetected && _permissionGranted && _cameraError == null)
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
                  backgroundColor: AppColors.surfaceContainerLow.withValues(alpha: 0.9),
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
          Pressable(
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
          const SizedBox(width: 10),
          VoiceToggleButton(coach: _voice),
          const SizedBox(width: 10),
          // Detection indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _poseDetected
                  ? Colors.green.withValues(alpha: 0.3)
                  : Colors.red.withValues(alpha: 0.3),
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
    final good = _repForm.where((ok) => ok).length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
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
                ' / $_targetReps',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 24,
                  fontWeight: FontWeight.w400,
                  color: Colors.white38,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        RepFormTally(good: good, bad: _repForm.length - good),
      ],
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
            ? Colors.green.withValues(alpha: 0.85)
            : AppColors.error.withValues(alpha: 0.85),
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
    final good = _repForm.where((ok) => ok).length;
    final accuracy = _repForm.isEmpty ? null : formAccuracyPercent(_repForm);
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
            if (accuracy != null) ...[
              const SizedBox(height: 20),
              Text(
                '$accuracy%',
                semanticsLabel: '$accuracy percent accuracy',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 56,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: formAccuracyColor(accuracy),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'FORM ACCURACY',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: Colors.white54,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              accuracy != null
                  ? '$good of ${_repForm.length} reps with good form'
                  : '$_repCount reps completed',
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

  /// Before the camera starts: the demo, the target, and how to set up the
  /// phone — the same brief Guided mode gives before a set.
  Widget _buildPreview() {
    final data = findExerciseByName(widget.exerciseName);
    final gif = data?.localGifAsset;
    final muscles = [
      if (data != null && data.muscleGroup.isNotEmpty) data.muscleGroup,
      ...?data?.secondaryMuscles.take(2),
    ];
    final cameraOff = _permissionChecked && !_permissionGranted;
    TextStyle label({double fontSize = 10, Color color = Colors.white54}) =>
        GoogleFonts.manrope(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: color,
        );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Row(
            children: [
              Pressable(
                onTap: () => Navigator.of(context).pop(_repCount),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 14),
              Text('FORM CHECK', style: label()),
              const Spacer(),
              VoiceToggleButton(coach: _voice),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (gif != null)
                  ExerciseDemoPanel(
                    gifAsset: gif,
                    title: widget.exerciseName,
                    badge: 'DEMO',
                    heroTag: 'form-check-demo-${widget.exerciseName}',
                    height: 210,
                  )
                else
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.fitness_center_rounded,
                        size: 40, color: Colors.white24),
                  ),
                const SizedBox(height: 20),
                Text(
                  'PRACTICE SET',
                  style: label(fontSize: 12, color: AppColors.primary)
                      .copyWith(letterSpacing: 2),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.exerciseName,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                if (muscles.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(muscles.join(' · ').toUpperCase(),
                      style: label(fontSize: 11, color: Colors.white38)),
                ],
                const SizedBox(height: 22),
                StepperCard(
                  label: 'TARGET REPS',
                  value: '$_targetReps',
                  onMinus: () => _bumpTarget(-1),
                  onPlus: () => _bumpTarget(1),
                ),
                const SizedBox(height: 14),
                if (cameraOff)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.videocam_off_rounded,
                            size: 16, color: Colors.white54),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Form check needs the camera — allow access to count your reps.',
                            style: GoogleFonts.manrope(
                                fontSize: 12, height: 1.4, color: Colors.white54),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  CameraSetupNote(exerciseName: widget.exerciseName),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: cameraOff ? _requestCameraPermission : _start,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.videocam_rounded,
                      size: 18, color: AppColors.onPrimary),
                  const SizedBox(width: 8),
                  Text(
                    cameraOff ? 'ALLOW CAMERA' : 'START',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: AppColors.onPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
      ..color = activeColor.withValues(alpha: 0.9)
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