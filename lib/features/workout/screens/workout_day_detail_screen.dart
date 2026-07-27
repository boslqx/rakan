import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../../../core/theme/app_colors.dart';
import '../data/exercise_data.dart';
import '../services/workout_plan_service.dart';
import 'workout_active_screen.dart';

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

  bool get _isToday => widget.day['dayNumber'] == DateTime.now().weekday;

  @override
  void initState() {
    super.initState();
    _exercises = List<Map<String, dynamic>>.from(
      (widget.day['exercises'] as List?)?.cast<Map<String, dynamic>>() ?? [],
    );
    _durationMinutes = widget.day['durationMinutes'] as int? ?? 0;
  }

  // ── Duration estimate ──────────────────────────────────────────────

  /// Rough estimate recomputed whenever exercises are added/removed —
  /// reuses the same deterministic "reps × 3s (min 15s) working time,
  /// plus rest between sets" formula already used for the Auto-Log guided
  /// timer, for the same reason: a consistent, explainable formula rather
  /// than a black-box guess, easy to justify in the dissertation.
  int _estimateDurationMinutes(List<Map<String, dynamic>> exercises) {
    const secondsPerRep = 3;
    const minWorkSeconds = 15;
    int totalSeconds = 0;

    for (final ex in exercises) {
      final sets = ex['sets'] as int? ?? 3;
      final reps = ex['reps'] as int? ?? 10;
      final restSeconds = ex['restSeconds'] as int? ?? 60;
      final workSeconds = (reps * secondsPerRep) < minWorkSeconds
          ? minWorkSeconds
          : reps * secondsPerRep;
      totalSeconds += sets * workSeconds + (sets - 1) * restSeconds;
    }

    final minutes = (totalSeconds / 60).round();
    return minutes < 10 ? 10 : minutes;
  }

  // ── Mutations ─────────────────────────────────────────────────────

  Future<void> _runMutation(Future<void> Function() action) async {
    if (_isMutating) return;
    setState(() => _isMutating = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Something went wrong. Please try again.', style: GoogleFonts.manrope()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  Future<void> _addExercise(ExerciseData data) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final newExercise = {
      'exerciseId': DateTime.now().millisecondsSinceEpoch.toString(),
      'exerciseName': data.name,
      'muscleGroup': data.muscleGroup,
      'sets': 3,
      'reps': 10,
      'restSeconds': 60,
    };

    final updatedExercises = [..._exercises, newExercise];
    final newDuration = _estimateDurationMinutes(updatedExercises);

    await _runMutation(() async {
      await WorkoutPlanService().addExerciseToDay(
        uid: uid,
        planId: widget.planId,
        dayId: widget.day['id'] as String,
        exercise: newExercise,
        order: _exercises.length,
        newDurationMinutes: newDuration,
      );
      setState(() {
        _exercises = updatedExercises;
        _durationMinutes = newDuration;
      });
    });
  }

  Future<void> _removeExercise(int index) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final docId = _exercises[index]['docId'] as String?;
    if (docId == null) return; // safety: nothing to delete server-side

    final updatedExercises = [..._exercises]..removeAt(index);
    final newDuration = _estimateDurationMinutes(updatedExercises);

    await _runMutation(() async {
      await WorkoutPlanService().removeExerciseFromDay(
        uid: uid,
        planId: widget.planId,
        dayId: widget.day['id'] as String,
        exerciseDocId: docId,
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
          dayId: widget.day['id'] as String,
          orderedExerciseDocIds: docIds,
        ));
  }

  Future<void> _confirmRemove(int index) async {
    final name = _exercises[index]['exerciseName'] as String? ?? 'this exercise';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Remove Exercise?',
            style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface, fontWeight: FontWeight.w600)),
        content: Text('$name will be removed from this workout.',
            style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Remove',
                style: GoogleFonts.manrope(color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm == true) _removeExercise(index);
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

  void _openAddExercisePicker() async {
    final picked = await Navigator.of(context).push<ExerciseData>(
      MaterialPageRoute(builder: (_) => const _ExercisePickerScreen()),
    );
    if (picked != null) _addExercise(picked);
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
                  GestureDetector(
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
                    'DRAG TO REORDER · TAP TO VIEW',
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
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CURRENT PROTOCOL',
                        style: GoogleFonts.manrope(
                            fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 2, color: AppColors.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            workoutName.toUpperCase(),
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 36, fontWeight: FontWeight.w700, color: AppColors.onSurface, height: 1.0),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('$_durationMinutes',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 36, fontWeight: FontWeight.w700, color: AppColors.primary)),
                            Text('EST. MIN',
                                style: GoogleFonts.manrope(
                                    fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.5, color: AppColors.onSurfaceVariant)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Text('EXERCISE MATRIX',
                            style: GoogleFonts.manrope(
                                fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 2, color: AppColors.onSurfaceVariant)),
                        const Spacer(),
                        GestureDetector(
                          onTap: _openAddExercisePicker,
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
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Reorderable list nested inside the outer scroll view —
                    // shrinkWrap + no own scrolling so it behaves as part of
                    // the same page rather than a separate scroll region.
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      onReorder: _reorder,
                      itemCount: _exercises.length,
                      itemBuilder: (context, index) {
                        final ex = _exercises[index];
                        final name = ex['exerciseName'] as String? ?? '';
                        final sets = ex['sets'] as int? ?? 0;
                        final reps = ex['reps'] as int? ?? 0;
                        final muscle = ex['muscleGroup'] as String? ?? '';

                        return Padding(
                          key: ValueKey(ex['docId'] ?? '$name-$index'),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GestureDetector(
                            onTap: () => _openExerciseDetail(name),
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(
                                      child: Text('${index + 1}',
                                          style: GoogleFonts.spaceGrotesk(
                                              fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary)),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(name,
                                            style: GoogleFonts.spaceGrotesk(
                                                fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                                        const SizedBox(height: 2),
                                        Text(muscle.toUpperCase(),
                                            style: GoogleFonts.manrope(
                                                fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1.5, color: AppColors.onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
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
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => _confirmRemove(index),
                                    child: const Padding(
                                      padding: EdgeInsets.only(left: 4, right: 4),
                                      child: Icon(Icons.close_rounded, size: 18, color: AppColors.onSurfaceVariant),
                                    ),
                                  ),
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: const Padding(
                                      padding: EdgeInsets.only(left: 4),
                                      child: Icon(Icons.drag_handle_rounded, size: 18, color: AppColors.onSurfaceVariant),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
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
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed: (_isToday && _exercises.isNotEmpty && !_isMutating) ? _startWorkout : null,
                    style: ElevatedButton.styleFrom(
                      disabledBackgroundColor: AppColors.surfaceContainerHigh,
                    ),
                    child: Text(
                      'INITIATE PROTOCOL →',
                      style: GoogleFonts.spaceGrotesk(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isToday ? 'READY FOR 100% OUTPUT?' : "AVAILABLE ON ITS SCHEDULED DAY",
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      letterSpacing: 2,
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Minimal full-exercise-library picker used by "ADD" above. Built
/// self-contained (rather than reusing exercise_library_screen.dart)
/// since that screen's exact constructor/selection-callback shape hasn't
/// been confirmed — safer not to guess and risk breaking it.
class _ExercisePickerScreen extends StatefulWidget {
  const _ExercisePickerScreen();

  @override
  State<_ExercisePickerScreen> createState() => _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends State<_ExercisePickerScreen> {
  String _query = '';
  String _muscleFilter = 'All';

  late final List<String> _muscleGroups;

  @override
  void initState() {
    super.initState();
    final groups = kExercises.map((e) => e.muscleGroup).toSet().toList()..sort();
    _muscleGroups = ['All', ...groups];
  }

  @override
  Widget build(BuildContext context) {
    final filtered = kExercises.where((ex) {
      final matchesQuery = _query.isEmpty || ex.name.toLowerCase().contains(_query.toLowerCase());
      final matchesMuscle = _muscleFilter == 'All' || ex.muscleGroup == _muscleFilter;
      return matchesQuery && matchesMuscle;
    }).toList();

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
                  GestureDetector(
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
                  Text('ADD EXERCISE',
                      style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
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
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: _muscleGroups.length,
                itemBuilder: (_, i) {
                  final group = _muscleGroups[i];
                  final isSelected = group == _muscleFilter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _muscleFilter = group),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary : AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(48),
                        ),
                        child: Center(
                          child: Text(
                            group.toUpperCase(),
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: isSelected ? AppColors.onPrimary : AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                itemCount: filtered.length,
                itemBuilder: (_, index) {
                  final ex = filtered[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(ex),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                'https://img.youtube.com/vi/${ex.youtubeId}/mqdefault.jpg',
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 48,
                                  height: 48,
                                  color: AppColors.surfaceContainerHigh,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(ex.name,
                                      style: GoogleFonts.spaceGrotesk(
                                          fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                                  const SizedBox(height: 2),
                                  Text(ex.muscleGroup.toUpperCase(),
                                      style: GoogleFonts.manrope(
                                          fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}