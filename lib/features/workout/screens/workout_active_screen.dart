import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../data/exercise_data.dart';
import '../services/workout_log_service.dart';
import 'pose_detection_screen.dart';
import 'workout_transition_screen.dart';

/// Which logging interaction style the user is currently using.
///
/// Both modes operate on the exact same [_ExerciseState] / [_SetState]
/// data — only the *presentation and interaction* layer differs. This
/// keeps workout state consistent even if the user switches mode
/// mid-session, since nothing about the underlying data changes.
enum _LoggingMode { manual, automated }

/// Automated-mode state machine per exercise.
///
/// idle      -> nothing running, waiting for user to start the next set
/// working   -> counting down the estimated time to perform the set;
///              reaching zero auto-logs the set as complete
/// resting   -> counting down rest between sets; reaching zero returns
///              to idle for the next set
enum _SetPhase { idle, working, resting }

class WorkoutActiveScreen extends StatefulWidget {
  final Map<String, dynamic> day; // The plan day being worked out

  const WorkoutActiveScreen({super.key, required this.day});

  @override
  State<WorkoutActiveScreen> createState() => _WorkoutActiveScreenState();
}

class _WorkoutActiveScreenState extends State<WorkoutActiveScreen> {
  late List<_ExerciseState> _exerciseStates;
  final DateTime _startedAt = DateTime.now();
  bool _isSaving = false;

  _LoggingMode _mode = _LoggingMode.manual;

  // Only one exercise can run its automated timer at once — this mirrors
  // how a person actually trains (one exercise at a time) and keeps the
  // timer bookkeeping simple: a single Timer, a single "active" exercise.
  Timer? _ticker;
  _ExerciseState? _activeExercise;

  @override
  void initState() {
    super.initState();
    final exercises = (widget.day['exercises'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    _exerciseStates = exercises.map((ex) {
      final sets = ex['sets'] as int? ?? 3;
      final reps = ex['reps'] as int? ?? 10;
      final exerciseName = ex['exerciseName'] as String? ?? '';

      return _ExerciseState(
        exerciseId: ex['exerciseId'] as String? ?? '',
        exerciseName: exerciseName,
        muscleGroup: ex['muscleGroup'] as String? ?? '',
        restSeconds: ex['restSeconds'] as int? ?? 60,
        data: findExerciseByName(exerciseName),
        sets: List.generate(
          sets,
          (i) => _SetState(reps: reps, weightKg: 0),
        ),
      );
    }).toList();

    _loadRecommendedWeights();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Prefills each exercise's sets with the user's last logged weight for
  /// that exact exercise, if one exists. Runs once, after the screen is
  /// already visible with reps/sets, so the UI never blocks on this.
  Future<void> _loadRecommendedWeights() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    for (final ex in _exerciseStates) {
      final lastWeight = await WorkoutLogService().getLastWeightForExercise(
        uid: uid,
        exerciseName: ex.exerciseName,
      );
      if (lastWeight == null) continue;
      if (!mounted) return;
      if (ex.weightManuallySet) continue;
      setState(() {
        for (final set in ex.sets) {
          set.weightKg = lastWeight;
        }
      });
    }
  }

  double get _totalVolume {
    double total = 0;
    for (final ex in _exerciseStates) {
      for (int i = 0; i < ex.sets.length; i++) {
        if (ex.completedSets.contains(i)) {
          total += ex.sets[i].reps * ex.sets[i].weightKg;
        }
      }
    }
    return total;
  }

  bool get _allExercisesDone =>
      _exerciseStates.every((ex) => ex.isFullyComplete);

  int _estimatedSetSeconds(_SetState set) {
    const secondsPerRep = 3;
    const minimumSeconds = 15;
    final estimate = set.reps * secondsPerRep;
    return estimate < minimumSeconds ? minimumSeconds : estimate;
  }

  void _startSet(_ExerciseState ex) {
    if (ex.isFullyComplete) return;
    _ticker?.cancel();

    final setIndex = ex.currentSetIndex;
    final estimate = _estimatedSetSeconds(ex.sets[setIndex]);

    setState(() {
      ex.phase = _SetPhase.working;
      ex.timerSecondsLeft = estimate;
      _activeExercise = ex;
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        ex.timerSecondsLeft--;
        if (ex.timerSecondsLeft <= 0) {
          timer.cancel();
          _logSetComplete(ex);
        }
      });
    });
  }

  void _pauseTimer(_ExerciseState ex) {
    _ticker?.cancel();
    setState(() => ex.phase = _SetPhase.idle);
  }

  void _logSetComplete(_ExerciseState ex) {
    final setIndex = ex.currentSetIndex;
    ex.completedSets.add(setIndex);
    HapticFeedback.lightImpact();

    final hasNextSet = ex.currentSetIndex < ex.sets.length;
    if (hasNextSet) {
      ex.phase = _SetPhase.resting;
      ex.timerSecondsLeft = ex.restSeconds;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() {
          ex.timerSecondsLeft--;
          if (ex.timerSecondsLeft <= 0) {
            timer.cancel();
            ex.phase = _SetPhase.idle;
          }
        });
      });
    } else {
      ex.phase = _SetPhase.idle;
      _ticker?.cancel();
      _activeExercise = null;
    }
  }

  void _extendRest(_ExerciseState ex, {int seconds = 30}) {
    setState(() => ex.timerSecondsLeft += seconds);
  }

  void _skipPhase(_ExerciseState ex) {
    _ticker?.cancel();
    if (ex.phase == _SetPhase.working) {
      _logSetComplete(ex);
    } else {
      setState(() => ex.phase = _SetPhase.idle);
    }
  }

  Future<void> _completeWorkout() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final completedAt = DateTime.now();
    final durationMins = completedAt.difference(_startedAt).inMinutes;
    const uuid = Uuid();

    final exerciseLogs = _exerciseStates.map((ex) {
      return {
        'exerciseLogId': uuid.v4(),
        'exerciseName': ex.exerciseName,
        'muscleGroup': ex.muscleGroup,
        'setsCompleted': ex.completedSets.length,
        'repsCompleted': ex.sets
            .asMap()
            .entries
            .where((e) => ex.completedSets.contains(e.key))
            .map((e) => e.value.reps)
            .fold(0, (a, b) => a + b),
        'weightKg': ex.sets.isNotEmpty ? ex.sets[0].weightKg : 0,
        'rpeScale': ex.rpe,
        'setDetails': ex.sets
            .asMap()
            .entries
            .map((e) => {
                  'setNumber': e.key + 1,
                  'reps': e.value.reps,
                  'weightKg': e.value.weightKg,
                  'completed': ex.completedSets.contains(e.key),
                })
            .toList(),
      };
    }).toList();

    final log = {
      'logId': uuid.v4(),
      'planId': widget.day['planId'] ?? '',
      'dayPlanId': widget.day['dayPlanId'] ?? '',
      'workoutName': widget.day['workoutName'] ?? '',
      'startedAt': _startedAt.toIso8601String(),
      'completedAt': completedAt.toIso8601String(),
      'totalDurationMins': durationMins,
      'totalVolume': _totalVolume,
      'isCompleted': true,
      'exerciseLogs': exerciseLogs,
    };

    await WorkoutLogService().saveWorkoutLog(uid: uid, log: log);

    if (!mounted) return;

    final rpeValues = _exerciseStates.map((ex) => ex.rpe.toDouble()).toList();
    final avgRpe = rpeValues.reduce((a, b) => a + b) / rpeValues.length;
    final maxRpe = rpeValues.reduce((a, b) => a > b ? a : b);

    final totalSets =
        _exerciseStates.map((ex) => ex.sets.length).reduce((a, b) => a + b);
    final completedSets = _exerciseStates
        .map((ex) => ex.completedSets.length)
        .reduce((a, b) => a + b);
    final completionRate = totalSets > 0 ? completedSets / totalSets : 1.0;

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => WorkoutTransitionScreen(
          workoutName: widget.day['workoutName'] as String? ?? '',
          durationMins: durationMins,
          totalVolume: _totalVolume,
          exerciseCount: _exerciseStates.length,
          uid: uid,
          avgRpe: avgRpe,
          maxRpe: maxRpe,
          completionRate: completionRate,
          exerciseLogs: exerciseLogs,
          logId: log['logId'] as String,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildModeToggle(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                itemCount: _exerciseStates.length + 1,
                itemBuilder: (context, index) {
                  if (index == _exerciseStates.length) {
                    return _buildCompleteButton();
                  }
                  return _buildExerciseCard(_exerciseStates[index], index);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final workoutName = widget.day['workoutName'] as String? ?? 'Workout';
    final exerciseCount = _exerciseStates.length;
    final doneCount = _exerciseStates.where((ex) => ex.isFullyComplete).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => _showQuitDialog(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.close_rounded,
                      color: AppColors.onSurface, size: 18),
                ),
              ),
              const Spacer(),
              Text(
                '$doneCount / $exerciseCount DONE',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            workoutName.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: exerciseCount > 0 ? doneCount / exerciseCount : 0,
              backgroundColor: AppColors.surfaceContainerHigh,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
              minHeight: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(child: _modeButton('MANUAL', _LoggingMode.manual)),
            Expanded(child: _modeButton('GUIDED', _LoggingMode.automated)),
          ],
        ),
      ),
    );
  }

  Widget _modeButton(String label, _LoggingMode value) {
    final isSelected = _mode == value;
    return GestureDetector(
      onTap: () {
        if (_mode == _LoggingMode.automated && value == _LoggingMode.manual) {
          _ticker?.cancel();
          if (_activeExercise != null) {
            _activeExercise!.phase = _SetPhase.idle;
          }
        }
        setState(() => _mode = value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color:
                  isSelected ? AppColors.onPrimary : AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExerciseCard(_ExerciseState ex, int exIndex) {
    final canDetectPosture = ex.data?.hasPoseDetection ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border(
          left: BorderSide(
            color: ex.isFullyComplete ? AppColors.primary : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              ex.exerciseName,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurface,
                              ),
                            ),
                          ),
                          if (ex.data != null) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => _openInfoSheet(ex),
                              child: const Icon(Icons.info_outline_rounded,
                                  size: 16, color: AppColors.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        ex.muscleGroup.toUpperCase(),
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_mode == _LoggingMode.manual)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '${ex.restSeconds}s REST',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        color: AppColors.onSurfaceVariant,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: () async {
                    if (!canDetectPosture) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              "Form check isn't available for this exercise yet."),
                        ),
                      );
                      return;
                    }
                    final repsCompleted = await Navigator.of(context).push<int>(
                      MaterialPageRoute(
                        builder: (_) => PoseDetectionScreen(
                          exerciseName: ex.exerciseName,
                          targetReps: ex.sets.isNotEmpty ? ex.sets[0].reps : 10,
                        ),
                      ),
                    );
                    if (repsCompleted != null && repsCompleted > 0) {
                      setState(() {
                        final firstIncomplete = ex.currentSetIndex;
                        if (firstIncomplete < ex.sets.length) {
                          ex.completedSets.add(firstIncomplete);
                        }
                      });
                    }
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: canDetectPosture
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_alt_rounded,
                            color: canDetectPosture
                                ? AppColors.primary
                                : AppColors.onSurfaceVariant,
                            size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'FORM',
                          style: GoogleFonts.manrope(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: canDetectPosture
                                ? AppColors.primary
                                : AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text('SET',
                      style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                          color: AppColors.onSurfaceVariant)),
                ),
                Expanded(
                  child: Text('REPS',
                      style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                          color: AppColors.onSurfaceVariant)),
                ),
                Expanded(
                  child: Text('KG',
                      style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                          color: AppColors.onSurfaceVariant)),
                ),
                const SizedBox(width: 40),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...ex.sets.asMap().entries.map((entry) {
            final setIndex = entry.key;
            final setData = entry.value;
            final isCompleted = ex.completedSets.contains(setIndex);
            final isCurrentInGuidedMode = _mode == _LoggingMode.automated &&
                setIndex == ex.currentSetIndex;

            return _buildSetRow(
              ex: ex,
              setIndex: setIndex,
              setData: setData,
              isCompleted: isCompleted,
              highlightAsCurrent: isCurrentInGuidedMode && !ex.isFullyComplete,
            );
          }),
          if (_mode == _LoggingMode.automated && !ex.isFullyComplete)
            _buildGuidedControls(ex),
          if (ex.isFullyComplete) _buildRpeSlider(ex),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildGuidedControls(_ExerciseState ex) {
    switch (ex.phase) {
      case _SetPhase.idle:
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _startSet(ex),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text(
                'START SET ${ex.currentSetIndex + 1}',
                style: GoogleFonts.spaceGrotesk(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: AppColors.onPrimary,
                ),
              ),
            ),
          ),
        );

      case _SetPhase.working:
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(
                  'SET ${ex.currentSetIndex + 1} IN PROGRESS',
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${ex.timerSecondsLeft}s',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pauseTimer(ex),
                        child: const Text('PAUSE'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _skipPhase(ex),
                        style:
                            ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                        child: Text('LOG NOW',
                            style: TextStyle(color: AppColors.onPrimary)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );

      case _SetPhase.resting:
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(
                  'RESTING',
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${ex.timerSecondsLeft}s',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _extendRest(ex),
                        child: const Text('+30s'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _skipPhase(ex),
                        style:
                            ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                        child: Text('SKIP REST',
                            style: TextStyle(color: AppColors.onPrimary)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
    }
  }

  Widget _buildSetRow({
    required _ExerciseState ex,
    required int setIndex,
    required _SetState setData,
    required bool isCompleted,
    bool highlightAsCurrent = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: highlightAsCurrent
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.5))
              : null,
        ),
        padding: highlightAsCurrent
            ? const EdgeInsets.symmetric(vertical: 2)
            : EdgeInsets.zero,
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: Text(
                '${setIndex + 1}',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color:
                      isCompleted ? AppColors.primary : AppColors.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: _mode == _LoggingMode.manual
                    ? () => _editValue(
                          label: 'Reps',
                          current: setData.reps,
                          onSave: (val) => setState(() => setData.reps = val),
                        )
                    : null,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${setData.reps}',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () => _editValue(
                  label: 'Weight (kg)',
                  current: setData.weightKg.toInt(),
                  onSave: (val) => setState(() {
                    setData.weightKg = val.toDouble();
                    ex.weightManuallySet = true;
                    for (int i = setIndex + 1; i < ex.sets.length; i++) {
                      if (!ex.completedSets.contains(i)) {
                        ex.sets[i].weightKg = val.toDouble();
                      }
                    }
                  }),
                ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    setData.weightKg == 0
                        ? '—'
                        : setData.weightKg.toStringAsFixed(1),
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: setData.weightKg == 0
                          ? AppColors.onSurfaceVariant
                          : AppColors.onSurface,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _mode == _LoggingMode.manual
                  ? () {
                      setState(() {
                        if (isCompleted) {
                          ex.completedSets.remove(setIndex);
                        } else {
                          ex.completedSets.add(setIndex);
                          HapticFeedback.lightImpact();
                        }
                      });
                    }
                  : null,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color:
                        isCompleted ? AppColors.primary : AppColors.outlineVariant,
                  ),
                ),
                child: isCompleted
                    ? const Icon(Icons.check_rounded,
                        size: 18, color: AppColors.primary)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRpeSlider(_ExerciseState ex) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: AppColors.outlineVariant, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'EFFORT LEVEL (RPE)',
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              Text(
                '${ex.rpe}/10',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.surfaceContainerHigh,
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.1),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
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
                  style: GoogleFonts.manrope(
                      fontSize: 9, letterSpacing: 1.5, color: AppColors.onSurfaceVariant)),
              Text('MAX EFFORT',
                  style: GoogleFonts.manrope(
                      fontSize: 9, letterSpacing: 1.5, color: AppColors.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 32),
      child: ElevatedButton(
        onPressed: _allExercisesDone && !_isSaving ? _completeWorkout : null,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              _allExercisesDone ? AppColors.primary : AppColors.surfaceContainerHigh,
          disabledBackgroundColor: AppColors.surfaceContainerHigh,
        ),
        child: _isSaving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
              )
            : Text(
                _allExercisesDone ? 'COMPLETE WORKOUT →' : 'COMPLETE ALL SETS TO FINISH',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: _allExercisesDone ? AppColors.onPrimary : AppColors.onSurfaceVariant,
                ),
              ),
      ),
    );
  }

  Future<void> _editValue({
    required String label,
    required int current,
    required Function(int) onSave,
  }) async {
    final controller = TextEditingController(text: current.toString());

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
            Text(
              label.toUpperCase(),
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '0',
                hintStyle: GoogleFonts.spaceGrotesk(fontSize: 32, color: AppColors.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                final val = int.tryParse(controller.text) ?? current;
                onSave(val);
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

  void _openInfoSheet(_ExerciseState ex) {
    final data = ex.data;
    if (data == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            Text(
              data.name,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              '${data.difficulty.toUpperCase()} · ${data.equipment}',
              style: GoogleFonts.manrope(fontSize: 11, letterSpacing: 1, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => _openVideo(data.youtubeId, data.name),
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                  image: DecorationImage(
                    image: NetworkImage('https://img.youtube.com/vi/${data.youtubeId}/mqdefault.jpg'),
                    fit: BoxFit.cover,
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.play_circle_fill_rounded, size: 48, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'HOW TO PERFORM',
              style: GoogleFonts.manrope(
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            ...data.steps.asMap().entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${entry.key + 1}',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: GoogleFonts.manrope(fontSize: 13, color: AppColors.onSurface, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                )),
            if (data.tips.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'FORM TIPS',
                style: GoogleFonts.manrope(
                    fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              ...data.tips.map((tip) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('•  $tip',
                        style: GoogleFonts.manrope(fontSize: 13, color: AppColors.onSurfaceVariant)),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  void _openVideo(String youtubeId, String title) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString('''
        <html><body style="margin:0;background:#000;">
        <iframe width="100%" height="100%"
          src="https://www.youtube.com/embed/$youtubeId?rel=0&modestbranding=1&autoplay=1"
          frameborder="0" allow="autoplay; encrypted-media" allowfullscreen></iframe>
        </body></html>
      ''');

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: Text(title, style: const TextStyle(color: Colors.white)),
          ),
          body: WebViewWidget(controller: controller),
        ),
      ),
    );
  }

  Future<void> _showQuitDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Quit Workout?',
            style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface, fontWeight: FontWeight.w600)),
        content: Text('Your progress will not be saved.',
            style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Keep Going', style: GoogleFonts.manrope(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Quit',
                style: GoogleFonts.manrope(color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) Navigator.of(context).pop();
  }
}

class _ExerciseState {
  final String exerciseId;
  final String exerciseName;
  final String muscleGroup;
  final int restSeconds;
  final ExerciseData? data;
  final List<_SetState> sets;
  final Set<int> completedSets = {};
  int rpe = 5;
  bool weightManuallySet = false;

  _SetPhase phase = _SetPhase.idle;
  int timerSecondsLeft = 0;

  _ExerciseState({
    required this.exerciseId,
    required this.exerciseName,
    required this.muscleGroup,
    required this.restSeconds,
    required this.sets,
    this.data,
  });

  bool get isFullyComplete => completedSets.length == sets.length;

  int get currentSetIndex {
    for (int i = 0; i < sets.length; i++) {
      if (!completedSets.contains(i)) return i;
    }
    return sets.length;
  }
}

class _SetState {
  int reps;
  double weightKg;

  _SetState({required this.reps, required this.weightKg});
}