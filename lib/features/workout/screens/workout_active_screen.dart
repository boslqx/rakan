import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/theme/app_colors.dart';
import '../services/workout_log_service.dart';
import 'workout_complete_screen.dart';

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

  @override
  void initState() {
    super.initState();
    final exercises = (widget.day['exercises'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    // Build mutable state for each exercise
    _exerciseStates = exercises.map((ex) {
      final sets = ex['sets'] as int? ?? 3;
      final reps = ex['reps'] as int? ?? 10;

      return _ExerciseState(
        exerciseId: ex['exerciseId'] as String? ?? '',
        exerciseName: ex['exerciseName'] as String? ?? '',
        muscleGroup: ex['muscleGroup'] as String? ?? '',
        restSeconds: ex['restSeconds'] as int? ?? 60,
        // Create one SetState per set, pre-filled with plan reps
        sets: List.generate(
          sets,
          (i) => _SetState(reps: reps, weightKg: 0),
        ),
      );
    }).toList();
  }

  // Total volume = sum of (reps × weight) across all completed sets
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

  Future<void> _completeWorkout() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final completedAt = DateTime.now();
    final durationMins =
        completedAt.difference(_startedAt).inMinutes;
    const uuid = Uuid();

    // Build exercise logs from state
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

    // Compute RPE metrics for fatigue prediction
    final rpeValues = _exerciseStates.map((ex) => ex.rpe.toDouble()).toList();
    final avgRpe = rpeValues.reduce((a, b) => a + b) / rpeValues.length;
    final maxRpe = rpeValues.reduce((a, b) => a > b ? a : b);

    // Total completed sets across all exercises
    final totalSets = _exerciseStates
        .map((ex) => ex.sets.length)
        .reduce((a, b) => a + b);
    final completedSets = _exerciseStates
        .map((ex) => ex.completedSets.length)
        .reduce((a, b) => a + b);
    final completionRate = totalSets > 0 ? completedSets / totalSets : 1.0;

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => WorkoutCompleteScreen(
          workoutName: widget.day['workoutName'] as String? ?? '',
          durationMins: durationMins,
          totalVolume: _totalVolume,
          exerciseCount: _exerciseStates.length,
          uid: uid,
          avgRpe: avgRpe,
          maxRpe: maxRpe,
          completionRate: completionRate,
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
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
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
          // Overall progress bar
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

  Widget _buildExerciseCard(_ExerciseState ex, int exIndex) {
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
          // Exercise header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ex.exerciseName,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
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
                Text(
                  '${ex.restSeconds}s REST',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),

          // Set column headers
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

          // Set rows
          ...ex.sets.asMap().entries.map((entry) {
            final setIndex = entry.key;
            final setData = entry.value;
            final isCompleted = ex.completedSets.contains(setIndex);

            return _buildSetRow(
              ex: ex,
              setIndex: setIndex,
              setData: setData,
              isCompleted: isCompleted,
            );
          }),

          // RPE slider — appears after all sets are done
          if (ex.isFullyComplete) _buildRpeSlider(ex),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildSetRow({
    required _ExerciseState ex,
    required int setIndex,
    required _SetState setData,
    required bool isCompleted,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Row(
        children: [
          // Set number
          SizedBox(
            width: 40,
            child: Text(
              '${setIndex + 1}',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isCompleted
                    ? AppColors.primary
                    : AppColors.onSurfaceVariant,
              ),
            ),
          ),

          // Reps field — tappable to edit
          Expanded(
            child: GestureDetector(
              onTap: () => _editValue(
                label: 'Reps',
                current: setData.reps,
                onSave: (val) =>
                    setState(() => setData.reps = val),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
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

          // Weight field — tappable to edit
          Expanded(
            child: GestureDetector(
              onTap: () => _editValue(
                label: 'Weight (kg)',
                current: setData.weightKg.toInt(),
                onSave: (val) =>
                    setState(() => setData.weightKg = val.toDouble()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  setData.weightKg == 0
                      ? '—'
                      : '${setData.weightKg.toStringAsFixed(1)}',
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

          // Complete set checkbox
          GestureDetector(
            onTap: () {
              setState(() {
                if (isCompleted) {
                  ex.completedSets.remove(setIndex);
                } else {
                  ex.completedSets.add(setIndex);
                  HapticFeedback.lightImpact();
                }
              });
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isCompleted
                    ? AppColors.primary.withOpacity(0.15)
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

  // RPE slider shown after all sets complete
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
              overlayColor: AppColors.primary.withOpacity(0.1),
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

  // Bottom dialog to edit reps or weight
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

// State classes

class _ExerciseState {
  final String exerciseId;
  final String exerciseName;
  final String muscleGroup;
  final int restSeconds;
  final List<_SetState> sets;
  final Set<int> completedSets = {};
  int rpe = 5;

  _ExerciseState({
    required this.exerciseId,
    required this.exerciseName,
    required this.muscleGroup,
    required this.restSeconds,
    required this.sets,
  });

  bool get isFullyComplete => completedSets.length == sets.length;
}

class _SetState {
  int reps;
  double weightKg;

  _SetState({required this.reps, required this.weightKg});
}