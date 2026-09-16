import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/theme/app_colors.dart';
import '../data/exercise_data.dart';
import '../models/active_session_state.dart';
import '../services/workout_log_service.dart';
import 'auto_log_screen.dart';
import 'pose_detection_screen.dart';
import 'workout_transition_screen.dart';

/// The Manual workout screen: a scrollable list of every exercise in the day's plan
class WorkoutActiveScreen extends StatefulWidget {
  final Map<String, dynamic> day; // The plan day being worked out

  const WorkoutActiveScreen({super.key, required this.day});

  @override
  State<WorkoutActiveScreen> createState() => _WorkoutActiveScreenState();
}

class _WorkoutActiveScreenState extends State<WorkoutActiveScreen> {
  late List<ExerciseSessionState> _exerciseStates;
  final DateTime _startedAt = DateTime.now();
  bool _isSaving = false;

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

      return ExerciseSessionState(
        exerciseId: ex['exerciseId'] as String? ?? '',
        exerciseName: exerciseName,
        muscleGroup: findExerciseByName(exerciseName)?.muscleGroup
            ?? ex['muscleGroup'] as String? ?? '',
        restSeconds: ex['restSeconds'] as int? ?? 60,
        // Resolve rich metadata
        data: findExerciseByName(exerciseName),
        sets: List.generate(
          sets,
          (i) => SetSessionState(reps: reps, weightKg: 0),
        ),
      );
    }).toList();

    _loadRecommendedWeights();
  }

  /// Prefills each exercise's sets with the user's last logged weight
  Future<void> _loadRecommendedWeights() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    for (final ex in _exerciseStates) {
      final lastWeight = await WorkoutLogService().getLastWeightForExercise(
        uid: uid,
        exerciseName: ex.exerciseName,
      );
      if (lastWeight == null) continue; // No history — leave blank for user to fill in
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

  /// Launches the full-screen Auto-Log 
  Future<void> _openAutoLog() async {
    final finished = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AutoLogScreen(
          workoutName: widget.day['workoutName'] as String? ?? 'Workout',
          exercises: _exerciseStates,
        ),
      ),
    );
    if (!mounted) return;
    if (finished == true && _allExercisesDone) {
      _completeWorkout();
    } else {
      setState(() {}); // reflect whatever partial progress was made
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

    // Computed here (rather than only later, for the transition screen) so
    // it can also be stored on the top-level log doc — the activity feed
    // reads that doc directly and shouldn't need a subcollection fetch
    // just to show a set count.
    final totalSets =
        _exerciseStates.map((ex) => ex.sets.length).reduce((a, b) => a + b);
    final completedSets = _exerciseStates
        .map((ex) => ex.completedSets.length)
        .reduce((a, b) => a + b);
    final completionRate = totalSets > 0 ? completedSets / totalSets : 1.0;

    // PR detection: for each exercise
    final prExerciseNames = <String>[];
    for (final ex in _exerciseStates) {
      final completedWeights = ex.sets
          .asMap()
          .entries
          .where((e) => ex.completedSets.contains(e.key))
          .map((e) => e.value.weightKg)
          .where((w) => w > 0)
          .toList();
      if (completedWeights.isEmpty) continue;

      final sessionMax = completedWeights.reduce((a, b) => a > b ? a : b);
      final historicalMax = await WorkoutLogService().getMaxWeightForExercise(
        uid: uid,
        exerciseName: ex.exerciseName,
      );

      if (historicalMax != null && sessionMax > historicalMax) {
        prExerciseNames.add(ex.exerciseName);
      }
    }

    final log = {
      'logId': uuid.v4(),
      'planId': widget.day['planId'] ?? '',
      'dayPlanId': widget.day['dayPlanId'] ?? '',
      'workoutName': widget.day['workoutName'] ?? '',
      'startedAt': _startedAt.toIso8601String(),
      'completedAt': completedAt.toIso8601String(),
      'totalDurationMins': durationMins,
      'totalVolume': _totalVolume,
      'totalSetsCompleted': completedSets,
      'prReached': prExerciseNames.isNotEmpty,
      'prExerciseNames': prExerciseNames,
      'isCompleted': true,
      'exerciseLogs': exerciseLogs,
    };

    await WorkoutLogService().saveWorkoutLog(uid: uid, log: log);

    if (!mounted) return;

    final rpeValues = _exerciseStates.map((ex) => ex.rpe.toDouble()).toList();
    final avgRpe = rpeValues.reduce((a, b) => a + b) / rpeValues.length;
    final maxRpe = rpeValues.reduce((a, b) => a > b ? a : b);

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
                itemCount: _exerciseStates.length + 1, // +1 for complete button
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
    final doneCount =
        _exerciseStates.where((ex) => ex.isFullyComplete).length;

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
                  child: const Icon(
                    Icons.close_rounded,
                    color: AppColors.onSurface,
                    size: 18,
                  ),
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

  /// GUIDED navigates into the full-screen Auto-Log flow
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
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    'MANUAL',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: AppColors.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: _openAutoLog,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Center(
                    child: Text(
                      'GUIDED',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseCard(ExerciseSessionState ex, int exIndex) {
    final canDetectPosture = ex.data?.hasPoseDetection ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border(
          left: BorderSide(
            color: ex.isFullyComplete
                ? AppColors.primary
                : Colors.transparent,
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
                              child: const Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: AppColors.onSurfaceVariant,
                              ),
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
                if (canDetectPosture)
                  GestureDetector(
                    onTap: () async {
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.camera_alt_rounded,
                              color: AppColors.primary, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            'FORM',
                            style: GoogleFonts.manrope(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (ex.isFullyComplete) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() => ex.collapsed = !ex.collapsed),
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        ex.collapsed
                            ? Icons.expand_more_rounded
                            : Icons.expand_less_rounded,
                        color: AppColors.onSurfaceVariant,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!ex.collapsed) ...[
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
                  if (ex.tracksWeight) const SizedBox(width: 8),
                  if (ex.tracksWeight)
                    Expanded(
                      child: Text('KG',
                          style: GoogleFonts.manrope(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                              color: AppColors.onSurfaceVariant)),
                    ),
                  const SizedBox(width: 8),
                  const SizedBox(width: 36),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ...ex.sets.asMap().entries.map((entry) {
              final setIndex = entry.key;
              final setData = entry.value;
              final isCompleted = ex.completedSets.contains(setIndex);

              return _buildSetRow(
                ex: ex,
                setIndex: setIndex,
                setData: setData,
                isCompleted: isCompleted,
                isCurrent: !isCompleted && setIndex == ex.currentSetIndex,
              );
            }),
            if (ex.isFullyComplete) _buildRpeSlider(ex),
          ] else
            _buildCollapsedSummary(ex),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  /// Fixed step size for the inline weight +/- buttons.
  static const double _weightIncrement = 2.5;

  Widget _buildCollapsedSummary(ExerciseSessionState ex) {
    final totalVolume = ex.sets
        .asMap()
        .entries
        .where((e) => ex.completedSets.contains(e.key))
        .fold<double>(0, (sum, e) => sum + e.value.reps * e.value.weightKg);

    final summary = ex.tracksWeight
        ? '${ex.sets.length} SETS · ${totalVolume.toStringAsFixed(0)} KG VOLUME · RPE ${ex.rpe}'
        : '${ex.sets.length} SETS COMPLETE · RPE ${ex.rpe}';

    return GestureDetector(
      onTap: () => setState(() => ex.collapsed = false),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                summary,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Applies [weight] to this set, and forward-fills it to any later
  /// not-yet-completed sets — mirrors how lifters actually work a set
  void _applyWeight(ExerciseSessionState ex, int setIndex, double weight) {
    ex.weightManuallySet = true;
    ex.sets[setIndex].weightKg = weight;
    for (int i = setIndex + 1; i < ex.sets.length; i++) {
      if (!ex.completedSets.contains(i)) {
        ex.sets[i].weightKg = weight;
      }
    }
  }

  void _bumpWeight(ExerciseSessionState ex, int setIndex, double delta) {
    final newWeight =
        (ex.sets[setIndex].weightKg + delta).clamp(0, 999).toDouble();
    setState(() => _applyWeight(ex, setIndex, newWeight));
    HapticFeedback.selectionClick();
  }

  Widget _weightStepButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 26,
        height: 36,
        child: Icon(icon, size: 14, color: AppColors.onSurfaceVariant),
      ),
    );
  }

  Widget _buildWeightCell(ExerciseSessionState ex, int setIndex, SetSessionState setData) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _weightStepButton(
            icon: Icons.remove_rounded,
            onTap: () => _bumpWeight(ex, setIndex, -_weightIncrement),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _editWeight(ex, setIndex),
              child: Text(
                setData.weightKg == 0
                    ? '—'
                    : setData.weightKg.toStringAsFixed(1),
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: setData.weightKg == 0
                      ? AppColors.onSurfaceVariant
                      : AppColors.onSurface,
                ),
              ),
            ),
          ),
          _weightStepButton(
            icon: Icons.add_rounded,
            onTap: () => _bumpWeight(ex, setIndex, _weightIncrement),
          ),
        ],
      ),
    );
  }

  Widget _buildSetRow({
    required ExerciseSessionState ex,
    required int setIndex,
    required SetSessionState setData,
    required bool isCompleted,
    required bool isCurrent,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppColors.primary.withValues(alpha: 0.06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '${setIndex + 1}',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: isCompleted
                    ? AppColors.primary
                    : AppColors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _editValue(
                label: 'Reps',
                current: setData.reps,
                onSave: (val) => setState(() => setData.reps = val),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${setData.reps}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: AppColors.onSurface,
                  ),
                ),
              ),
            ),
          ),
          // Weight field — only rendered for exercises that support added load.
          if (ex.tracksWeight) ...[
            const SizedBox(width: 8),
            Expanded(child: _buildWeightCell(ex, setIndex, setData)),
          ],
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              setState(() {
                if (isCompleted) {
                  ex.completedSets.remove(setIndex);
                  ex.collapsed = false;
                } else {
                  ex.completedSets.add(setIndex);
                  HapticFeedback.lightImpact();
                  // Don't auto-collapse here — the RPE slider (below) needs
                  // to stay visible so the user can actually set it; collapse
                  // is triggered instead once they finish dragging the slider
                }
              });
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isCompleted
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isCompleted
                      ? AppColors.primary
                      : AppColors.outlineVariant,
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
    );
  }

  Widget _buildRpeSlider(ExerciseSessionState ex) {
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
                  fontFeatures: const [FontFeature.tabularFigures()],
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
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: ex.rpe.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              onChanged: (val) =>
                  setState(() => ex.rpe = val.round()),
              onChangeEnd: (val) {
                if (!ex.isFullyComplete) return;
                Future.delayed(const Duration(milliseconds: 350), () {
                  if (!mounted) return;
                  setState(() => ex.collapsed = true);
                });
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('EASY',
                  style: GoogleFonts.manrope(
                      fontSize: 9,
                      letterSpacing: 1.5,
                      color: AppColors.onSurfaceVariant)),
              Text('MAX EFFORT',
                  style: GoogleFonts.manrope(
                      fontSize: 9,
                      letterSpacing: 1.5,
                      color: AppColors.onSurfaceVariant)),
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
        onPressed: _allExercisesDone && !_isSaving
            ? _completeWorkout
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _allExercisesDone
              ? AppColors.primary
              : AppColors.surfaceContainerHigh,
          disabledBackgroundColor: AppColors.surfaceContainerHigh,
        ),
        child: _isSaving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.onPrimary),
              )
            : Text(
                _allExercisesDone
                    ? 'COMPLETE WORKOUT →'
                    : 'COMPLETE ALL SETS TO FINISH',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: _allExercisesDone
                      ? AppColors.onPrimary
                      : AppColors.onSurfaceVariant,
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
    final controller =
        TextEditingController(text: current.toString());

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
                hintStyle: GoogleFonts.spaceGrotesk(
                  fontSize: 32,
                  color: AppColors.onSurfaceVariant,
                ),
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
                  style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w700, letterSpacing: 1.5)),
            ),
          ],
        ),
      ),
    );
  }

  /// Weight-specific editor: decimal keyboard, and an explicit "apply to all
  /// sets" toggle for retroactively fixing already-completed sets — the
  /// implicit forward-fill in [_applyWeight] only reaches later, incomplete sets
  Future<void> _editWeight(ExerciseSessionState ex, int setIndex) async {
    final current = ex.sets[setIndex].weightKg;
    final controller = TextEditingController(
      text: current == 0 ? '' : current.toStringAsFixed(1),
    );
    bool applyToAll = false;

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
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
              Text(
                'WEIGHT (KG)',
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: '0',
                  hintStyle: GoogleFonts.spaceGrotesk(
                    fontSize: 32,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
              if (ex.sets.length > 1) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => setSheetState(() => applyToAll = !applyToAll),
                  child: Row(
                    children: [
                      Icon(
                        applyToAll
                            ? Icons.check_box_rounded
                            : Icons.check_box_outline_blank_rounded,
                        size: 20,
                        color: applyToAll
                            ? AppColors.primary
                            : AppColors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Apply to all ${ex.sets.length} sets',
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  final val = double.tryParse(controller.text) ?? current;
                  setState(() {
                    if (applyToAll) {
                      ex.weightManuallySet = true;
                      for (final s in ex.sets) {
                        s.weightKg = val;
                      }
                    } else {
                      _applyWeight(ex, setIndex, val);
                    }
                  });
                  Navigator.pop(sheetContext);
                  if (!applyToAll && setIndex + 1 < ex.sets.length) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Applied to remaining sets'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: Text('SAVE',
                    style: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the media component for the info sheet
  Widget _buildInfoSheetMedia(ExerciseData data) {
    // Case 1: GIF — square media, full animation visible via AspectRatio + contain
    if (data.localGifAsset != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            color: AppColors.surfaceContainerHigh,
            child: Image.asset(
              data.localGifAsset!,
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
    }

    // Case 2: no GIF, but a real YouTube ID — same static thumbnail + play icon as before
    if (data.youtubeId.isNotEmpty) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          image: DecorationImage(
            image: NetworkImage(
                'https://img.youtube.com/vi/${data.youtubeId}/mqdefault.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: const Center(
          child: Icon(Icons.play_circle_fill_rounded,
              size: 48, color: Colors.white),
        ),
      );
    }

    // Case 3: neither — placeholder
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: Icon(Icons.fitness_center_rounded,
            size: 40, color: AppColors.onSurfaceVariant),
      ),
    );
  }

  /// Instructional bottom sheet: steps, tips, and a video link
  void _openInfoSheet(ExerciseSessionState ex) {
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
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${data.difficulty.toUpperCase()} · ${data.equipment}',
              style: GoogleFonts.manrope(
                fontSize: 11,
                letterSpacing: 1,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoSheetMedia(data),
            const SizedBox(height: 20),
            Text(
              'HOW TO PERFORM',
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: AppColors.onSurfaceVariant,
              ),
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
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          entry.value,
                          style: GoogleFonts.manrope(
                              fontSize: 13, color: AppColors.onSurface, height: 1.4),
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
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              ...data.tips.map((tip) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('•  $tip',
                        style: GoogleFonts.manrope(
                            fontSize: 13, color: AppColors.onSurfaceVariant)),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showQuitDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Quit Workout?',
            style: GoogleFonts.spaceGrotesk(
                color: AppColors.onSurface, fontWeight: FontWeight.w600)),
        content: Text('Your progress will not be saved.',
            style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Keep Going',
                style: GoogleFonts.manrope(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Quit',
                style: GoogleFonts.manrope(
                    color: AppColors.error,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) Navigator.of(context).pop();
  }
}