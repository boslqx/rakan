import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/active_session_state.dart';
import '../services/pose_service.dart';
import '../services/angle_calculator.dart';
import 'pose_detection_screen.dart';


enum _ScreenPhase { ready, active, resting, rpe }

class AutoLogScreen extends StatefulWidget {
  final String workoutName;
  final List<ExerciseSessionState> exercises;

  const AutoLogScreen({
    super.key,
    required this.workoutName,
    required this.exercises,
  });

  @override
  State<AutoLogScreen> createState() => _AutoLogScreenState();
}

class _AutoLogScreenState extends State<AutoLogScreen> {
  int _exerciseIndex = 0;
  _ScreenPhase _phase = _ScreenPhase.ready;

  // Rest timer
  Timer? _restTicker;

  // Camera / pose detection state (mirrors PoseDetectionScreen)
  StreamSubscription? _poseSubscription;
  List<Landmark> _landmarks = [];
  bool _poseDetected = false;
  PostureResult? _lastResult;
  dynamic _analyser;
  int _repCount = 0;
  int _frameWidth = 640;
  int _frameHeight = 480;
  int _frameRotation = 0;

  bool _permissionGranted = false;

  ExerciseSessionState get _currentExercise => widget.exercises[_exerciseIndex];
  bool get _isLastExercise => _exerciseIndex == widget.exercises.length - 1;

  @override
  void initState() {
    super.initState();
    // Only bother asking for camera permission if at least one exercise
    final anyNeedsCamera =
        widget.exercises.any((ex) => ex.data?.hasPoseDetection ?? false);
    if (anyNeedsCamera) {
      _requestCameraPermission();
    }
  }

  @override
  void dispose() {
    _restTicker?.cancel();
    _poseSubscription?.cancel();
    super.dispose();
  }

  Future<void> _requestCameraPermission() async {
    const platform = MethodChannel('com.example.rakan/permissions');
    try {
      final granted =
          await platform.invokeMethod<bool>('requestCamera') ?? false;
      if (!mounted) return;
      setState(() {
        _permissionGranted = granted;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _permissionGranted = false;
      });
    }
  }

  bool get _currentExerciseCanUseCamera =>
      (_currentExercise.data?.hasPoseDetection ?? false) && _permissionGranted;

  // Starting a set
  void _startSet() {
    if (_currentExerciseCanUseCamera) {
      _analyser = ExerciseAnalyserFactory.getAnalyser(_currentExercise.exerciseName);
      _repCount = 0;
      _poseDetected = false;
      _landmarks = [];
      _lastResult = null;
      _startPoseStream();
    }
    setState(() => _phase = _ScreenPhase.active);
  }

  void _startPoseStream() {
    _poseSubscription?.cancel();
    _poseSubscription =
        PoseService.getLandmarkStream(_currentExercise.exerciseName).listen(
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
          _frameWidth = (data['frameWidth'] as int?) ?? 640;
          _frameHeight = (data['frameHeight'] as int?) ?? 480;
          _frameRotation = (data['frameRotation'] as int?) ?? 0;

          if (result.countRep) {
            _repCount = _analyser is SquatAnalyser
                ? (_analyser as SquatAnalyser).repCount
                : _analyser is PushUpAnalyser
                    ? (_analyser as PushUpAnalyser).repCount
                    : (_analyser as ShoulderPressAnalyser).repCount;

            final target = _currentExercise.sets[_currentExercise.currentSetIndex].reps;
            if (_repCount >= target) {
              _finishSet(actualReps: _repCount);
            }
          }
        });
      },
      onError: (_) {},
    );
  }

  /// Logs the current set as complete, then decides what comes next:
  void _finishSet({int? actualReps}) {
    _poseSubscription?.cancel();
    final ex = _currentExercise;
    final setIndex = ex.currentSetIndex;
    if (setIndex >= ex.sets.length) return; // safety guard

    if (actualReps != null) {
      ex.sets[setIndex].reps = actualReps;
    }
    ex.completedSets.add(setIndex);
    HapticFeedback.mediumImpact();

    if (!ex.isFullyComplete) {
      _startRest(ex.restSeconds);
    } else {
      setState(() => _phase = _ScreenPhase.rpe);
    }
  }

  void _startRest(int seconds) {
    _restTicker?.cancel();
    setState(() {
      _phase = _ScreenPhase.resting;
      _currentExercise.timerSecondsLeft = seconds;
    });
    _restTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _currentExercise.timerSecondsLeft--;
        if (_currentExercise.timerSecondsLeft <= 0) {
          timer.cancel();
          _phase = _ScreenPhase.ready;
        }
      });
    });
  }

  void _extendRest({int seconds = 30}) {
    setState(() => _currentExercise.timerSecondsLeft += seconds);
  }

  void _skipRest() {
    _restTicker?.cancel();
    setState(() => _phase = _ScreenPhase.ready);
  }

  void _confirmRpeAndAdvance() {
    if (_isLastExercise) {
      Navigator.of(context).pop(true); // true = workout finished
      return;
    }
    setState(() {
      _exerciseIndex++;
      _phase = _ScreenPhase.ready;
    });
  }

  Future<void> _quit() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Exit Auto-Log?',
            style: GoogleFonts.spaceGrotesk(
                color: AppColors.onSurface, fontWeight: FontWeight.w600)),
        content: Text(
            'Sets already logged will be kept. You can switch back to Manual mode.',
            style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Stay', style: GoogleFonts.manrope(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Exit',
                style: GoogleFonts.manrope(
                    color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      Navigator.of(context).pop(false); // false = not finished, just exited
    }
  }

  // Weight quick-edit
  Future<void> _editWeight() async {
    final ex = _currentExercise;
    final setIndex = ex.currentSetIndex;
    if (setIndex >= ex.sets.length) return;
    final controller =
        TextEditingController(text: ex.sets[setIndex].weightKg.toInt().toString());

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('WEIGHT (KG)',
                style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.onSurface),
              decoration: const InputDecoration(border: InputBorder.none),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final val = double.tryParse(controller.text) ?? ex.sets[setIndex].weightKg;
                setState(() {
                  ex.sets[setIndex].weightKg = val;
                  ex.weightManuallySet = true;
                  // Forward-fill remaining, not-yet-completed sets — same
                  // rule as Manual mode, so switching modes stays consistent.
                  for (int i = setIndex + 1; i < ex.sets.length; i++) {
                    if (!ex.completedSets.contains(i)) {
                      ex.sets[i].weightKg = val;
                    }
                  }
                });
                Navigator.pop(context);
              },
              child: Text('SAVE',
                  style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            ),
          ],
        ),
      ),
    );
  }

  // Build
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _quit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: switch (_phase) {
            _ScreenPhase.ready => _buildReadyPhase(),
            _ScreenPhase.active => _currentExerciseCanUseCamera
                ? _buildCameraPhase()
                : _buildVideoFallbackPhase(),
            _ScreenPhase.resting => _buildRestPhase(),
            _ScreenPhase.rpe => _buildRpePhase(),
          },
        ),
      ),
    );
  }

  Widget _topCloseBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: _quit,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
            ),
          ),
          const Spacer(),
          Text(
            'EXERCISE ${_exerciseIndex + 1} OF ${widget.exercises.length}',
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  // READY phase
  Widget _buildReadyPhase() {
    final ex = _currentExercise;
    final setIndex = ex.currentSetIndex;
    final set = ex.sets[setIndex];
    final canCamera = ex.data?.hasPoseDetection ?? false;

    return Column(
      children: [
        _topCloseBar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'SET ${setIndex + 1} OF ${ex.sets.length}',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  ex.exerciseName,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  ex.muscleGroup.toUpperCase(),
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    letterSpacing: 2,
                    color: Colors.white38,
                  ),
                ),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _readyStat('${set.reps}', 'TARGET REPS'),
                    if (ex.tracksWeight) ...[
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _editWeight,
                        child: _readyStat(
                          set.weightKg == 0 ? 'TAP' : '${set.weightKg.toStringAsFixed(0)}kg',
                          'WEIGHT',
                          editable: true,
                        ),
                      ),
                    ],
                  ],
                ),
                if (!canCamera) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.videocam_off_rounded, size: 14, color: Colors.white54),
                        const SizedBox(width: 8),
                        Text(
                          'Form check unavailable — follow the video',
                          style: GoogleFonts.manrope(fontSize: 11, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _startSet,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: Text(
                'START SET',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: AppColors.onPrimary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _readyStat(String value, String label, {bool editable = false}) {
    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: editable ? Border.all(color: Colors.white24) : null,
      ),
      child: Column(
        children: [
          Text(value,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 4),
          Text(label,
              style: GoogleFonts.manrope(fontSize: 9, letterSpacing: 1.5, color: Colors.white38)),
        ],
      ),
    );
  }

  // ACTIVE phase (camera)
  Widget _buildCameraPhase() {
    final ex = _currentExercise;
    final setIndex = ex.currentSetIndex;
    final target = ex.sets[setIndex].reps;

    return Stack(
      children: [
        Positioned.fill(
          child: AndroidView(
            viewType: 'com.example.rakan/camera_preview',
            layoutDirection: TextDirection.ltr,
            creationParamsCodec: const StandardMessageCodec(),
          ),
        ),
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
        if (!_poseDetected)
          Positioned.fill(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.accessibility_new_rounded, color: Colors.white24, size: 72),
                  const SizedBox(height: 12),
                  Text('Point camera at your full body',
                      style: GoogleFonts.manrope(color: Colors.white38, fontSize: 15)),
                ],
              ),
            ),
          ),
        _topCloseBar(),
        Positioned(
          top: 72,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$_repCount',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 44, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  Text(' / $target',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 22, fontWeight: FontWeight.w400, color: Colors.white38)),
                ],
              ),
            ),
          ),
        ),
        if (_lastResult != null)
          Positioned(
            bottom: 110,
            left: 24,
            right: 24,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: (_lastResult!.isCorrect ? Colors.green : AppColors.error)
                    .withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                      _lastResult!.isCorrect
                          ? Icons.check_circle_rounded
                          : Icons.warning_rounded,
                      color: Colors.white,
                      size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_lastResult!.feedback,
                        style: GoogleFonts.manrope(
                            fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          bottom: 32,
          left: 24,
          right: 24,
          child: OutlinedButton(
            onPressed: () => _finishSet(actualReps: _repCount),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text('FINISH SET',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1, color: Colors.white70)),
          ),
        ),
      ],
    );
  }

  // ACTIVE phase (no camera): looping video + tap-to-log ────────────
  Widget _buildVideoFallbackPhase() {
    final ex = _currentExercise;
    final setIndex = ex.currentSetIndex;
    final data = ex.data;

    return Column(
      children: [
        _topCloseBar(),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.videocam_off_rounded, size: 14, color: Colors.white54),
                const SizedBox(width: 8),
                Text('Pose detection not available for this exercise — follow the video',
                    style: GoogleFonts.manrope(fontSize: 11, color: Colors.white54)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: data != null
                  ? _LoopingVideo(youtubeId: data.youtubeId)
                  : Container(color: Colors.white10),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          ex.exerciseName,
          style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 4),
        Text(
          'SET ${setIndex + 1} OF ${ex.sets.length} · ${ex.sets[setIndex].reps} REPS',
          style: GoogleFonts.manrope(fontSize: 12, letterSpacing: 1, color: Colors.white54),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 40),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _finishSet(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: Text('LOG SET',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.onPrimary)),
            ),
          ),
        ),
      ],
    );
  }

  // RESTING phase
  Widget _buildRestPhase() {
    final ex = _currentExercise;
    return Column(
      children: [
        _topCloseBar(),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('RESTING',
                    style: GoogleFonts.manrope(
                        fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 3, color: Colors.white38)),
                const SizedBox(height: 16),
                Text('${ex.timerSecondsLeft}',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 88, fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 8),
                Text('SECONDS',
                    style: GoogleFonts.manrope(fontSize: 11, letterSpacing: 2, color: Colors.white38)),
                const SizedBox(height: 32),
                Text('NEXT: SET ${ex.currentSetIndex + 1} OF ${ex.sets.length}',
                    style: GoogleFonts.manrope(fontSize: 13, color: Colors.white54)),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _extendRest,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text('+30s',
                      style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, color: Colors.white70)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _skipRest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text('SKIP',
                      style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, color: AppColors.onPrimary)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // RPE phase
  Widget _buildRpePhase() {
    final ex = _currentExercise;
    return Column(
      children: [
        _topCloseBar(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${ex.exerciseName.toUpperCase()} DONE',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                        fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2, color: AppColors.primary)),
                const SizedBox(height: 20),
                Text('How did that feel?',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 32),
                Text('${ex.rpe}',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 64, fontWeight: FontWeight.w700, color: AppColors.primary)),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: Colors.white12,
                    thumbColor: AppColors.primary,
                    overlayColor: AppColors.primary.withValues(alpha: 0.1),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                  ),
                  child: Slider(
                    value: ex.rpe.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    onChanged: (val) => setState(() => ex.rpe = val.round()),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('EASY',
                        style: GoogleFonts.manrope(fontSize: 9, letterSpacing: 1.5, color: Colors.white38)),
                    Text('MAX EFFORT',
                        style: GoogleFonts.manrope(fontSize: 9, letterSpacing: 1.5, color: Colors.white38)),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _confirmRpeAndAdvance,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: Text(
                _isLastExercise ? 'FINISH WORKOUT →' : 'NEXT EXERCISE →',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.onPrimary),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Silent, looping, chromeless YouTube embed used as the visual anchor for
/// exercises without pose detection support — keeps the camera-first
/// design language even when there's no camera feed to show.
class _LoopingVideo extends StatefulWidget {
  final String youtubeId;
  const _LoopingVideo({required this.youtubeId});

  @override
  State<_LoopingVideo> createState() => _LoopingVideoState();
}

class _LoopingVideoState extends State<_LoopingVideo> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString('''
        <html><body style="margin:0;background:#000;">
        <iframe width="100%" height="100%"
          src="https://www.youtube.com/embed/${widget.youtubeId}?autoplay=1&mute=1&loop=1&playlist=${widget.youtubeId}&controls=0&rel=0&modestbranding=1"
          frameborder="0" allow="autoplay; encrypted-media" allowfullscreen></iframe>
        </body></html>
      ''');
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}
