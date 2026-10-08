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
import '../../../shared/utils/number_format.dart';
import '../../../shared/widgets/pressable.dart';
import '../widgets/elapsed_time_text.dart';
import '../widgets/exercise_media.dart';
import '../widgets/rest_timer_bar.dart';
import '../widgets/session_hud.dart';

/// What the rest bar previews as coming up after the current rest.
typedef _UpNext = ({String title, String detail, String? thumbnail});

/// The Manual workout screen: a scrollable list of every exercise in the
/// day's plan. One exercise is open at a time — it plays its demo and shows
/// its set rows — and finishing it hands off to the next.
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

  // Rest timer (Manual mode). Non-null while a rest countdown is showing;
  // _restId changes per rest so a new set restarts the countdown.
  int? _restSeconds;
  _UpNext? _restUpNext;
  int _restId = 0;

  /// The exercise card that's open. Null when every card is closed.
  int? _focusedIndex;
  final ScrollController _scrollController = ScrollController();
  late final List<GlobalKey> _cardKeys;
  final GlobalKey _finishKey = GlobalKey();

  /// How long a card takes to open or close.
  static const Duration _expandDuration = Duration(milliseconds: 280);

  void _startRest(ExerciseSessionState ex) {
    // No rest after the very last set of the workout.
    if (_allExercisesDone || ex.restSeconds <= 0) {
      _restSeconds = null;
      return;
    }
    _restId++;
    _restSeconds = ex.restSeconds;
    _restUpNext = _upNextAfter(ex);
  }

  /// What follows this rest: [ex]'s next set, or — once [ex] is finished —
  /// the next set of the next unfinished exercise.
  _UpNext? _upNextAfter(ExerciseSessionState ex) {
    if (!ex.isFullyComplete) return _upNextFor(ex);
    final i = _nextIncompleteAfter(_exerciseStates.indexOf(ex));
    return i == null ? null : _upNextFor(_exerciseStates[i]);
  }

  _UpNext _upNextFor(ExerciseSessionState ex) => (
        title: ex.exerciseName,
        detail: 'Set ${ex.currentSetIndex + 1} of ${ex.sets.length}',
        thumbnail: ex.data?.thumbnailAsset,
      );

  void _endRest() {
    if (mounted && _restSeconds != null) setState(() => _restSeconds = null);
  }

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

    _cardKeys = List.generate(_exerciseStates.length, (_) => GlobalKey());
    _focusedIndex = _exerciseStates.isEmpty ? null : 0;

    _loadRecommendedWeights();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Prefills each exercise's sets with the user's last logged weight.
  /// One history pass for the whole workout (see
  /// WorkoutLogService.getWeightHistory) instead of a full scan per
  /// exercise.
  Future<void> _loadRecommendedWeights() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _exerciseStates.isEmpty) return;

    final Map<String, ExerciseWeightHistory> history;
    try {
      history = await WorkoutLogService().getWeightHistory(
        uid: uid,
        exerciseNames: _exerciseStates.map((ex) => ex.exerciseName),
        scanLimit: 15,
      );
    } catch (e) {
      debugPrint('Weight prefill failed: $e');
      return; // prefill is a convenience — leave weights blank
    }
    if (!mounted) return;

    setState(() {
      for (final ex in _exerciseStates) {
        final lastWeight = history[ex.exerciseName]?.lastWeight;
        if (lastWeight == null || ex.weightManuallySet) continue;
        for (final set in ex.sets) {
          set.weightKg = lastWeight;
        }
      }
    });
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

  int get _completedSetCount =>
      _exerciseStates.fold(0, (sum, ex) => sum + ex.completedSets.length);

  int get _plannedSetCount =>
      _exerciseStates.fold(0, (sum, ex) => sum + ex.sets.length);

  int get _completedReps => _exerciseStates.fold(
      0,
      (sum, ex) =>
          sum + ex.completedSets.fold(0, (s, i) => s + ex.sets[i].reps));

  /// First unfinished exercise after [index], wrapping around to the top
  /// so one skipped earlier isn't forgotten. Null once everything's done.
  int? _nextIncompleteAfter(int index) {
    final n = _exerciseStates.length;
    for (int step = 1; step < n; step++) {
      final i = (index + step) % n;
      if (!_exerciseStates[i].isFullyComplete) return i;
    }
    return null;
  }

  int? get _firstIncomplete {
    final i = _exerciseStates.indexWhere((ex) => !ex.isFullyComplete);
    return i < 0 ? null : i;
  }

  /// Opens [index]'s card (closing whichever was open) and glides it to the
  /// top. Null closes every card.
  void _focusExercise(int? index) {
    setState(() {
      _focusedIndex = index;
      // Opened something else mid-rest — that's what's up next now.
      if (_restSeconds != null &&
          index != null &&
          !_exerciseStates[index].isFullyComplete) {
        _restUpNext = _upNextFor(_exerciseStates[index]);
      }
    });
    if (index != null) _scrollTo(_cardKeys[index]);
  }

  /// After a finished exercise: open the next unfinished one, or — if that
  /// was the last — close it and bring the finish button into view.
  void _goToNextExercise(int fromIndex) {
    final next = _nextIncompleteAfter(fromIndex);
    if (next != null) {
      _focusExercise(next);
    } else {
      _focusExercise(null);
      _scrollTo(_finishKey, toEnd: true);
    }
  }

  /// Scrolls [key]'s widget into view once the open/close animation has
  /// settled (until then the layout is still moving — a card closing above
  /// would shift the target after the scroll had aimed at it). [toEnd] only
  /// scrolls as far as needed to show its bottom edge.
  void _scrollTo(GlobalKey key, {bool toEnd = false}) {
    Future.delayed(_expandDuration + const Duration(milliseconds: 60), () {
      final target = key.currentContext;
      if (!mounted || target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        alignmentPolicy: toEnd
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.explicit,
      );
    });
  }

  void _toggleSet(ExerciseSessionState ex, int setIndex, bool isCompleted) {
    setState(() {
      if (isCompleted) {
        ex.completedSets.remove(setIndex);
      } else {
        ex.completedSets.add(setIndex);
        _startRest(ex);
      }
    });
    if (isCompleted) return;

    if (ex.isFullyComplete) {
      // Heavier buzz for the last set — and make sure the effort rating
      // that just appeared under the sets is on screen.
      HapticFeedback.mediumImpact();
      final i = _exerciseStates.indexOf(ex);
      if (i == _focusedIndex) _scrollTo(_cardKeys[i], toEnd: true);
    } else {
      HapticFeedback.lightImpact();
    }
  }

  /// Camera rep counter; a counted set ticks off the exercise's next set.
  Future<void> _openFormCheck(ExerciseSessionState ex) async {
    final repsCompleted = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => PoseDetectionScreen(
          exerciseName: ex.exerciseName,
          targetReps: ex.sets.isNotEmpty ? ex.sets[0].reps : 10,
        ),
      ),
    );
    if (!mounted || repsCompleted == null || repsCompleted <= 0) return;
    final firstIncomplete = ex.currentSetIndex;
    if (firstIncomplete < ex.sets.length) {
      _toggleSet(ex, firstIncomplete, false);
    }
  }

  /// Finishing is allowed once at least one set is done — not only when
  /// every set is. Requiring 100% meant completion_rate (a fatigue-model
  /// input) was always 1.0, so the model never saw a cut-short session.
  bool get _canFinish => _completedSetCount > 0;

  /// Asks for confirmation before finishing with sets still left.
  Future<void> _onFinishPressed() async {
    if (_isSaving) return;
    if (!_allExercisesDone) {
      final done = _completedSetCount;
      final planned = _plannedSetCount;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppColors.surfaceContainerLow,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Finish early?',
              style: GoogleFonts.spaceGrotesk(
                  color: AppColors.onSurface, fontWeight: FontWeight.w600)),
          content: Text(
              "You've completed $done of $planned sets. Your session will be "
              'saved as it is, and your plan will adapt to it.',
              style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('Keep Going',
                  style: GoogleFonts.manrope(color: AppColors.primary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('Finish',
                  style: GoogleFonts.manrope(
                      color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }
    await _completeWorkout();
  }

  /// Launches the full-screen Auto-Log 
  Future<void> _openAutoLog() async {
    _endRest(); // Guided mode runs its own rest timer
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
      await _completeWorkout();
    } else {
      // Reflect whatever partial progress was made, and open the exercise
      // Guided mode stopped on.
      _focusExercise(_firstIncomplete);
    }
  }

  /// Generated once per screen so a retried save reuses the same log id
  /// (a retry overwrites the same documents instead of duplicating them).
  final String _logId = const Uuid().v4();

  Future<void> _completeWorkout() async {
    if (_isSaving) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || !_canFinish) return;

    setState(() => _isSaving = true);

    try {
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
          'rpeRated': ex.rpeRated,
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

      // Stored on the top-level log doc too — the activity feed reads that
      // doc directly and shouldn't need a subcollection fetch for a count.
      final totalSets = _plannedSetCount;
      final completedSets = _completedSetCount;
      final completionRate = totalSets > 0 ? completedSets / totalSets : 1.0;

      // Exercises the user actually did at least one set of. Only these
      // feed RPE, exercise count and adaptation proposals — an untouched
      // exercise wasn't trained, so it shouldn't adapt that muscle group.
      final performed =
          _exerciseStates.where((ex) => ex.completedSets.isNotEmpty).toList();

      // PR detection: one history pass for all exercises. Best-effort — if
      // history can't be read (e.g. offline), the session still saves.
      final prExerciseNames = <String>[];
      try {
        final history = await WorkoutLogService().getWeightHistory(
          uid: uid,
          exerciseNames: performed.map((ex) => ex.exerciseName),
        );
        for (final ex in performed) {
          final completedWeights = ex.sets
              .asMap()
              .entries
              .where((e) => ex.completedSets.contains(e.key))
              .map((e) => e.value.weightKg)
              .where((w) => w > 0)
              .toList();
          if (completedWeights.isEmpty) continue;

          final sessionMax = completedWeights.reduce((a, b) => a > b ? a : b);
          final historicalMax = history[ex.exerciseName]?.maxWeight;
          if (historicalMax != null && sessionMax > historicalMax) {
            prExerciseNames.add(ex.exerciseName);
          }
        }
      } catch (e) {
        debugPrint('PR detection skipped: $e');
      }

      final log = {
        'logId': _logId,
        'planId': widget.day['planId'] ?? '',
        'dayPlanId': widget.day['dayPlanId'] ?? '',
        'workoutName': widget.day['workoutName'] ?? '',
        'startedAt': _startedAt.toIso8601String(),
        'completedAt': completedAt.toIso8601String(),
        'totalDurationMins': durationMins,
        'totalVolume': _totalVolume,
        'totalSetsCompleted': completedSets,
        'totalSetsPlanned': totalSets,
        'completionRate': completionRate,
        'prReached': prExerciseNames.isNotEmpty,
        'prExerciseNames': prExerciseNames,
        'isCompleted': true,
        'exerciseLogs': exerciseLogs,
      };

      final synced =
          await WorkoutLogService().saveWorkoutLog(uid: uid, log: log);
      if (!mounted) return;

      if (!synced) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "You're offline — your workout is saved on this phone and "
              'will sync automatically.',
              style: GoogleFonts.manrope(color: AppColors.onSurface),
            ),
            backgroundColor: AppColors.surfaceContainerHigh,
          ),
        );
      }

      // RPE: rated exercises only (an untouched slider isn't a rating);
      // falls back to the neutral default if nothing was rated.
      final rated = performed.where((ex) => ex.rpeRated).toList();
      final rpeSource = rated.isNotEmpty ? rated : performed;
      final rpeValues = rpeSource.map((ex) => ex.rpe.toDouble()).toList();
      final avgRpe = rpeValues.isEmpty
          ? 5.0
          : rpeValues.reduce((a, b) => a + b) / rpeValues.length;
      final maxRpe =
          rpeValues.isEmpty ? 5.0 : rpeValues.reduce((a, b) => a > b ? a : b);

      final performedNames = performed.map((ex) => ex.exerciseName).toSet();
      final performedLogs = exerciseLogs
          .where((l) => performedNames.contains(l['exerciseName']))
          .toList();

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => WorkoutTransitionScreen(
            workoutName: widget.day['workoutName'] as String? ?? '',
            durationMins: durationMins,
            totalVolume: _totalVolume,
            exerciseCount: performed.length,
            uid: uid,
            avgRpe: avgRpe,
            maxRpe: maxRpe,
            completionRate: completionRate,
            exerciseLogs: performedLogs,
            logId: _logId,
            prExerciseNames: prExerciseNames,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Workout save failed: $e');
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Couldn't save your workout. Your progress is still here — "
            'try again.',
            style: GoogleFonts.manrope(color: AppColors.onSurface),
          ),
          backgroundColor: AppColors.surfaceContainerHigh,
          action: SnackBarAction(
            label: 'RETRY',
            textColor: AppColors.primary,
            onPressed: _completeWorkout,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Intercepts the Android back button / back gesture: leaving used to
    // silently discard the whole session. Now it asks first (same dialog as
    // the X button). Navigator.pop() from the dialog still works, since
    // PopScope only gates system back and maybePop().
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _isSaving) return;
        _showQuitDialog();
      },
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    final upNext = _restUpNext;

    return Scaffold(
      backgroundColor: AppColors.surface,
      bottomNavigationBar: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, animation) => SizeTransition(
          sizeFactor: animation,
          axisAlignment: -1,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: _restSeconds == null
            ? const SizedBox.shrink()
            : RestTimerBar(
                key: ValueKey(_restId),
                seconds: _restSeconds!,
                upNextTitle: upNext?.title,
                upNextDetail: upNext?.detail,
                upNextThumbnail: upNext?.thumbnail,
                onFinished: _endRest,
              ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              // Not a lazy ListView: a session is a handful of exercises,
              // and every card must be laid out for ensureVisible to
              // scroll to it.
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSessionBanner(),
                    const SizedBox(height: 18),
                    _buildSectionHeader(),
                    const SizedBox(height: 12),
                    for (int i = 0; i < _exerciseStates.length; i++)
                      _StaggeredEntrance(
                        index: i,
                        child: _buildExerciseCard(_exerciseStates[i], i),
                      ),
                    _buildFinishSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar ─────────────────────────────────────────────────────────────

  /// Always-visible strip: quit, per-exercise progress, live clock.
  Widget _buildTopBar() {
    final exerciseCount = _exerciseStates.length;
    final doneCount =
        _exerciseStates.where((ex) => ex.isFullyComplete).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Pressable(
            onTap: _showQuitDialog,
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
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$doneCount OF $exerciseCount DONE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _labelStyle(),
                ),
                const SizedBox(height: 7),
                SegmentedProgress(
                  values: [
                    for (final ex in _exerciseStates)
                      ex.sets.isEmpty
                          ? 0
                          : ex.completedSets.length / ex.sets.length,
                  ],
                  highlighted: _focusedIndex,
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LivePulseDot(),
                const SizedBox(width: 4),
                ElapsedTimeText(
                  startedAt: _startedAt,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Session banner ──────────────────────────────────────────────────────

  /// Same photo as the Home "today's workout" card this session was started
  /// from, so the hand-off feels continuous. Carries the title, the muscle
  /// groups being trained, and live session stats.
  Widget _buildSessionBanner() {
    final workoutName = widget.day['workoutName'] as String? ?? 'Workout';
    final targets = <String>{
      for (final ex in _exerciseStates)
        if (ex.muscleGroup.isNotEmpty) ex.muscleGroup,
    };
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final numberStyle = GoogleFonts.spaceGrotesk(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: AppColors.onSurface,
    );
    final suffixStyle = GoogleFonts.spaceGrotesk(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: AppColors.onSurfaceVariant,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.surfaceContainerLow,
              child: Image.asset(
                'assets/images/workout_day.jpg',
                fit: BoxFit.cover,
                // The source photo is 5472px wide; decode it at banner size.
                cacheWidth: (width * dpr).round(),
                opacity: const AlwaysStoppedAnimation(0.9),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppColors.surfaceContainerLow.withValues(alpha: 0.88),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workoutName.toUpperCase(),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    color: AppColors.onSurface,
                  ),
                ),
                if (targets.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final t in targets) _buildTargetChip(t)],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatTile(
                        icon: Icons.check_circle_outline_rounded,
                        label: 'SETS',
                        value: AnimatedCount(
                          value: _completedSetCount.toDouble(),
                          format: (v) => '${v.round()}',
                          suffix: '/$_plannedSetCount',
                          style: numberStyle,
                          suffixStyle: suffixStyle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatTile(
                        icon: Icons.repeat_rounded,
                        label: 'REPS',
                        value: AnimatedCount(
                          value: _completedReps.toDouble(),
                          format: (v) => formatThousands(v),
                          style: numberStyle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      // Volume means nothing in an all-bodyweight session —
                      // show exercises done there instead of a stuck 0.
                      child: _exerciseStates.any((ex) => ex.tracksWeight)
                          ? _buildStatTile(
                              icon: Icons.fitness_center_rounded,
                              label: 'VOLUME',
                              value: AnimatedCount(
                                value: _totalVolume,
                                format: (v) => formatThousands(v),
                                suffix: ' kg',
                                style: numberStyle,
                                suffixStyle: suffixStyle,
                              ),
                            )
                          : _buildStatTile(
                              icon: Icons.flag_outlined,
                              label: 'EXERCISES',
                              value: AnimatedCount(
                                value: _exerciseStates
                                    .where((ex) => ex.isFullyComplete)
                                    .length
                                    .toDouble(),
                                format: (v) => '${v.round()}',
                                suffix: '/${_exerciseStates.length}',
                                style: numberStyle,
                                suffixStyle: suffixStyle,
                              ),
                            ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetChip(String group) {
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipOval(
            child: Container(
              width: 20,
              height: 20,
              color: AppColors.surfaceContainerHigh,
              child: Image.asset(
                'assets/muscle_illustration/${group.toLowerCase()}.png',
                fit: BoxFit.cover,
                cacheWidth: (20 * dpr).round(),
                errorBuilder: (_, _, _) => const Icon(
                    Icons.fitness_center_rounded,
                    size: 11,
                    color: AppColors.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            group.toUpperCase(),
            style: GoogleFonts.manrope(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile({
    required IconData icon,
    required String label,
    required Widget value,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: value,
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 11, color: AppColors.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(label,
                    style: _labelStyle(fontSize: 9, letterSpacing: 1.2)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section header + mode switch ────────────────────────────────────────

  /// "EXERCISES 5" with the Manual/Guided switch beside it. GUIDED
  /// navigates into the full-screen Auto-Log flow.
  Widget _buildSectionHeader() {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  'EXERCISES',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _labelStyle(fontSize: 11, letterSpacing: 1.8),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_exerciseStates.length}',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildModeOption(
                icon: Icons.checklist_rounded,
                label: 'MANUAL',
                selected: true,
              ),
              Pressable(
                onTap: _openAutoLog,
                child: _buildModeOption(
                  icon: Icons.play_circle_outline_rounded,
                  label: 'GUIDED',
                  selected: false,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModeOption({
    required IconData icon,
    required String label,
    required bool selected,
  }) {
    final color = selected ? AppColors.onPrimary : AppColors.onSurfaceVariant;
    // Small phones drop the icons so "EXERCISES" keeps its room.
    final showIcon = MediaQuery.sizeOf(context).width >= 360;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ── Exercise cards ──────────────────────────────────────────────────────

  /// One card per exercise. Only the open one ([_focusedIndex]) shows its
  /// demo and set rows; the rest are compact rows so the list stays
  /// scannable.
  Widget _buildExerciseCard(ExerciseSessionState ex, int exIndex) {
    final isFocused = exIndex == _focusedIndex;

    return Container(
      key: _cardKeys[exIndex],
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isFocused
              ? AppColors.primary.withValues(alpha: 0.28)
              : Colors.transparent,
        ),
      ),
      child: AnimatedSize(
        duration: _expandDuration,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: isFocused
            ? _buildOpenCard(ex, exIndex)
            : _buildCompactRow(ex, exIndex),
      ),
    );
  }

  Widget _buildCompactRow(ExerciseSessionState ex, int exIndex) {
    final done = ex.isFullyComplete;

    return Pressable(
      onTap: () => _focusExercise(exIndex),
      pressedScale: 0.98,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ExerciseThumb(asset: ex.data?.thumbnailAsset, done: done),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ex.exerciseName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: done
                          ? AppColors.onSurfaceVariant
                          : AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    done ? _doneSummary(ex) : _planSummary(ex),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _labelStyle(letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 8),
                  SetDots(total: ex.sets.length, completed: ex.completedSets),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _buildCompactTrailing(ex),
          ],
        ),
      ),
    );
  }

  /// Check when done, "2/4" mid-way, a play cue when not started.
  Widget _buildCompactTrailing(ExerciseSessionState ex) {
    if (ex.isFullyComplete) {
      return Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded,
            size: 16, color: AppColors.onPrimary),
      );
    }
    if (ex.completedSets.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '${ex.completedSets.length}/${ex.sets.length}',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: AppColors.onSurface,
          ),
        ),
      );
    }
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.play_arrow_rounded,
          size: 16, color: AppColors.onSurfaceVariant),
    );
  }

  /// The open exercise: looping demo, details, set rows, and — once every
  /// set is done — the effort rating.
  Widget _buildOpenCard(ExerciseSessionState ex, int exIndex) {
    final gif = ex.data?.localGifAsset;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (gif != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: ExerciseDemoPanel(
              gifAsset: gif,
              title: ex.exerciseName,
              badge: '${exIndex + 1} / ${_exerciseStates.length}',
              heroTag: 'exercise-demo-$exIndex',
              height: 190,
            ),
          ),
        _buildOpenHeader(ex, showThumb: gif == null),
        _buildSetTableHeader(ex),
        const SizedBox(height: 6),
        for (int i = 0; i < ex.sets.length; i++)
          _buildSetRow(
            ex: ex,
            setIndex: i,
            setData: ex.sets[i],
            isCompleted: ex.completedSets.contains(i),
            isCurrent: !ex.completedSets.contains(i) &&
                i == ex.currentSetIndex,
          ),
        if (ex.isFullyComplete) _buildRpeSection(ex, exIndex),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildOpenHeader(ExerciseSessionState ex, {required bool showThumb}) {
    final data = ex.data;
    final canDetectPosture = data?.hasPoseDetection ?? false;
    final muscles = [
      if (ex.muscleGroup.isNotEmpty) ex.muscleGroup,
      ...?data?.secondaryMuscles.take(2),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showThumb) ...[
            ExerciseThumb(asset: data?.thumbnailAsset, size: 48),
            const SizedBox(width: 12),
          ],
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
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    if (data != null) ...[
                      const SizedBox(width: 6),
                      Pressable(
                        onTap: () => _openInfoSheet(ex),
                        child: const Padding(
                          padding: EdgeInsets.all(2),
                          child: Icon(
                            Icons.info_outline_rounded,
                            size: 17,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (muscles.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    muscles.join(' · ').toUpperCase(),
                    style: _labelStyle(letterSpacing: 1.2),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildMetaChip(
                        Icons.timer_outlined, '${ex.restSeconds}s REST'),
                    if (data != null)
                      _buildMetaChip(Icons.signal_cellular_alt_rounded,
                          data.difficulty.toUpperCase()),
                    if (canDetectPosture)
                      Pressable(
                        onTap: () => _openFormCheck(ex),
                        child: _buildMetaChip(
                          Icons.camera_alt_rounded,
                          'FORM CHECK',
                          highlighted: true,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Pressable(
            onTap: () => _focusExercise(null),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.expand_less_rounded,
                  color: AppColors.onSurfaceVariant, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String label,
      {bool highlighted = false}) {
    final color =
        highlighted ? AppColors.primary : AppColors.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.primary.withValues(alpha: 0.15)
            : AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetTableHeader(ExerciseSessionState ex) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          SizedBox(width: 40, child: Text('SET', style: _labelStyle())),
          Expanded(child: Text('REPS', style: _labelStyle())),
          if (ex.tracksWeight) ...[
            const SizedBox(width: 8),
            Expanded(child: Text('KG', style: _labelStyle())),
          ],
          const SizedBox(width: 8 + _checkSize),
        ],
      ),
    );
  }

  // ── Set rows ────────────────────────────────────────────────────────────

  /// Fixed step size for the inline weight +/- buttons.
  static const double _weightIncrement = 2.5;

  /// Size of the tick-off button; big enough to hit mid-set.
  static const double _checkSize = 40;

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
    return Pressable(
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
            child: Pressable(
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      margin: const EdgeInsets.fromLTRB(8, 2, 8, 2),
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
      decoration: BoxDecoration(
        color: isCurrent
            ? AppColors.primary.withValues(alpha: 0.07)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent
              ? AppColors.primary.withValues(alpha: 0.22)
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildSetBadge(setIndex, isCompleted, isCurrent),
            ),
          ),
          Expanded(
            child: Pressable(
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
          _buildSetCheck(ex, setIndex, isCompleted, isCurrent),
        ],
      ),
    );
  }

  /// Set number; filled for the set that's up next.
  Widget _buildSetBadge(int setIndex, bool isCompleted, bool isCurrent) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isCurrent ? AppColors.primary : Colors.transparent,
        shape: BoxShape.circle,
      ),
      child: Text(
        '${setIndex + 1}',
        style: GoogleFonts.spaceGrotesk(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: isCurrent
              ? AppColors.onPrimary
              : isCompleted
                  ? AppColors.primary
                  : AppColors.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildSetCheck(ExerciseSessionState ex, int setIndex,
      bool isCompleted, bool isCurrent) {
    return Pressable(
      onTap: () => _toggleSet(ex, setIndex, isCompleted),
      pressedScale: 0.9,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: _checkSize,
        height: _checkSize,
        decoration: BoxDecoration(
          color: isCompleted
              ? AppColors.primary
              : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCompleted
                ? AppColors.primary
                : isCurrent
                    ? AppColors.primary.withValues(alpha: 0.6)
                    : AppColors.outlineVariant,
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            child: child,
          ),
          child: isCompleted
              ? const Icon(Icons.check_rounded,
                  key: ValueKey('done'), size: 20, color: AppColors.onPrimary)
              : const SizedBox.shrink(key: ValueKey('todo')),
        ),
      ),
    );
  }

  // ── Effort rating ───────────────────────────────────────────────────────

  static String _rpeDescriptor(int rpe) {
    if (rpe <= 2) return 'VERY EASY';
    if (rpe <= 4) return 'EASY';
    if (rpe <= 6) return 'MODERATE';
    if (rpe <= 8) return 'HARD';
    if (rpe == 9) return 'VERY HARD';
    return 'MAX EFFORT';
  }

  /// Shown under a finished exercise's sets: rate the effort, then move on.
  Widget _buildRpeSection(ExerciseSessionState ex, int exIndex) {
    final next = _nextIncompleteAfter(exIndex);
    final nextLabel = next == null
        ? 'WRAP UP SESSION'
        : 'NEXT: ${_exerciseStates[next].exerciseName.toUpperCase()}';

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 12, 10, 0),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('HOW HARD WAS THAT?', style: _labelStyle()),
                    const SizedBox(height: 3),
                    Text(
                      ex.rpeRated
                          ? _rpeDescriptor(ex.rpe)
                          : 'SLIDE TO RATE YOUR EFFORT',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: ex.rpeRated
                            ? AppColors.onSurface
                            : AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text.rich(
                TextSpan(
                  text: '${ex.rpe}',
                  children: [
                    TextSpan(
                      text: '/10',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: ex.rpeRated
                      ? AppColors.primary
                      : AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: AppColors.surfaceContainerLow,
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.1),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
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
              Text('EASY', style: _labelStyle(fontSize: 9)),
              Text('MAX EFFORT', style: _labelStyle(fontSize: 9)),
            ],
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: () => _goToNextExercise(exIndex),
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    nextLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: AppColors.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  next == null
                      ? Icons.flag_rounded
                      : Icons.arrow_forward_rounded,
                  size: 16,
                  color: AppColors.onPrimary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Finish ──────────────────────────────────────────────────────────────

  Widget _buildFinishSection() {
    final allDone = _allExercisesDone && _exerciseStates.isNotEmpty;
    final canFinish = _canFinish;
    final String label;
    if (allDone) {
      label = 'COMPLETE WORKOUT →';
    } else if (canFinish) {
      label = 'FINISH WORKOUT ($_completedSetCount/$_plannedSetCount SETS)';
    } else {
      label = 'COMPLETE A SET TO FINISH';
    }

    final button = ElevatedButton(
      onPressed: canFinish && !_isSaving ? _onFinishPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor:
            allDone ? AppColors.primary : AppColors.surfaceContainerHigh,
        disabledBackgroundColor: AppColors.surfaceContainerHigh,
      ),
      child: _isSaving
          ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: allDone ? AppColors.onPrimary : AppColors.primary),
            )
          : Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: allDone
                    ? AppColors.onPrimary
                    : canFinish
                        ? AppColors.onSurface
                        : AppColors.onSurfaceVariant,
              ),
            ),
    );

    if (!allDone) {
      return Padding(
        key: _finishKey,
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        child: button,
      );
    }

    // Every set done: a small celebration card around the button.
    final volume = _totalVolume;
    final summary = [
      '$_completedSetCount sets',
      '${formatThousands(_completedReps)} reps',
      if (volume > 0) '${formatThousands(volume)} kg lifted',
    ].join(' · ');

    return Container(
      key: _finishKey,
      margin: const EdgeInsets.only(top: 8, bottom: 32),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.16),
            AppColors.surfaceContainerLow,
          ],
        ),
      ),
      child: Column(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.4, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (_, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.emoji_events_rounded,
                  size: 30, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'EVERY SET DONE',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            summary,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          button,
        ],
      ),
    );
  }

  TextStyle _labelStyle({double fontSize = 10, double letterSpacing = 1.5}) {
    return GoogleFonts.manrope(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: letterSpacing,
      color: AppColors.onSurfaceVariant,
    );
  }

  /// e.g. "3 × 10 · 20 KG · CHEST"
  String _planSummary(ExerciseSessionState ex) {
    final first = ex.sets.isNotEmpty ? ex.sets.first : null;
    return [
      '${ex.sets.length} × ${first?.reps ?? 0}',
      if (ex.tracksWeight && first != null && first.weightKg > 0)
        '${formatKg(first.weightKg)} KG',
      if (ex.muscleGroup.isNotEmpty) ex.muscleGroup.toUpperCase(),
    ].join(' · ');
  }

  /// e.g. "3 SETS · 1,200 KG · RPE 7"
  String _doneSummary(ExerciseSessionState ex) {
    final volume = ex.sets
        .asMap()
        .entries
        .where((e) => ex.completedSets.contains(e.key))
        .fold<double>(0, (sum, e) => sum + e.value.reps * e.value.weightKg);
    return [
      '${ex.sets.length} SETS',
      if (ex.tracksWeight && volume > 0) '${formatThousands(volume)} KG',
      if (ex.rpeRated) 'RPE ${ex.rpe}',
    ].join(' · ');
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
                Pressable(
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

/// Cards slide up and fade in one after another when the screen opens.
/// Plays once: later rebuilds keep the same tween, so it doesn't restart.
class _StaggeredEntrance extends StatelessWidget {
  final int index;
  final Widget child;

  const _StaggeredEntrance({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;

    final delayMs = (index * 70).clamp(0, 420);
    final totalMs = 340 + delayMs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: totalMs),
      curve: Interval(delayMs / totalMs, 1, curve: Curves.easeOutCubic),
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 18),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
