import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../data/exercise_data.dart';
import '../models/active_session_state.dart';
import '../services/pose_service.dart';
import '../services/angle_calculator.dart';
import '../widgets/elapsed_time_text.dart';
import '../widgets/exercise_media.dart';
import '../widgets/pose_countdown_overlay.dart';
import '../widgets/session_hud.dart';
import 'pose_detection_screen.dart';
import '../../../shared/utils/number_format.dart';
import '../../../shared/widgets/pressable.dart';


enum _ScreenPhase { ready, active, resting, rpe }

/// Guided mode: walks the session one set at a time — brief, set up, do the
/// set (camera rep-counting where supported), rest, rate, next exercise.
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

  // Rest timer. _restTotal drives the ring and grows with +30s.
  Timer? _restTicker;
  int _restTotal = 0;

  // The set in progress: when it started (sets logged by hand show a
  // running clock) and how many reps to log for it.
  DateTime _setStartedAt = DateTime.now();
  int _repsDone = 0;

  /// The set most recently logged — the rest screen confirms it.
  int? _lastLoggedSet;

  // Camera / pose detection state (mirrors PoseDetectionScreen)
  StreamSubscription? _poseSubscription;
  List<Landmark> _landmarks = [];
  bool _poseDetected = false;
  PostureResult? _lastResult;
  late PostureAnalyser _analyser;
  int _repCount = 0;
  int _frameWidth = 640;
  int _frameHeight = 480;
  int _frameRotation = 0;

  bool _permissionGranted = false;

  // Countdown state
  bool _countingDown = true;

  /// True while the "log this set" sheet is open — camera frames are
  /// ignored so a late rep can't auto-finish the set underneath it.
  bool _confirmingSet = false;

  /// Fixed step size for the weight +/- buttons (same as Manual mode).
  static const double _weightIncrement = 2.5;

  ExerciseSessionState get _currentExercise => widget.exercises[_exerciseIndex];

  /// The next exercise after this one that still has sets to do, if any.
  int? get _nextExerciseIndex {
    for (int i = _exerciseIndex + 1; i < widget.exercises.length; i++) {
      if (!widget.exercises[i].isFullyComplete) return i;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();

    if (!_skipToNextIncompleteExercise()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
      return;
    }

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

  /// Camera set-up lines for an exercise ("Place phone…", "Stand…"), minus
  /// the leading emoji — the UI draws its own icons.
  static List<String> _setupLines(String exerciseName) =>
      ExerciseAnalyserFactory.getInstructions(exerciseName)
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'^[^A-Za-z0-9]+'), '').trim())
          .where((l) => l.isNotEmpty)
          .toList();

  /// Advances _exerciseIndex forward past any exercises that are already
  /// fully complete (all sets logged via Manual mode). Returns true if a
  /// valid, incomplete exercise was found and set as current; returns false
  /// if every remaining exercise is already complete.
  bool _skipToNextIncompleteExercise() {
    while (_exerciseIndex < widget.exercises.length) {
      final ex = widget.exercises[_exerciseIndex];
      if (ex.currentSetIndex < ex.sets.length) {
        return true;
      }
      _exerciseIndex++;
    }
    return false;
  }

  // Starting a set
  void _startSet() {
    final ex = _currentExercise;
    _setStartedAt = DateTime.now();
    _repsDone = ex.sets[ex.currentSetIndex].reps;
    if (_currentExerciseCanUseCamera) {
      _analyser = ExerciseAnalyserFactory.getAnalyser(ex.exerciseName);
      _repCount = 0;
      _poseDetected = false;
      _landmarks = [];
      _lastResult = null;
      _countingDown = true; // NEW — every set re-arms the countdown
      _startPoseStream();
    }
    HapticFeedback.lightImpact();
    setState(() => _phase = _ScreenPhase.active);
  }

  void _startPoseStream() {
    _poseSubscription?.cancel();
    _poseSubscription =
        PoseService.getLandmarkStream(_currentExercise.exerciseName).listen(
      (data) {
        if (!mounted || _confirmingSet) return;
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

        // Same gate as PoseDetectionScreen: show the skeleton, never touch
        // the analyser while counting down.
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

        setState(() {
          _poseDetected = true;
          _landmarks = landmarks;
          _lastResult = result;
          _frameWidth = (data['frameWidth'] as int?) ?? 640;
          _frameHeight = (data['frameHeight'] as int?) ?? 480;
          _frameRotation = (data['frameRotation'] as int?) ?? 0;

          if (result.countRep) {
            _repCount = _analyser.repCount;
            HapticFeedback.lightImpact();

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
    _lastLoggedSet = setIndex;
    HapticFeedback.mediumImpact();

    if (!ex.isFullyComplete) {
      _startRest(ex.restSeconds);
    } else {
      setState(() => _phase = _ScreenPhase.rpe);
    }
  }

  /// Ending a camera set by hand means the count fell short of the target —
  /// often because the camera missed a rep. Confirm the number first, so a
  /// miscount (or a 0) isn't logged silently.
  Future<void> _finishCameraSetEarly() async {
    final counted = _repCount;
    final target = _currentExercise.sets[_currentExercise.currentSetIndex].reps;
    var reps = counted > 0 ? counted : target;

    _confirmingSet = true;
    final logged = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          void bump(int delta) {
            HapticFeedback.selectionClick();
            setSheetState(() => reps = (reps + delta).clamp(1, 100));
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
                24, 24, 24, MediaQuery.of(sheetContext).viewPadding.bottom + 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('LOG THIS SET',
                    style: _label(fontSize: 11, color: AppColors.onSurfaceVariant)),
                const SizedBox(height: 8),
                Text(
                  counted > 0
                      ? 'The camera counted $counted of $target. Missed any? Adjust before logging.'
                      : "The camera didn't count any reps — enter what you did.",
                  style: GoogleFonts.manrope(
                      fontSize: 14, height: 1.4, color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                _StepperCard(
                  label: 'REPS DONE',
                  value: '$reps',
                  onMinus: () => bump(-1),
                  onPlus: () => bump(1),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.pop(sheetContext, reps),
                  child: Text('LOG $reps REPS',
                      style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.w700, letterSpacing: 1.5)),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (!mounted) return;
    _confirmingSet = false;
    if (logged != null) _finishSet(actualReps: logged);
  }

  void _startRest(int seconds) {
    _restTicker?.cancel();
    if (seconds <= 0) {
      setState(() => _phase = _ScreenPhase.ready);
      return;
    }
    setState(() {
      _phase = _ScreenPhase.resting;
      _restTotal = seconds;
      _currentExercise.timerSecondsLeft = seconds;
    });
    _restTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _currentExercise.timerSecondsLeft--;
        final left = _currentExercise.timerSecondsLeft;
        if (left <= 0) {
          timer.cancel();
          _phase = _ScreenPhase.ready;
        }
      });
      // Countdown cue for the last seconds, then a firm buzz: the phone may
      // be across the room or face-down on the bench.
      final left = _currentExercise.timerSecondsLeft;
      if (left <= 0) {
        HapticFeedback.heavyImpact();
      } else if (left <= 3) {
        HapticFeedback.selectionClick();
      }
    });
  }

  void _extendRest({int seconds = 30}) {
    HapticFeedback.selectionClick();
    setState(() {
      _currentExercise.timerSecondsLeft += seconds;
      _restTotal += seconds;
    });
  }

  void _skipRest() {
    _restTicker?.cancel();
    setState(() => _phase = _ScreenPhase.ready);
  }

  void _confirmRpeAndAdvance() {
    // The guided flow always shows the RPE step, so pressing on counts as
    // a rating even if the slider was left at its default.
    _currentExercise.rpeRated = true;
    if (_exerciseIndex + 1 < widget.exercises.length) {
      _exerciseIndex++;
    } else {
      _exerciseIndex = widget.exercises.length;
    }

    if (!_skipToNextIncompleteExercise()) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
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

  // Reps / weight adjustments — always for the next set to be done

  void _bumpReps(int delta) {
    final ex = _currentExercise;
    final set = ex.sets[ex.currentSetIndex];
    setState(() => set.reps = (set.reps + delta).clamp(1, 100));
    HapticFeedback.selectionClick();
  }

  /// Applies [weight] to the next set and forward-fills the remaining,
  /// not-yet-completed sets — same rule as Manual mode, so switching modes
  /// stays consistent.
  void _applyWeight(double weight) {
    final ex = _currentExercise;
    final setIndex = ex.currentSetIndex;
    ex.weightManuallySet = true;
    ex.sets[setIndex].weightKg = weight;
    for (int i = setIndex + 1; i < ex.sets.length; i++) {
      if (!ex.completedSets.contains(i)) {
        ex.sets[i].weightKg = weight;
      }
    }
  }

  void _bumpWeight(double delta) {
    final ex = _currentExercise;
    final current = ex.sets[ex.currentSetIndex].weightKg;
    setState(() => _applyWeight((current + delta).clamp(0, 999).toDouble()));
    HapticFeedback.selectionClick();
  }

  // Weight quick-edit
  Future<void> _editWeight() async {
    final ex = _currentExercise;
    final setIndex = ex.currentSetIndex;
    if (setIndex >= ex.sets.length) return;
    final current = ex.sets[setIndex].weightKg;
    final controller =
        TextEditingController(text: current == 0 ? '' : formatKg(current));

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 32,
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.onSurface),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '0',
                hintStyle: GoogleFonts.spaceGrotesk(
                    fontSize: 32, color: AppColors.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final val = double.tryParse(controller.text) ?? current;
                setState(() => _applyWeight(val));
                Navigator.pop(sheetContext);
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
    // initState found nothing left to do and pops on the next frame.
    if (_exerciseIndex >= widget.exercises.length) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    final ex = _currentExercise;
    final onCamera =
        _phase == _ScreenPhase.active && _currentExerciseCanUseCamera;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _quit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (current, previous) => Stack(
              fit: StackFit.expand,
              children: [...previous, ?current],
            ),
            transitionBuilder: (child, animation) {
              // The camera preview is a platform view — keep it out of
              // opacity layers; the next phase simply fades in over it.
              if (child.key == const ValueKey('camera')) return child;
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.025),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: onCamera
                  ? const ValueKey('camera')
                  : ValueKey('${_phase.name}-$_exerciseIndex-${ex.currentSetIndex}'),
              child: switch (_phase) {
                _ScreenPhase.ready => _buildReadyPhase(),
                _ScreenPhase.active => onCamera
                    ? _buildCameraPhase()
                    : _buildVideoFallbackPhase(),
                _ScreenPhase.resting => _buildRestPhase(),
                _ScreenPhase.rpe => _buildRpePhase(),
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Quit, where you are in the session (one segment per exercise), and an
  /// optional status pill on the right.
  Widget _buildTopBar({Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          Pressable(
            onTap: _quit,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'EXERCISE ${_exerciseIndex + 1} OF ${widget.exercises.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _label(color: Colors.white54),
                ),
                const SizedBox(height: 7),
                SegmentedProgress(
                  values: [
                    for (final ex in widget.exercises)
                      ex.sets.isEmpty
                          ? 0
                          : ex.completedSets.length / ex.sets.length,
                  ],
                  highlighted: _exerciseIndex,
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 14),
            trailing,
          ],
        ],
      ),
    );
  }

  // READY phase — brief the set: demo, targets, camera set-up.
  Widget _buildReadyPhase() {
    final ex = _currentExercise;
    final setIndex = ex.currentSetIndex;
    final set = ex.sets[setIndex];
    final data = ex.data;
    final gif = data?.localGifAsset;
    final muscles = [
      if (ex.muscleGroup.isNotEmpty) ex.muscleGroup,
      ...?data?.secondaryMuscles.take(2),
    ];

    return Column(
      children: [
        _buildTopBar(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (gif != null)
                  ExerciseDemoPanel(
                    gifAsset: gif,
                    title: ex.exerciseName,
                    badge: '${_exerciseIndex + 1} / ${widget.exercises.length}',
                    heroTag: 'guided-demo-$_exerciseIndex',
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
                Row(
                  children: [
                    Text(
                      'SET ${setIndex + 1} OF ${ex.sets.length}',
                      style: _label(fontSize: 12, letterSpacing: 2, color: AppColors.primary),
                    ),
                    const Spacer(),
                    SetDots(total: ex.sets.length, completed: ex.completedSets),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  ex.exerciseName,
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
                      style: _label(fontSize: 11, color: Colors.white38)),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: _StepperCard(
                        label: 'TARGET REPS',
                        value: '${set.reps}',
                        onMinus: () => _bumpReps(-1),
                        onPlus: () => _bumpReps(1),
                      ),
                    ),
                    if (ex.tracksWeight) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StepperCard(
                          label: 'WEIGHT · KG',
                          value: set.weightKg == 0 ? '—' : formatKg(set.weightKg),
                          onMinus: () => _bumpWeight(-_weightIncrement),
                          onPlus: () => _bumpWeight(_weightIncrement),
                          onTapValue: _editWeight,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                _buildSetupNote(ex),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: _primaryButton(
            icon: _currentExerciseCanUseCamera
                ? Icons.videocam_rounded
                : Icons.play_arrow_rounded,
            label: 'START SET',
            onPressed: _startSet,
          ),
        ),
      ],
    );
  }

  /// Camera exercises: where to put the phone and how to stand, before the
  /// set starts. Otherwise, why there's no rep counting this time.
  Widget _buildSetupNote(ExerciseSessionState ex) {
    final hasPose = ex.data?.hasPoseDetection ?? false;

    if (hasPose && _permissionGranted) {
      final lines = _setupLines(ex.exerciseName);
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const LivePulseDot(color: Colors.greenAccent, size: 6),
                const SizedBox(width: 4),
                Text('FORM CHECK ON', style: _label(color: Colors.white70)),
                const Spacer(),
                Flexible(
                  child: Text('AUTO REP COUNT',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _label(fontSize: 9, color: Colors.white38)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (int i = 0; i < lines.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      i == 0
                          ? Icons.phone_android_rounded
                          : Icons.accessibility_new_rounded,
                      size: 16,
                      color: Colors.white54,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        lines[i],
                        style: GoogleFonts.manrope(
                            fontSize: 12.5, height: 1.4, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.videocam_off_rounded, size: 16, color: Colors.white54),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasPose
                  ? "Camera access is off, so reps won't be counted — do your set, then log it."
                  : 'No camera tracking for this exercise — follow the demo, then log your set.',
              style: GoogleFonts.manrope(fontSize: 12, height: 1.4, color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  // ACTIVE phase (camera). Built to be read from 2–3m away: a big rep ring,
  // and the whole screen edge glowing with form quality.
  Widget _buildCameraPhase() {
    final ex = _currentExercise;
    final target = ex.sets[ex.currentSetIndex].reps;
    final tracking = _poseDetected && !_countingDown;
    final result = tracking ? _lastResult : null;
    final glow = result == null
        ? Colors.transparent
        : (result.isCorrect ? Colors.greenAccent : Colors.redAccent)
            .withValues(alpha: 0.75);
    final phaseLabel = result == null ? null : _phaseLabel(result.phase);

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
        // Form glow around the whole screen — readable from across the
        // room, where the feedback text isn't.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              decoration: BoxDecoration(border: Border.all(color: glow, width: 6)),
            ),
          ),
        ),
        // Scrims so the HUD stays legible over a bright room.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 260,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 240,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        if (!_poseDetected && !_countingDown)
          Positioned.fill(child: _buildFramingGuide(ex)),
        if (_countingDown)
          Positioned.fill(
            child: PoseCountdownOverlay(
              hints: _setupLines(ex.exerciseName),
              onComplete: () => setState(() => _countingDown = false),
            ),
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildTopBar(trailing: _buildTrackingPill()),
        ),
        if (!_countingDown)
          Positioned(
            top: 76,
            left: 0,
            right: 0,
            child: Column(
              children: [
                _RepRing(count: _repCount, target: target),
                if (phaseLabel != null) ...[
                  const SizedBox(height: 10),
                  _pill(
                    child: Text(phaseLabel,
                        style: _label(fontSize: 11, letterSpacing: 2, color: Colors.white)),
                  ),
                ],
              ],
            ),
          ),
        if (result != null)
          Positioned(
            bottom: 96,
            left: 20,
            right: 20,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: (result.isCorrect ? Colors.green : AppColors.error)
                    .withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Icon(
                      result.isCorrect
                          ? Icons.check_circle_rounded
                          : Icons.warning_rounded,
                      color: Colors.white,
                      size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(result.feedback,
                        style: GoogleFonts.manrope(
                            fontSize: 16,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          bottom: 24,
          left: 20,
          right: 20,
          child: OutlinedButton(
            onPressed: _finishCameraSetEarly,
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.black38,
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

  /// 'going_down' → 'GOING DOWN'. Null for frames the analyser couldn't read.
  static String? _phaseLabel(String phase) {
    if (phase.isEmpty || phase == 'unknown') return null;
    return phase.replaceAll('_', ' ').toUpperCase();
  }

  Widget _buildTrackingPill() {
    final tracking = _poseDetected && !_countingDown;
    final label = _countingDown
        ? 'GET READY'
        : tracking
            ? 'TRACKING'
            : 'SEARCHING';
    return _pill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LivePulseDot(
            size: 6,
            color: tracking ? Colors.greenAccent : Colors.white38,
          ),
          const SizedBox(width: 3),
          Text(label, style: _label(color: Colors.white70)),
        ],
      ),
    );
  }

  /// Shown while no body is detected: what to do about it.
  Widget _buildFramingGuide(ExerciseSessionState ex) {
    final lines = _setupLines(ex.exerciseName);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 120), // clear of the rep ring
            const Icon(Icons.accessibility_new_rounded, color: Colors.white38, size: 64),
            const SizedBox(height: 12),
            Text("Can't see you yet",
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 6),
            Text(
              lines.length > 1 ? lines[1] : 'Step back so your whole body is in frame.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 13, height: 1.4, color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }

  // ACTIVE phase (no camera): looping demo, set clock, log what you did.
  Widget _buildVideoFallbackPhase() {
    final ex = _currentExercise;
    final setIndex = ex.currentSetIndex;
    final set = ex.sets[setIndex];
    final data = ex.data;
    final target = [
      'TARGET ${set.reps} REPS',
      if (ex.tracksWeight && set.weightKg > 0) '${formatKg(set.weightKg)} KG',
    ].join(' · ');

    return Column(
      children: [
        _buildTopBar(
          trailing: _pill(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_outlined, size: 13, color: Colors.white54),
                const SizedBox(width: 5),
                ElapsedTimeText(
                  startedAt: _setStartedAt,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: ColoredBox(
                color: Colors.white,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    data != null
                        ? _buildLoopingMedia(data)
                        : const Icon(Icons.fitness_center_rounded,
                            size: 48, color: Colors.black26),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: _pill(
                        child: Text('SET ${setIndex + 1} / ${ex.sets.length}',
                            style: _label(fontSize: 11, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              Text(
                ex.exerciseName,
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(target, style: _label(fontSize: 11, letterSpacing: 1.2, color: Colors.white54)),
              const SizedBox(height: 14),
              _StepperCard(
                label: 'REPS DONE',
                value: '$_repsDone',
                onMinus: () {
                  HapticFeedback.selectionClick();
                  setState(() => _repsDone = math.max(1, _repsDone - 1));
                },
                onPlus: () {
                  HapticFeedback.selectionClick();
                  setState(() => _repsDone = math.min(100, _repsDone + 1));
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: _primaryButton(
            icon: Icons.check_rounded,
            label: 'LOG SET',
            onPressed: () => _finishSet(actualReps: _repsDone),
          ),
        ),
      ],
    );
  }

  Widget _buildLoopingMedia(ExerciseData data) {
    if (data.localGifAsset != null) {
      return Image.asset(
        data.localGifAsset!,
        fit: BoxFit.contain,
        // gaplessPlayback avoids a flash to nothing when Flutter briefly
        // rebuilds this widget (e.g. on a hot state change) — animated
        // GIFs otherwise restart from frame 1 on every rebuild.
        gaplessPlayback: true,
      );
    }
    if (data.youtubeId.isNotEmpty) {
      return _LoopingVideo(youtubeId: data.youtubeId);
    }
    return const Icon(Icons.fitness_center_rounded, size: 48, color: Colors.black26);
  }

  // RESTING phase — confirm the set, count down, prep the next one.
  Widget _buildRestPhase() {
    final ex = _currentExercise;
    final left = math.max(0, ex.timerSecondsLeft);
    final progress = _restTotal > 0 ? (left / _restTotal).clamp(0.0, 1.0) : 0.0;
    final logged = _lastLoggedSet;
    final tips = ex.data?.tips ?? const <String>[];
    // A different tip each rest.
    final tip = tips.isEmpty ? null : tips[(ex.completedSets.length - 1) % tips.length];

    return Column(
      children: [
        _buildTopBar(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    if (logged != null && logged < ex.sets.length)
                      Center(
                        child: _pill(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  size: 14, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Text(
                                'SET ${logged + 1} LOGGED · ${ex.sets[logged].reps} REPS',
                                style: _label(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Center(child: _RestRing(secondsLeft: left, progress: progress)),
                    const SizedBox(height: 28),
                    if (tip != null) ...[
                      _buildTipCard(tip),
                      const SizedBox(height: 10),
                    ],
                    _buildNextSetCard(ex),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
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
                  child: Text('SKIP REST',
                      style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.onPrimary)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTipCard(String tip) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline_rounded, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('FORM TIP', style: _label(fontSize: 9, color: Colors.white38)),
                const SizedBox(height: 4),
                Text(tip,
                    style: GoogleFonts.manrope(fontSize: 13, height: 1.4, color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The set after this rest — with its weight adjustable right here, the
  /// moment lifters usually decide to go up or down.
  Widget _buildNextSetCard(ExerciseSessionState ex) {
    final set = ex.sets[ex.currentSetIndex];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ExerciseThumb(asset: ex.data?.thumbnailAsset, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('UP NEXT', style: _label(fontSize: 9, color: Colors.white38)),
                    const SizedBox(height: 2),
                    Text(ex.exerciseName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                    const SizedBox(height: 2),
                    Text(
                      'Set ${ex.currentSetIndex + 1} of ${ex.sets.length} · ${set.reps} reps',
                      style: GoogleFonts.manrope(fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (ex.tracksWeight) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: Colors.white10),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('WEIGHT · KG', style: _label(fontSize: 9, color: Colors.white38)),
                const Spacer(),
                _StepButton(icon: Icons.remove_rounded, onTap: () => _bumpWeight(-_weightIncrement)),
                SizedBox(
                  width: 72,
                  child: Pressable(
                    onTap: _editWeight,
                    child: Text(
                      set.weightKg == 0 ? '—' : formatKg(set.weightKg),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                _StepButton(icon: Icons.add_rounded, onTap: () => _bumpWeight(_weightIncrement)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _rpeDescriptor(int rpe) {
    if (rpe <= 2) return 'VERY EASY';
    if (rpe <= 4) return 'EASY';
    if (rpe <= 6) return 'MODERATE';
    if (rpe <= 8) return 'HARD';
    if (rpe == 9) return 'VERY HARD';
    return 'MAX EFFORT';
  }

  // RPE phase — celebrate the exercise, rate it, preview what's next.
  Widget _buildRpePhase() {
    final ex = _currentExercise;
    final nextIndex = _nextExerciseIndex;
    final next = nextIndex == null ? null : widget.exercises[nextIndex];
    final reps = ex.completedSets.fold<int>(0, (sum, i) => sum + ex.sets[i].reps);
    final volume = ex.completedSets
        .fold<double>(0, (sum, i) => sum + ex.sets[i].reps * ex.sets[i].weightKg);

    return Column(
      children: [
        _buildTopBar(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.4, end: 1),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.elasticOut,
                  builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, size: 34, color: AppColors.primary),
                  ),
                ),
                const SizedBox(height: 14),
                Text('${ex.exerciseName.toUpperCase()} COMPLETE',
                    textAlign: TextAlign.center,
                    style: _label(fontSize: 12, letterSpacing: 2, color: AppColors.primary)),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: _summaryTile('${ex.completedSets.length}', 'SETS')),
                    const SizedBox(width: 8),
                    Expanded(child: _summaryTile('$reps', 'REPS')),
                    if (ex.tracksWeight && volume > 0) ...[
                      const SizedBox(width: 8),
                      Expanded(child: _summaryTile(formatThousands(volume), 'KG VOLUME')),
                    ],
                  ],
                ),
                const SizedBox(height: 30),
                Text('How hard was that?',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 12),
                Text.rich(
                  TextSpan(
                    text: '${ex.rpe}',
                    children: [
                      TextSpan(
                        text: '/10',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white38),
                      ),
                    ],
                  ),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 64,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: AppColors.primary,
                  ),
                ),
                Text(_rpeDescriptor(ex.rpe),
                    style: _label(fontSize: 12, letterSpacing: 2, color: Colors.white70)),
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: Colors.white12,
                    thumbColor: AppColors.primary,
                    overlayColor: AppColors.primary.withValues(alpha: 0.1),
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                  ),
                  child: Slider(
                    value: ex.rpe.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    onChanged: (val) {
                      if (val.round() != ex.rpe) HapticFeedback.selectionClick();
                      setState(() {
                        ex.rpe = val.round();
                        ex.rpeRated = true;
                      });
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('EASY', style: _label(fontSize: 9, color: Colors.white38)),
                    Text('MAX EFFORT', style: _label(fontSize: 9, color: Colors.white38)),
                  ],
                ),
                if (next != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        ExerciseThumb(asset: next.data?.thumbnailAsset, size: 48),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('UP NEXT', style: _label(fontSize: 9, color: Colors.white38)),
                              const SizedBox(height: 2),
                              Text(next.exerciseName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                              const SizedBox(height: 2),
                              Text(
                                '${next.sets.length} × ${next.sets.isEmpty ? 0 : next.sets.first.reps}'
                                '${next.muscleGroup.isEmpty ? '' : ' · ${next.muscleGroup}'}',
                                style: GoogleFonts.manrope(fontSize: 12, color: Colors.white54),
                              ),
                            ],
                          ),
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
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: _primaryButton(
            icon: next == null ? Icons.flag_rounded : Icons.arrow_forward_rounded,
            label: next == null ? 'FINISH WORKOUT' : 'NEXT EXERCISE',
            onPressed: _confirmRpeAndAdvance,
          ),
        ),
      ],
    );
  }

  Widget _summaryTile(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, style: _label(fontSize: 9, color: Colors.white38)),
          ),
        ],
      ),
    );
  }

  Widget _primaryButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppColors.onPrimary),
            const SizedBox(width: 8),
            Text(
              label,
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
    );
  }

  /// Dark translucent pill — reads over camera, photos and the white demo.
  Widget _pill({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: child,
    );
  }

  TextStyle _label({
    double fontSize = 10,
    double letterSpacing = 1.5,
    Color color = Colors.white54,
  }) {
    return GoogleFonts.manrope(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: letterSpacing,
      color: color,
    );
  }
}

/// Rep count inside a ring that fills toward the target; each new rep pops
/// in. Sized to read from where the phone is propped, metres away.
class _RepRing extends StatelessWidget {
  final int count;
  final int target;

  const _RepRing({required this.count, required this.target});

  @override
  Widget build(BuildContext context) {
    final progress = target > 0 ? (count / target).clamp(0.0, 1.0) : 0.0;

    return SizedBox.square(
      dimension: 168,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.55),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(5),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: progress),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              builder: (_, value, _) => CircularProgressIndicator(
                value: value,
                strokeWidth: 8,
                strokeCap: StrokeCap.round,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: Text(
                    '$count',
                    key: ValueKey(count),
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 72,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'OF $target REPS',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Big rest countdown: a ring that drains as the seconds tick off.
class _RestRing extends StatelessWidget {
  final int secondsLeft;
  final double progress;

  const _RestRing({required this.secondsLeft, required this.progress});

  @override
  Widget build(BuildContext context) {
    final m = secondsLeft ~/ 60;
    final s = (secondsLeft % 60).toString().padLeft(2, '0');

    return SizedBox.square(
      dimension: 200,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // A short tick per second rather than a continuous glide, so a
          // rest doesn't redraw at 60fps the whole time.
          TweenAnimationBuilder<double>(
            tween: Tween(end: progress),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (_, value, _) => CircularProgressIndicator(
              value: value,
              strokeWidth: 10,
              strokeCap: StrokeCap.round,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'REST',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 3,
                    color: Colors.white38,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$m:$s',
                  semanticsLabel: '$secondsLeft seconds of rest left',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 54,
                    height: 1.05,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A value with −/+ either side; tap the value itself for exact entry when
/// [onTapValue] is given.
class _StepperCard extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback? onTapValue;

  const _StepperCard({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
    this.onTapValue,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: Colors.white38,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _StepButton(icon: Icons.remove_rounded, onTap: onMinus),
              Expanded(
                child: Pressable(
                  onTap: onTapValue,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              _StepButton(icon: Icons.add_rounded, onTap: onPlus),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.9,
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: Colors.white10,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: Colors.white70),
      ),
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
