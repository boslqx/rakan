import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../../onboarding/services/user_profile_service.dart';
import '../data/exercise_data.dart';
import '../services/workout_log_service.dart';
import '../services/workout_plan_service.dart';
import '../widgets/exercise_media.dart';
import 'workout_active_screen.dart';
import 'workout_log_detail_screen.dart';
import '../../../shared/widgets/pressable.dart';

/// Editable version of the "workout preview" layout, opened from the
/// Schedule tab when a day is tapped (replacing the old bottom sheet).
///
/// Deliberately a separate screen from [WorkoutPreviewScreen] rather than
/// adding editing controls to it: WorkoutPreviewScreen's job is a quick,
/// read-only "about to start right now" confirmation (used from Home) —
/// cluttering that moment with add/remove/reorder controls would slow
/// down the common case. This screen takes over the "browse and plan
/// ahead" job for the Schedule tab instead, and — since it already shows
/// everything WorkoutPreviewScreen does — starting a workout from here
/// jumps straight to WorkoutActiveScreen rather than routing through
/// WorkoutPreviewScreen a second time.
class WorkoutDayDetailScreen extends StatefulWidget {
  final Map<String, dynamic> day;
  final String planId;

  const WorkoutDayDetailScreen({
    super.key,
    required this.day,
    required this.planId,
  });

  @override
  State<WorkoutDayDetailScreen> createState() => _WorkoutDayDetailScreenState();
}

class _WorkoutDayDetailScreenState extends State<WorkoutDayDetailScreen> {
  late List<Map<String, dynamic>> _exercises;
  late int _durationMinutes;
  bool _isMutating = false;

  Map<String, dynamic>? _completedLog;
  bool _loadingStatus = true;

  bool get _isToday => widget.day['dayNumber'] == DateTime.now().weekday;

  /// This week's actual calendar date for widget.day's weekday (Mon=1..Sun=7,
  /// same convention as DateTime.weekday) — needed to look up whether that
  /// occurrence was logged or, if its day already passed, went unlogged.
  DateTime get _scheduledDateThisWeek {
    final today = DateTime.now();
    final dayNumber = widget.day['dayNumber'] as int? ?? today.weekday;
    return DateTime(today.year, today.month, today.day)
        .add(Duration(days: dayNumber - today.weekday));
  }

  bool get _isPastThisWeek => _scheduledDateThisWeek
      .isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day));

  bool get _isCompleted => _completedLog != null;

  String get _dayId => widget.day['id'] as String;

  Set<String> get _exerciseNames =>
      {for (final ex in _exercises) ex['exerciseName'] as String? ?? ''};

  int get _totalSets => _exercises.fold<int>(
      0, (sum, ex) => sum + ((ex['sets'] as num?)?.toInt() ?? 0));

  @override
  void initState() {
    super.initState();
    _exercises = List<Map<String, dynamic>>.from(
      (widget.day['exercises'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    );
    _durationMinutes = widget.day['durationMinutes'] as int? ?? 0;
    _loadCompletionStatus();
  }

  /// Checks whether this week's occurrence of this day was already logged —
  /// gates re-initiating a workout that's done, and labels past, unlogged
  /// days as skipped rather than silently offering "start" on a day that's
  /// already gone
  Future<void> _loadCompletionStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loadingStatus = false);
      return;
    }
    final log = await WorkoutLogService().getLogForDate(
      uid: uid,
      date: _scheduledDateThisWeek,
    );
    if (!mounted) return;
    setState(() {
      _completedLog = log;
      _loadingStatus = false;
    });
  }

  // ── Mutations ─────────────────────────────────────────────────────
  // Each one recomputes the duration estimate (WorkoutPlanService
  // .estimateDurationMinutes) from the edited list and saves it alongside.

  /// Runs a write; returns whether it succeeded.
  Future<bool> _runMutation(Future<void> Function() action) async {
    if (_isMutating) return false;
    setState(() => _isMutating = true);
    try {
      await action();
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Something went wrong. Please try again.', style: GoogleFonts.manrope()),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  void _showSnack(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.manrope(color: AppColors.onSurface)),
          backgroundColor: AppColors.surfaceContainerHigh,
          action: action,
        ),
      );
  }

  Future<void> _addExercise(ExerciseData data) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final newExercise = <String, dynamic>{
      'exerciseId': DateTime.now().millisecondsSinceEpoch.toString(),
      'exerciseName': data.name,
      'muscleGroup': data.muscleGroup,
      'sets': 3,
      'reps': 10,
      'restSeconds': 60,
    };

    final updatedExercises = [..._exercises, newExercise];
    final newDuration = WorkoutPlanService.estimateDurationMinutes(updatedExercises);

    final ok = await _runMutation(() async {
      final docId = await WorkoutPlanService().addExerciseToDay(
        uid: uid,
        planId: widget.planId,
        dayId: _dayId,
        exercise: newExercise,
        order: _exercises.length,
        newDurationMinutes: newDuration,
      );
      // Keep the new doc ID, so the exercise can be edited, removed or
      // reordered straight away — without it those silently did nothing
      // until the screen was reopened.
      newExercise['docId'] = docId;
      setState(() {
        _exercises = updatedExercises;
        _durationMinutes = newDuration;
      });
    });
    if (ok && mounted) _showSnack('Added ${data.name}');
  }

  /// Removes at once, with UNDO instead of a confirm dialog.
  Future<void> _removeExercise(int index) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final removed = _exercises[index];
    final docId = removed['docId'] as String?;
    if (docId == null) return; // safety: nothing to delete server-side

    final updatedExercises = [..._exercises]..removeAt(index);
    final newDuration = WorkoutPlanService.estimateDurationMinutes(updatedExercises);

    final ok = await _runMutation(() async {
      await WorkoutPlanService().removeExerciseFromDay(
        uid: uid,
        planId: widget.planId,
        dayId: _dayId,
        exerciseDocId: docId,
        newDurationMinutes: newDuration,
      );
      setState(() {
        _exercises = updatedExercises;
        _durationMinutes = newDuration;
      });
    });
    if (!ok || !mounted) return;

    _showSnack(
      'Removed ${removed['exerciseName'] ?? 'exercise'}',
      action: SnackBarAction(
        label: 'UNDO',
        textColor: AppColors.primary,
        onPressed: () => _restoreExercise(removed, index),
      ),
    );
  }

  /// Puts a just-removed exercise back in its old position (as a new doc,
  /// with the same sets/reps/rest), then renumbers the day's order.
  Future<void> _restoreExercise(Map<String, dynamic> removed, int index) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final exercise = <String, dynamic>{
      for (final e in removed.entries)
        if (e.key != 'docId' && e.key != 'order') e.key: e.value,
    };
    final at = index.clamp(0, _exercises.length);
    final restored = [..._exercises]..insert(at, exercise);
    final newDuration = WorkoutPlanService.estimateDurationMinutes(restored);

    await _runMutation(() async {
      final docId = await WorkoutPlanService().addExerciseToDay(
        uid: uid,
        planId: widget.planId,
        dayId: _dayId,
        exercise: exercise,
        order: at,
        newDurationMinutes: newDuration,
      );
      exercise['docId'] = docId;
      final docIds = restored.map((e) => e['docId'] as String?).whereType<String>().toList();
      if (docIds.length == restored.length) {
        await WorkoutPlanService().reorderExercisesInDay(
          uid: uid,
          planId: widget.planId,
          dayId: _dayId,
          orderedExerciseDocIds: docIds,
        );
      }
      setState(() {
        _exercises = restored;
        _durationMinutes = newDuration;
      });
    });
  }

  /// Saves edited fields on one exercise (sets/reps/rest, or a swap).
  Future<bool> _updateExercise(int index, Map<String, dynamic> fields) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final docId = _exercises[index]['docId'] as String?;
    if (docId == null) return false;

    final updatedExercises = [..._exercises];
    updatedExercises[index] = {..._exercises[index], ...fields};
    final newDuration = WorkoutPlanService.estimateDurationMinutes(updatedExercises);

    return _runMutation(() async {
      await WorkoutPlanService().updateExerciseInDay(
        uid: uid,
        planId: widget.planId,
        dayId: _dayId,
        exerciseDocId: docId,
        fields: fields,
        newDurationMinutes: newDuration,
      );
      setState(() {
        _exercises = updatedExercises;
        _durationMinutes = newDuration;
      });
    });
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (newIndex > oldIndex) newIndex -= 1;
    final updated = [..._exercises];
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);

    setState(() => _exercises = updated); // optimistic — feels instant while dragging

    final docIds = updated.map((e) => e['docId'] as String?).whereType<String>().toList();
    if (docIds.length != updated.length) return; // some exercise missing a docId — skip persisting

    await _runMutation(() => WorkoutPlanService().reorderExercisesInDay(
          uid: uid,
          planId: widget.planId,
          dayId: _dayId,
          orderedExerciseDocIds: docIds,
        ));
  }

  /// Tap an exercise: adjust sets/reps/rest, swap it, read how to do it,
  /// or remove it — everything for that exercise in one sheet.
  Future<void> _openExerciseEditor(int index) async {
    final ex = _exercises[index];
    final result = await showModalBottomSheet<_EditResult>(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _ExerciseEditSheet(
        exercise: ex,
        otherExercises: [
          for (int i = 0; i < _exercises.length; i++)
            if (i != index) _exercises[i],
        ],
      ),
    );
    if (result == null || !mounted) return;

    switch (result.action) {
      case _EditAction.save:
        final fields = {
          'sets': result.sets,
          'reps': result.reps,
          'restSeconds': result.restSeconds,
        };
        final changed = fields.entries.any((e) => ex[e.key] != e.value);
        if (changed && await _updateExercise(index, fields) && mounted) {
          _showSnack('${ex['exerciseName']} · ${result.sets} × ${result.reps}, ${result.restSeconds}s rest');
        }
      case _EditAction.swap:
        await _swapExercise(index);
      case _EditAction.remove:
        await _removeExercise(index);
      case _EditAction.info:
        _openExerciseDetail(ex['exerciseName'] as String? ?? '');
    }
  }

  /// Replaces an exercise with another (same muscle group suggested first),
  /// keeping its sets, reps, rest and position.
  Future<void> _swapExercise(int index) async {
    final current = _exercises[index];
    final name = current['exerciseName'] as String? ?? '';
    final muscle = (current['muscleGroup'] as String?)?.isNotEmpty == true
        ? current['muscleGroup'] as String
        : findExerciseByName(name)?.muscleGroup;

    final picked = await Navigator.of(context).push<ExerciseData>(
      MaterialPageRoute(
        builder: (_) => _ExercisePickerScreen(
          title: 'SWAP EXERCISE',
          subtitle: 'Replacing $name — keeps its sets, reps and rest',
          initialMuscle: muscle,
          inWorkout: _exerciseNames,
        ),
      ),
    );
    if (picked == null || !mounted) return;

    final ok = await _updateExercise(index, {
      'exerciseId': DateTime.now().millisecondsSinceEpoch.toString(),
      'exerciseName': picked.name,
      'muscleGroup': picked.muscleGroup,
    });
    if (ok && mounted) _showSnack('Swapped $name for ${picked.name}');
  }

  /// The bottom CTA: "start" only when today's window is open and unused —
  /// already-logged and already-passed days each get their own read-only
  /// state instead of silently offering (or re-offering) INITIATE PROTOCOL
  Widget _buildActionSection() {
    final String label;
    final String subtitle;
    final VoidCallback? onPressed;
    final bool isDone = _isCompleted;
    final bool isSkipped = !isDone && _isPastThisWeek;

    if (_loadingStatus) {
      label = 'INITIATE PROTOCOL →';
      subtitle = '';
      onPressed = null;
    } else if (isDone) {
      label = 'WORKOUT COMPLETED · VIEW →';
      subtitle = _isToday ? 'GREAT WORK — SEE YOU TOMORROW' : 'COMPLETED THIS WEEK';
      onPressed = () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => WorkoutLogDetailScreen(log: _completedLog!)),
          );
    } else if (isSkipped) {
      label = 'SESSION SKIPPED';
      subtitle = "THIS DAY'S WINDOW HAS PASSED";
      onPressed = null;
    } else if (_isToday) {
      label = 'INITIATE PROTOCOL →';
      subtitle = 'READY FOR 100% OUTPUT?';
      onPressed = (_exercises.isNotEmpty && !_isMutating) ? _startWorkout : null;
    } else {
      label = 'INITIATE PROTOCOL →';
      subtitle = 'AVAILABLE ON ITS SCHEDULED DAY';
      onPressed = null;
    }

    return Column(
      children: [
        ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            disabledBackgroundColor: AppColors.surfaceContainerHigh,
            backgroundColor: isDone ? AppColors.primary.withValues(alpha: 0.15) : null,
            foregroundColor: isDone ? AppColors.primary : null,
          ),
          child: Text(
            label,
            style: GoogleFonts.spaceGrotesk(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.5),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          subtitle,
          style: GoogleFonts.manrope(
            fontSize: 10,
            letterSpacing: 2,
            color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  void _startWorkout() {
    final updatedDay = {
      ...widget.day,
      'exercises': _exercises,
      'durationMinutes': _durationMinutes,
    };
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => WorkoutActiveScreen(day: updatedDay)),
    );
  }

  Widget _buildDetailMedia(ExerciseData data) {
    // Case 1: GIF — full-size, tappable, opens the same full-screen GIF viewer
    if (data.localGifAsset != null) {
      return Pressable(
        onTap: () => showExerciseDemoFullscreen(context, gifAsset: data.localGifAsset!, title: data.name),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              color: AppColors.surfaceContainerHigh,
              child: Image.asset(data.localGifAsset!, fit: BoxFit.contain),
            ),
          ),
        ),
      );
    }

    // Case 2: no GIF, real YouTube ID — existing thumbnail + play icon
    if (data.youtubeId.isNotEmpty) {
      return Pressable(
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
      );
    }

    // Case 3: neither
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: Icon(Icons.fitness_center_rounded, size: 40, color: AppColors.onSurfaceVariant),
      ),
    );
  }

  void _openExerciseDetail(String exerciseName) {
    final data = findExerciseByName(exerciseName);
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
            Text(data.name,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
            const SizedBox(height: 4),
            Text(
              '${data.difficulty.toUpperCase()} · ${data.equipment}',
              style: GoogleFonts.manrope(fontSize: 11, letterSpacing: 1, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            _buildDetailMedia(data),
            const SizedBox(height: 20),
            Text('HOW TO PERFORM',
                style: GoogleFonts.manrope(
                    fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.onSurfaceVariant)),
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
                        child: Text(entry.value,
                            style: GoogleFonts.manrope(fontSize: 13, color: AppColors.onSurface, height: 1.4)),
                      ),
                    ],
                  ),
                )),
            if (data.tips.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('FORM TIPS',
                  style: GoogleFonts.manrope(
                      fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.onSurfaceVariant)),
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

  void _openAddExercisePicker() async {
    final picked = await Navigator.of(context).push<ExerciseData>(
      MaterialPageRoute(
        builder: (_) => _ExercisePickerScreen(inWorkout: _exerciseNames),
      ),
    );
    if (picked != null) _addExercise(picked);
  }

  @override
  Widget build(BuildContext context) {
    final workoutName = widget.day['workoutName'] as String? ?? 'Workout';
    final focusDescription = widget.day['focusDescription'] as String? ?? '';
    final focusChips = focusDescription
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: [
                  Pressable(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface, size: 18),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'TAP TO EDIT · HOLD ≡ TO REORDER',
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _isMutating
                  ? const Padding(
                      padding: EdgeInsets.fromLTRB(24, 12, 24, 0),
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        color: AppColors.primary,
                        backgroundColor: AppColors.surfaceContainerHigh,
                      ),
                    )
                  : const SizedBox(height: 14),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CURRENT PROTOCOL',
                        style: GoogleFonts.manrope(
                            fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 2, color: AppColors.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Text(
                      workoutName.toUpperCase(),
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 34, fontWeight: FontWeight.w700, color: AppColors.onSurface, height: 1.0),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildHeaderStat('$_durationMinutes', 'EST. MIN'),
                        const SizedBox(width: 10),
                        _buildHeaderStat('${_exercises.length}', 'EXERCISES'),
                        const SizedBox(width: 10),
                        _buildHeaderStat('$_totalSets', 'SETS'),
                      ],
                    ),
                    if (focusChips.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: focusChips
                            .map((chip) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(48),
                                  ),
                                  child: Text(chip.toUpperCase(),
                                      style: GoogleFonts.manrope(
                                          fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.5, color: AppColors.onSurface)),
                                ))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Text('EXERCISE MATRIX',
                            style: GoogleFonts.manrope(
                                fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2, color: AppColors.onSurfaceVariant)),
                        const Spacer(),
                        Pressable(
                          onTap: _openAddExercisePicker,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(48),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.add_rounded, size: 16, color: AppColors.primary),
                                const SizedBox(width: 4),
                                Text('ADD',
                                    style: GoogleFonts.manrope(
                                        fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.primary)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Reorderable list nested inside the outer scroll view —
                    // shrinkWrap + no own scrolling so it behaves as part of
                    // the same page rather than a separate scroll region.
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      onReorder: _reorder,
                      itemCount: _exercises.length,
                      itemBuilder: (context, index) => Padding(
                        key: ValueKey(_exercises[index]['docId'] ??
                            '${_exercises[index]['exerciseName']}-$index'),
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildExerciseRow(index),
                      ),
                    ),

                    if (_exercises.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No exercises yet — tap ADD to build this workout.',
                          style: GoogleFonts.manrope(fontSize: 13, color: AppColors.onSurfaceVariant),
                        ),
                      ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: _buildActionSection(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderStat(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.onSurface, height: 1.1)),
            const SizedBox(height: 2),
            Text(label,
                style: GoogleFonts.manrope(
                    fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: AppColors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseRow(int index) {
    final ex = _exercises[index];
    final name = ex['exerciseName'] as String? ?? '';
    final sets = ex['sets'] as int? ?? 0;
    final reps = ex['reps'] as int? ?? 0;
    final rest = ex['restSeconds'] as int? ?? 60;
    final data = findExerciseByName(name);
    final muscle = (ex['muscleGroup'] as String?)?.isNotEmpty == true
        ? ex['muscleGroup'] as String
        : data?.muscleGroup ?? '';
    final gif = data?.localGifAsset;

    return Pressable(
      onTap: () => _openExerciseEditor(index),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // Thumbnail plays the demo; the badge is the exercise's order.
            Pressable(
              onTap: gif == null
                  ? null
                  : () => showExerciseDemoFullscreen(context, gifAsset: gif, title: name),
              child: Stack(
                children: [
                  ExerciseThumb(asset: data?.thumbnailAsset, size: 52),
                  Positioned(
                    left: 4,
                    top: 4,
                    child: Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        shape: BoxShape.circle,
                      ),
                      child: Text('${index + 1}',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.onSurface, height: 1.15)),
                  const SizedBox(height: 3),
                  Text(
                    [if (muscle.isNotEmpty) muscle.toUpperCase(), '${rest}S REST'].join(' · '),
                    style: GoogleFonts.manrope(
                        fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$sets × $reps',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                Text('SETS × REPS',
                    style: GoogleFonts.manrope(fontSize: 9, letterSpacing: 1, color: AppColors.onSurfaceVariant)),
              ],
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                child: Icon(Icons.drag_handle_rounded, size: 20, color: AppColors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Exercise editor sheet ───────────────────────────────────────────────

enum _EditAction { save, swap, remove, info }

class _EditResult {
  final _EditAction action;
  final int sets;
  final int reps;
  final int restSeconds;

  const _EditResult(this.action, {this.sets = 0, this.reps = 0, this.restSeconds = 0});
}

/// Steppers for sets / reps / rest with a live estimate of the workout's
/// length, plus swap, how-to and remove — one place for everything about
/// an exercise in this plan.
class _ExerciseEditSheet extends StatefulWidget {
  final Map<String, dynamic> exercise;

  /// The rest of the day's exercises, for the live duration estimate.
  final List<Map<String, dynamic>> otherExercises;

  const _ExerciseEditSheet({required this.exercise, required this.otherExercises});

  @override
  State<_ExerciseEditSheet> createState() => _ExerciseEditSheetState();
}

class _ExerciseEditSheetState extends State<_ExerciseEditSheet> {
  late int _sets = widget.exercise['sets'] as int? ?? 3;
  late int _reps = widget.exercise['reps'] as int? ?? 10;
  late int _rest = widget.exercise['restSeconds'] as int? ?? 60;

  void _step(void Function() change) {
    HapticFeedback.selectionClick();
    setState(change);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.exercise['exerciseName'] as String? ?? '';
    final data = findExerciseByName(name);
    final muscle = (widget.exercise['muscleGroup'] as String?)?.isNotEmpty == true
        ? widget.exercise['muscleGroup'] as String
        : data?.muscleGroup ?? '';
    final workoutMinutes = WorkoutPlanService.estimateDurationMinutes([
      ...widget.otherExercises,
      {'sets': _sets, 'reps': _reps, 'restSeconds': _rest},
    ]);

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewPadding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              ExerciseThumb(asset: data?.thumbnailAsset, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface, height: 1.15)),
                    const SizedBox(height: 3),
                    Text(
                      [if (muscle.isNotEmpty) muscle, ?data?.equipment].join(' · ').toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (data != null)
                IconButton(
                  tooltip: 'How to perform',
                  onPressed: () => Navigator.pop(context, const _EditResult(_EditAction.info)),
                  icon: const Icon(Icons.info_outline_rounded, color: AppColors.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _StepperRow(
            label: 'SETS',
            value: '$_sets',
            onMinus: _sets > 1 ? () => _step(() => _sets--) : null,
            onPlus: _sets < 10 ? () => _step(() => _sets++) : null,
          ),
          const SizedBox(height: 8),
          _StepperRow(
            label: 'REPS',
            value: '$_reps',
            onMinus: _reps > 1 ? () => _step(() => _reps--) : null,
            onPlus: _reps < 50 ? () => _step(() => _reps++) : null,
          ),
          const SizedBox(height: 8),
          _StepperRow(
            label: 'REST',
            value: '${_rest}s',
            onMinus: _rest > 0 ? () => _step(() => _rest -= 15) : null,
            onPlus: _rest < 300 ? () => _step(() => _rest += 15) : null,
          ),
          const SizedBox(height: 12),
          Text(
            'WORKOUT ≈ $workoutMinutes MIN',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
                fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.pop(
              context,
              _EditResult(_EditAction.save, sets: _sets, reps: _reps, restSeconds: _rest),
            ),
            child: Text('SAVE CHANGES',
                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, letterSpacing: 1.5)),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SheetAction(
                  icon: Icons.swap_horiz_rounded,
                  label: 'SWAP EXERCISE',
                  onTap: () => Navigator.pop(context, const _EditResult(_EditAction.swap)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SheetAction(
                  icon: Icons.delete_outline_rounded,
                  label: 'REMOVE',
                  color: AppColors.error,
                  onTap: () => Navigator.pop(context, const _EditResult(_EditAction.remove)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  const _StepperRow({required this.label, required this.value, this.onMinus, this.onPlus});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Text(label,
              style: GoogleFonts.manrope(
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.onSurfaceVariant)),
          const Spacer(),
          _stepButton(Icons.remove_rounded, onMinus),
          SizedBox(
            width: 64,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: AppColors.onSurface,
              ),
            ),
          ),
          _stepButton(Icons.add_rounded, onPlus),
        ],
      ),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap) {
    return Pressable(
      onTap: onTap,
      pressedScale: 0.9,
      child: Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainerLow,
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            size: 18,
            color: onTap == null
                ? AppColors.onSurfaceVariant.withValues(alpha: 0.3)
                : AppColors.onSurface),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.onSurface,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(48),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: color)),
          ],
        ),
      ),
    );
  }
}

// ── Exercise picker ─────────────────────────────────────────────────────

/// Full-library picker for ADD and SWAP. Built self-contained (rather than
/// reusing exercise_library_screen.dart) since picking needs a selection
/// callback that browsing doesn't. Defaults to exercises the user's own
/// equipment allows; exercises already in the workout are marked.
class _ExercisePickerScreen extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String? initialMuscle;
  final Set<String> inWorkout;

  const _ExercisePickerScreen({
    this.title = 'ADD EXERCISE',
    this.subtitle,
    this.initialMuscle,
    this.inWorkout = const {},
  });

  @override
  State<_ExercisePickerScreen> createState() => _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends State<_ExercisePickerScreen> {
  String _query = '';
  late String _muscleFilter;
  late final List<String> _muscleGroups;

  /// The user's equipment (onboarding ids); null until loaded or if it
  /// couldn't be — the MY EQUIPMENT filter only shows once it's known.
  List<String>? _userEquipment;
  bool _myEquipmentOnly = false;

  bool get _canFilterEquipment =>
      _userEquipment != null &&
      _userEquipment!.isNotEmpty &&
      !_userEquipment!.contains('fullGym');

  @override
  void initState() {
    super.initState();
    final groups = kExercises.map((e) => e.muscleGroup).toSet().toList()..sort();
    _muscleGroups = ['All', ...groups];
    _muscleFilter = groups.contains(widget.initialMuscle) ? widget.initialMuscle! : 'All';
    _loadEquipment();
  }

  Future<void> _loadEquipment() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final profile = await UserProfileService().getUserProfile(uid);
      final equipment = (profile?['equipment'] as List?)?.cast<String>();
      if (!mounted || equipment == null) return;
      setState(() {
        _userEquipment = equipment;
        _myEquipmentOnly = _canFilterEquipment;
      });
    } catch (e) {
      debugPrint('Exercise picker: equipment load failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = kExercises.where((ex) {
      final matchesQuery = _query.isEmpty || ex.name.toLowerCase().contains(_query.toLowerCase());
      final matchesMuscle = _muscleFilter == 'All' || ex.muscleGroup == _muscleFilter;
      final matchesEquipment = !_myEquipmentOnly ||
          !_canFilterEquipment ||
          equipmentMatches(ex.equipment, _userEquipment!);
      return matchesQuery && matchesMuscle && matchesEquipment;
    }).toList()
      // Already-added ones sink to the bottom.
      ..sort((a, b) {
        final ia = widget.inWorkout.contains(a.name) ? 1 : 0;
        final ib = widget.inWorkout.contains(b.name) ? 1 : 0;
        return ia.compareTo(ib);
      });

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Row(
                children: [
                  Pressable(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface, size: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                        if (widget.subtitle != null)
                          Text(widget.subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.manrope(fontSize: 12, color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                onChanged: (val) => setState(() => _query = val),
                style: GoogleFonts.manrope(color: AppColors.onSurface),
                decoration: InputDecoration(
                  hintText: 'Search exercises',
                  hintStyle: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.onSurfaceVariant),
                  filled: true,
                  fillColor: AppColors.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  if (_canFilterEquipment)
                    _filterChip(
                      label: 'MY EQUIPMENT',
                      icon: Icons.fitness_center_rounded,
                      selected: _myEquipmentOnly,
                      outlined: true,
                      onTap: () => setState(() => _myEquipmentOnly = !_myEquipmentOnly),
                    ),
                  for (final group in _muscleGroups)
                    _filterChip(
                      label: group.toUpperCase(),
                      selected: group == _muscleFilter,
                      onTap: () => setState(() => _muscleFilter = group),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Text(
                '${filtered.length} EXERCISE${filtered.length == 1 ? '' : 'S'}',
                style: GoogleFonts.manrope(
                    fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5, color: AppColors.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          _myEquipmentOnly
                              ? 'Nothing here matches your equipment — turn off MY EQUIPMENT to see everything.'
                              : 'No exercises found.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.manrope(fontSize: 13, color: AppColors.onSurfaceVariant, height: 1.5),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                      itemCount: filtered.length,
                      itemBuilder: (_, index) => _buildOption(filtered[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(ExerciseData ex) {
    final added = widget.inWorkout.contains(ex.name);
    final gif = ex.localGifAsset;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Opacity(
        opacity: added ? 0.5 : 1,
        child: Pressable(
          onTap: added ? null : () => Navigator.of(context).pop(ex),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Pressable(
                  onTap: gif == null
                      ? null
                      : () => showExerciseDemoFullscreen(context, gifAsset: gif, title: ex.name),
                  child: ExerciseThumb(asset: ex.thumbnailAsset, size: 52),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ex.name,
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                      const SizedBox(height: 3),
                      Text(
                        '${ex.muscleGroup.toUpperCase()} · ${ex.equipment}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                            fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (added)
                  Text('IN WORKOUT',
                      style: GoogleFonts.manrope(
                          fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: AppColors.primary))
                else
                  Icon(
                    widget.title == 'SWAP EXERCISE'
                        ? Icons.swap_horiz_rounded
                        : Icons.add_circle_outline_rounded,
                    color: AppColors.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    bool outlined = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected
                ? (outlined ? AppColors.primary.withValues(alpha: 0.15) : AppColors.primary)
                : AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(48),
            border: outlined
                ? Border.all(color: selected ? AppColors.primary : AppColors.outlineVariant)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 13,
                    color: selected ? AppColors.primary : AppColors.onSurfaceVariant),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: selected
                      ? (outlined ? AppColors.primary : AppColors.onPrimary)
                      : AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
