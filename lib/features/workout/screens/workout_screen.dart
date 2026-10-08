import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/theme/app_colors.dart';
import '../services/workout_plan_service.dart';
import '../services/workout_log_service.dart';
import '../services/schedule_matcher.dart';
import '../services/notification_service.dart';
import '../widgets/exercise_media.dart';
import 'workout_day_detail_screen.dart';
import 'exercise_library_screen.dart';
import '../data/exercise_data.dart';
import '../../onboarding/services/user_profile_service.dart';
import '../../../shared/widgets/pressable.dart';

export '../data/exercise_data.dart' show equipmentMatches;

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  // Segment state
  // 0 = Schedule, 1 = Exercise Library
  int _segmentIndex = 0;

  // Schedule state
  Map<String, dynamic>? _plan;
  bool _isLoading = true;
  String? _error;

  // Edit mode: when on, tapping a workout day opens the Replace/Cancel
  // management sheet instead of the normal "view exercises" sheet.
  bool _isEditMode = false;
  bool _isMutating = false; // true while a swap/cancel write is in flight

  /// Recent logs, to mark each day DONE / MISSED for this week.
  List<Map<String, dynamic>> _recentLogs = [];

  final ScrollController _scheduleScroll = ScrollController();
  final GlobalKey _scheduleListKey = GlobalKey();
  Timer? _autoScrollTimer;
  double? _dragPointerY;

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scheduleScroll.dispose();
    super.dispose();
  }

  Future<void> _loadPlan() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final plan = await WorkoutPlanService().getActivePlan(uid);
      // Best-effort: without logs the cards just don't show DONE/MISSED.
      var logs = _recentLogs;
      try {
        logs = await WorkoutLogService().getRecentLogs(uid, limit: 14);
      } catch (e) {
        debugPrint('Schedule: recent logs load failed: $e');
      }
      if (mounted) {
        setState(() {
          _plan = plan;
          _recentLogs = logs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with segment switcher
            _buildHeader(),

            // Content area
            Expanded(
              child: _segmentIndex == 0
                  ? _buildScheduleContent()
                  : const ExerciseLibraryScreen(),
            ),
          ],
        ),
      ),
    );
  }

  // Header
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Screen title
                    Text(
                      _segmentIndex == 0 ? 'SCHEDULE' : 'EXERCISE LIBRARY',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _segmentIndex == 0
                          ? 'Your 7-Day Plan'
                          : 'Master Your Mechanics',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              // Edit-mode toggle — only meaningful on the Schedule segment.
              if (_segmentIndex == 0 && _plan != null)
                Pressable(
                  onTap: () => setState(() => _isEditMode = !_isEditMode),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _isEditMode
                          ? AppColors.primary
                          : AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isEditMode
                              ? Icons.check_rounded
                              : Icons.edit_calendar_rounded,
                          size: 16,
                          color: _isEditMode
                              ? AppColors.onPrimary
                              : AppColors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isEditMode ? 'DONE' : 'EDIT',
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: _isEditMode
                                ? AppColors.onPrimary
                                : AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Segment switcher pills
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(48),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSegmentPill('SCHEDULE', 0),
                _buildSegmentPill('EXERCISE LIBRARY', 1),
              ],
            ),
          ),

          if (_isEditMode) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hold and drag a day onto another to swap them. Tap a day for more options.',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSegmentPill(String label, int index) {
    final isSelected = _segmentIndex == index;
    return Pressable(
      onTap: () => setState(() => _segmentIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(48),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: isSelected
                ? AppColors.onPrimary
                : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // Schedule content
  Widget _buildScheduleContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 1.5,
        ),
      );
    }
    if (_error != null) return _buildError();
    if (_plan == null) return _buildNoPlan();
    return _buildPlan();
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.error,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load plan',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() => _isLoading = true);
                _loadPlan();
              },
              child: Text(
                'Retry',
                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoPlan() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.fitness_center_rounded,
              color: AppColors.onSurfaceVariant,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'No active plan',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Complete onboarding to generate\nyour personalized workout plan.',
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlan() {
    final days = (_plan!['days'] as List).cast<Map<String, dynamic>>();

    return RefreshIndicator(
      onRefresh: _loadPlan,
      color: AppColors.primary,
      backgroundColor: AppColors.surfaceContainerLow,
      child: CustomScrollView(
        key: _scheduleListKey,
        controller: _scheduleScroll,
        slivers: [
          SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _isMutating
                  ? const Padding(
                      padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        color: AppColors.primary,
                        backgroundColor: AppColors.surfaceContainerHigh,
                      ),
                    )
                  : const SizedBox(height: 10),
            ),
          ),
          // The overview is for reading the week; edit mode trades it for
          // compact rows so the whole week fits for drag-and-drop.
          if (!_isEditMode)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: _buildPlanOverview(days),
              ),
            ),
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final day = days[index];
              return Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, _isEditMode ? 8 : 12),
                child: _isEditMode ? _buildEditDayRow(day) : _buildDayCard(day),
              );
            }, childCount: days.length),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  // ── This week, against the plan ───────────────────────────────────────

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// This week's calendar date for a plan day (dayNumber 1 = Monday).
  DateTime _dateThisWeek(int dayNumber) {
    final t = _today;
    return DateTime(t.year, t.month, t.day - t.weekday + dayNumber);
  }

  bool _isDoneThisWeek(Map<String, dynamic> day) =>
      ScheduleMatcher.logForDate(
        _recentLogs,
        _dateThisWeek(day['dayNumber'] as int),
      ) !=
      null;

  static List<Map<String, dynamic>> _exercisesOf(Map<String, dynamic> day) =>
      (day['exercises'] as List?)?.cast<Map<String, dynamic>>() ?? [];

  static int _setsOf(Map<String, dynamic> day) => _exercisesOf(
    day,
  ).fold<int>(0, (sum, ex) => sum + ((ex['sets'] as num?)?.toInt() ?? 0));

  // ── Plan overview ─────────────────────────────────────────────────────

  /// The week at a glance — how the load is spread across days, and how
  /// many sets each muscle group gets. The second is what to check when
  /// adjusting the plan: it shows at once if a muscle is over- or
  /// under-served.
  Widget _buildPlanOverview(List<Map<String, dynamic>> days) {
    final planName = _plan!['planName'] as String? ?? '7-Day Plan';
    final weekNumber = _plan!['weekNumber'] as int?;
    final workoutDays = days.where((d) => d['dayType'] == 'workout').toList();
    final totalMinutes = workoutDays.fold<int>(
      0,
      (sum, d) => sum + ((d['durationMinutes'] as num?)?.toInt() ?? 0),
    );
    final totalSets = workoutDays.fold<int>(0, (sum, d) => sum + _setsOf(d));

    final setsByMuscle = <String, int>{};
    for (final day in workoutDays) {
      for (final ex in _exercisesOf(day)) {
        final name = ex['exerciseName'] as String? ?? '';
        final group = (ex['muscleGroup'] as String?)?.isNotEmpty == true
            ? ex['muscleGroup'] as String
            : findExerciseByName(name)?.muscleGroup ?? 'Other';
        setsByMuscle[group] =
            (setsByMuscle[group] ?? 0) + ((ex['sets'] as num?)?.toInt() ?? 0);
      }
    }
    final muscleRows = setsByMuscle.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxMuscleSets = muscleRows.isEmpty ? 1 : muscleRows.first.value;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            weekNumber != null
                ? 'CURRENT CYCLE · WEEK $weekNumber'
                : 'CURRENT CYCLE',
            style: _label(),
          ),
          const SizedBox(height: 4),
          Text(
            planName,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 18),
          _buildWeekLoadChart(days),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildOverviewStat(
                  '${workoutDays.length}',
                  'TRAINING DAYS',
                ),
              ),
              Expanded(
                child: _buildOverviewStat('$totalMinutes', 'MIN / WEEK'),
              ),
              Expanded(child: _buildOverviewStat('$totalSets', 'SETS / WEEK')),
            ],
          ),
          if (muscleRows.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Divider(height: 1, color: AppColors.outlineVariant),
            const SizedBox(height: 14),
            Text('WEEKLY SETS BY MUSCLE', style: _label()),
            const SizedBox(height: 10),
            for (final row in muscleRows.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 84,
                      child: Text(
                        row.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          height: 6,
                          color: AppColors.surfaceContainerHigh,
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: row.value / maxMuscleSets,
                            heightFactor: 1,
                            child: const ColoredBox(color: AppColors.primary),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      child: Text(
                        '${row.value}',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// One bar per weekday, height = session length. Done this week is solid,
  /// missed is tinted red, still to come is muted; rest days are a dot.
  Widget _buildWeekLoadChart(List<Map<String, dynamic>> days) {
    const maxBar = 44.0;
    final byNumber = {for (final d in days) d['dayNumber'] as int: d};
    final longest = days.fold<int>(
      1,
      (m, d) => math.max(m, (d['durationMinutes'] as num?)?.toInt() ?? 0),
    );
    final today = _today;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (int n = 1; n <= 7; n++) ...[
          if (n > 1) const SizedBox(width: 8),
          Expanded(
            child: Builder(
              builder: (context) {
                final day = byNumber[n];
                final isWorkout = day != null && day['dayType'] == 'workout';
                final date = _dateThisWeek(n);
                final isToday = date == today;
                final done = isWorkout && _isDoneThisWeek(day);
                final missed = isWorkout && !done && date.isBefore(today);
                final minutes = (day?['durationMinutes'] as num?)?.toInt() ?? 0;

                final Widget bar = isWorkout
                    ? AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 10 + (maxBar - 10) * (minutes / longest),
                        decoration: BoxDecoration(
                          color: done
                              ? AppColors.primary
                              : missed
                              ? AppColors.error.withValues(alpha: 0.35)
                              : AppColors.surfaceBright,
                          borderRadius: BorderRadius.circular(5),
                          border: isToday && !done
                              ? Border.all(color: AppColors.primary, width: 1.5)
                              : null,
                        ),
                      )
                    : Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(bottom: 2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.onSurfaceVariant.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                      );

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: maxBar,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: bar,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'MTWTFSS'[n - 1],
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                        color: isToday
                            ? AppColors.onSurface
                            : AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOverviewStat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: _label(fontSize: 9, letterSpacing: 1.3)),
      ],
    );
  }

  // ── Day cards ─────────────────────────────────────────────────────────

  Widget _buildDayCard(Map<String, dynamic> day) {
    final isRest = day['dayType'] == 'rest';
    final dayNumber = day['dayNumber'] as int;
    final dayName = day['dayName'] as String;
    final workoutName = day['workoutName'] as String;
    final focusDescription = day['focusDescription'] as String? ?? '';
    final durationMinutes = day['durationMinutes'] as int? ?? 0;
    final exercises = _exercisesOf(day);
    final sets = _setsOf(day);

    final date = _dateThisWeek(dayNumber);
    final isToday = date == _today;
    final isDone = !isRest && _isDoneThisWeek(day);
    final isMissed = !isRest && !isDone && date.isBefore(_today);

    final card = Pressable(
      onTap: isRest ? null : () => _openDayDetail(day),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: isRest
              ? AppColors.surfaceContainerLowest
              : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isRest ? 20 : 6),
            bottomRight: Radius.circular(isRest ? 20 : 6),
          ),
          border: Border.all(
            color: isToday
                ? AppColors.primary.withValues(alpha: 0.45)
                : isRest
                ? AppColors.outlineVariant.withValues(alpha: 0.6)
                : Colors.transparent,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${dayName.toUpperCase()} • DAY ${dayNumber.toString().padLeft(2, '0')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _label(
                      color: isRest
                          ? AppColors.onSurfaceVariant.withValues(alpha: 0.6)
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (isToday) ...[
                  _statusChip('TODAY', filled: true),
                  const SizedBox(width: 6),
                ],
                if (isDone)
                  _statusChip('DONE', icon: Icons.check_rounded)
                else if (isMissed)
                  _statusChip('MISSED', color: AppColors.error)
                else if (isRest)
                  _statusChip('REST', color: AppColors.onSurfaceVariant),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isRest ? 'REST DAY' : workoutName.toUpperCase(),
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isRest
                    ? AppColors.onSurfaceVariant.withValues(alpha: 0.5)
                    : AppColors.onSurface,
                height: 1.1,
              ),
            ),
            if (isRest || focusDescription.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                isRest ? 'Recovery — muscles rebuild today.' : focusDescription,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: isRest
                      ? AppColors.onSurfaceVariant.withValues(alpha: 0.45)
                      : AppColors.onSurfaceVariant,
                ),
              ),
            ],
            if (!isRest) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  _metaItem(Icons.timer_outlined, '$durationMinutes MIN'),
                  _metaItem(
                    Icons.fitness_center_rounded,
                    '${exercises.length} EXERCISE${exercises.length == 1 ? '' : 'S'}',
                  ),
                  if (sets > 0) ...[
                    _metaItem(Icons.repeat_rounded, '$sets SETS'),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: exercises.isEmpty
                        ? Text(
                            'No exercises yet — tap to add some.',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              color: AppColors.onSurfaceVariant,
                            ),
                          )
                        : ExerciseThumbStrip(
                            exerciseNames: [
                              for (final ex in exercises)
                                ex['exerciseName'] as String? ?? '',
                            ],
                            size: 40,
                            overflowColor: AppColors.surfaceContainerHigh,
                          ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [card, if (!isRest) _buildDayReminderRow(day)],
    );
  }

  Widget _statusChip(
    String label, {
    IconData? icon,
    Color? color,
    bool filled = false,
  }) {
    final fg = filled ? AppColors.onPrimary : (color ?? AppColors.primary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? AppColors.primary : fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(48),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaItem(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label, style: _label(fontSize: 11, letterSpacing: 1)),
      ],
    );
  }

  TextStyle _label({
    double fontSize = 10,
    double letterSpacing = 1.5,
    Color color = AppColors.onSurfaceVariant,
  }) {
    return GoogleFonts.manrope(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  // ── Edit mode: compact, draggable rows ────────────────────────────────

  /// Hold a row and drop it on another day to swap them; tap for the rest
  /// of the day's options. Rows are compact so the week fits on screen
  /// while dragging (with edge auto-scroll for the rest).
  Widget _buildEditDayRow(Map<String, dynamic> day) {
    final isRest = day['dayType'] == 'rest';

    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (details) => details.data['id'] != day['id'],
      onAcceptWithDetails: (details) => _swapDays(details.data, day),
      builder: (context, candidates, _) {
        final row = _editRowContent(day, highlighted: candidates.isNotEmpty);
        return LongPressDraggable<Map<String, dynamic>>(
          data: day,
          hapticFeedbackOnStart: true,
          onDragStarted: _startDragAutoScroll,
          onDragUpdate: (details) => _dragPointerY = details.globalPosition.dy,
          onDragEnd: (_) => _stopDragAutoScroll(),
          onDraggableCanceled: (_, _) => _stopDragAutoScroll(),
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: MediaQuery.sizeOf(context).width - 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: _editRowContent(day, lifted: true),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: row),
          child: Pressable(
            onTap: () => isRest
                ? _showManageRestDaySheet(day)
                : _showManageDaySheet(day),
            child: row,
          ),
        );
      },
    );
  }

  Widget _editRowContent(
    Map<String, dynamic> day, {
    bool highlighted = false,
    bool lifted = false,
  }) {
    final isRest = day['dayType'] == 'rest';
    final dayName = day['dayName'] as String? ?? '';
    final exercises = _exercisesOf(day);
    final minutes = day['durationMinutes'] as int? ?? 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.fromLTRB(6, 12, 12, 12),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.primary.withValues(alpha: 0.14)
            : lifted
            ? AppColors.surfaceContainerHigh
            : isRest
            ? AppColors.surfaceContainerLowest
            : AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted
              ? AppColors.primary
              : AppColors.outlineVariant.withValues(alpha: lifted ? 1 : 0.6),
          width: highlighted ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.drag_indicator_rounded,
            size: 20,
            color: AppColors.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 38,
            child: Text(
              dayName.length >= 3
                  ? dayName.substring(0, 3).toUpperCase()
                  : dayName.toUpperCase(),
              style: _label(
                fontSize: 11,
                letterSpacing: 1.2,
                color: AppColors.onSurface,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isRest
                      ? 'Rest day'
                      : day['workoutName'] as String? ?? 'Workout',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isRest
                        ? AppColors.onSurfaceVariant.withValues(alpha: 0.6)
                        : AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  highlighted
                      ? 'Drop to swap'
                      : isRest
                      ? 'Recovery'
                      : '${exercises.length} exercise${exercises.length == 1 ? '' : 's'} · $minutes min',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: highlighted
                        ? AppColors.primary
                        : AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isRest && !lifted)
            Pressable(
              onTap: () => _promptWorkoutNameAndConvert(day),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(48),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.add_rounded,
                      size: 14,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'WORKOUT',
                      style: _label(
                        fontSize: 10,
                        letterSpacing: 1,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            const Icon(
              Icons.more_horiz_rounded,
              color: AppColors.onSurfaceVariant,
            ),
        ],
      ),
    );
  }

  // Edge auto-scroll while dragging a day. Driven by a timer rather than
  // drag updates alone, so holding a row at the edge keeps scrolling.
  void _startDragAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final y = _dragPointerY;
      final box =
          _scheduleListKey.currentContext?.findRenderObject() as RenderBox?;
      if (y == null || box == null || !_scheduleScroll.hasClients) return;

      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      const edge = 72.0;
      double speed = 0;
      if (y < top + edge) {
        speed = -14 * (1 - ((y - top) / edge).clamp(0.0, 1.0));
      } else if (y > bottom - edge) {
        speed = 14 * (1 - ((bottom - y) / edge).clamp(0.0, 1.0));
      }
      if (speed == 0) return;

      final position = _scheduleScroll.position;
      _scheduleScroll.jumpTo(
        (position.pixels + speed).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    });
  }

  void _stopDragAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _dragPointerY = null;
  }

  /// Swaps two days' content, at once on screen (then confirmed by the
  /// reload) — with UNDO rather than a confirm dialog: a swap is fully
  /// reversible, so asking first only slows it down.
  Future<void> _swapDays(
    Map<String, dynamic> dayA,
    Map<String, dynamic> dayB, {
    bool offerUndo = true,
  }) async {
    HapticFeedback.mediumImpact();

    // Optimistic: mirror WorkoutPlanService.swapDays — content moves, the
    // calendar slot (dayNumber/dayName/dayOfWeek, doc id) stays put.
    const slotFields = {'id', 'dayNumber', 'dayName', 'dayOfWeek'};
    final days = (_plan!['days'] as List).cast<Map<String, dynamic>>();
    final ia = days.indexWhere((d) => d['id'] == dayA['id']);
    final ib = days.indexWhere((d) => d['id'] == dayB['id']);
    if (ia == -1 || ib == -1) return;
    Map<String, dynamic> withContent(
      Map<String, dynamic> slot,
      Map<String, dynamic> content,
    ) => {
      for (final e in content.entries)
        if (!slotFields.contains(e.key)) e.key: e.value,
      for (final e in slot.entries)
        if (slotFields.contains(e.key)) e.key: e.value,
    };
    final a = days[ia], b = days[ib];
    setState(() {
      days[ia] = withContent(a, b);
      days[ib] = withContent(b, a);
    });

    final ok = await _runMutation(
      () => WorkoutPlanService().swapDays(
        uid: FirebaseAuth.instance.currentUser!.uid,
        planId: _plan!['id'] as String,
        dayIdA: dayA['id'] as String,
        dayIdB: dayB['id'] as String,
      ),
    );
    if (!mounted || !ok || !offerUndo) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Swapped ${dayA['dayName']} and ${dayB['dayName']}',
            style: GoogleFonts.manrope(color: AppColors.onSurface),
          ),
          backgroundColor: AppColors.surfaceContainerHigh,
          action: SnackBarAction(
            label: 'UNDO',
            textColor: AppColors.primary,
            onPressed: () => _swapDays(dayA, dayB, offerUndo: false),
          ),
        ),
      );
  }

  // ── Per-day "start workout at X" reminder row ─────────────────────────
  // Sits directly under a workout day card with no gap and squared-off
  // top corners, so it reads as a connected extension of that card
  // rather than a separate one. Independent of the blanket weekly
  // reminder in Settings — this is a single day's own start-time alarm.

  Widget _buildDayReminderRow(Map<String, dynamic> day) {
    final enabled = day['reminderEnabled'] as bool? ?? false;
    final hour = day['reminderHour'] as int? ?? 7;
    final minute = day['reminderMinute'] as int? ?? 0;
    final time = TimeOfDay(hour: hour, minute: minute);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: enabled
            ? AppColors.surfaceContainerHigh
            : AppColors.surfaceBright,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
        border: Border(
          left: BorderSide(
            color: enabled
                ? AppColors.primary.withValues(alpha: 0.6)
                : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.alarm_rounded,
            size: 16,
            color: enabled
                ? AppColors.primary
                : AppColors.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Pressable(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? () => _pickDayReminderTime(day) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: enabled
                        ? AppColors.onSurface
                        : AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  child: Text(
                    enabled
                        ? 'START WORKOUT AT ${time.format(context)}'
                        : 'START TIME REMINDER',
                  ),
                ),
              ),
            ),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: enabled,
              onChanged: (value) => _toggleDayReminder(day, value),
              activeColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  /// Flips a single day's reminder on/off, updating the UI immediately
  /// and persisting/scheduling the underlying notification in the
  /// background. Turning it on for the first time opens the time picker
  /// right away so the user sets a start time in the same motion.
  Future<void> _toggleDayReminder(Map<String, dynamic> day, bool value) async {
    final hadTimeSet = day['reminderHour'] != null;
    await _setDayReminder(day, enabled: value);
    if (value && !hadTimeSet && mounted) {
      await _pickDayReminderTime(day);
    }
  }

  Future<void> _pickDayReminderTime(Map<String, dynamic> day) async {
    final hour = day['reminderHour'] as int? ?? 7;
    final minute = day['reminderMinute'] as int? ?? 0;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.primary,
              surface: AppColors.surfaceContainerLow,
              onSurface: AppColors.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;
    await _setDayReminder(
      day,
      enabled: true,
      hour: picked.hour,
      minute: picked.minute,
    );
  }

  /// Applies a reminder change to the specific day both locally (for an
  /// instant, smooth toggle) and durably — Firestore for persistence,
  /// NotificationService for the actual scheduled alarm. Reverts the local
  /// change if either write fails, so the switch never lies about state.
  Future<void> _setDayReminder(
    Map<String, dynamic> day, {
    required bool enabled,
    int? hour,
    int? minute,
  }) async {
    final dayId = day['id'] as String;
    final days = (_plan!['days'] as List).cast<Map<String, dynamic>>();
    final index = days.indexWhere((d) => d['id'] == dayId);
    if (index == -1) return;

    final previous = Map<String, dynamic>.from(days[index]);
    final resolvedHour = hour ?? (day['reminderHour'] as int? ?? 7);
    final resolvedMinute = minute ?? (day['reminderMinute'] as int? ?? 0);
    final dayNumber = day['dayNumber'] as int;
    final workoutName = day['workoutName'] as String? ?? 'Workout';

    setState(() {
      days[index] = {
        ...days[index],
        'reminderEnabled': enabled,
        'reminderHour': resolvedHour,
        'reminderMinute': resolvedMinute,
      };
    });

    try {
      if (enabled) {
        await NotificationService().init();
        final hasPermission = await NotificationService().hasPermission();
        if (!hasPermission) {
          if (mounted) {
            setState(() => days[index] = previous);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Enable notifications for Rakan in system settings',
                  style: GoogleFonts.manrope(color: AppColors.onSurface),
                ),
                backgroundColor: AppColors.surfaceContainerHigh,
              ),
            );
          }
          return;
        }
      }

      final uid = FirebaseAuth.instance.currentUser!.uid;
      await WorkoutPlanService().updateDayReminder(
        uid: uid,
        planId: _plan!['id'] as String,
        dayId: dayId,
        enabled: enabled,
        hour: resolvedHour,
        minute: resolvedMinute,
      );

      if (enabled) {
        final nextAt = await NotificationService().scheduleDayReminder(
          dayNumber: dayNumber,
          workoutName: workoutName,
          hour: resolvedHour,
          minute: resolvedMinute,
        );
        // Tell the user exactly when it will fire. This reminder repeats on
        // THIS card's weekday only, so a card for another day won't fire
        // today — showing the date makes that obvious.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Next reminder: ${NotificationService.describe(nextAt)}',
                style: GoogleFonts.manrope(color: AppColors.onSurface),
              ),
              backgroundColor: AppColors.surfaceContainerHigh,
            ),
          );
        }
      } else {
        await NotificationService().cancelDayReminder(dayNumber);
      }
    } catch (e, stack) {
      debugPrint('_setDayReminder failed: $e\n$stack');
      if (mounted) {
        setState(() => days[index] = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not update reminder',
              style: GoogleFonts.manrope(color: AppColors.onSurface),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ── Edit mode: manage-day sheet (Replace / Cancel) ────────────────────

  void _showManageDaySheet(Map<String, dynamic> day) {
    final workoutName = day['workoutName'] as String? ?? 'Workout';
    final dayName = day['dayName'] as String? ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dayName.toUpperCase(),
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              workoutName,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 24),

            _manageOptionTile(
              icon: Icons.tune_rounded,
              title: 'Edit Exercises',
              subtitle: 'Sets, reps, rest — add, swap or remove',
              onTap: () {
                Navigator.pop(sheetContext);
                _openDayDetail(day);
              },
            ),
            const SizedBox(height: 10),
            _manageOptionTile(
              icon: Icons.swap_horiz_rounded,
              title: 'Move to Another Day',
              subtitle: 'Swap with another day — or drag it there',
              onTap: () {
                Navigator.pop(sheetContext);
                _showReplaceDayPicker(day);
              },
            ),
            const SizedBox(height: 10),
            _manageOptionTile(
              icon: Icons.remove_circle_outline_rounded,
              title: 'Make It a Rest Day',
              subtitle: 'Cancels this workout and its exercises',
              iconColor: AppColors.error,
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmCancelDay(day);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _manageOptionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color iconColor = AppColors.primary,
  }) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  void _showReplaceDayPicker(Map<String, dynamic> day) {
    final days = (_plan!['days'] as List).cast<Map<String, dynamic>>();
    final replacementDays = days.where((d) => d['id'] != day['id']).toList();

    if (replacementDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No other days to swap with.',
            style: GoogleFonts.manrope(),
          ),
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        minChildSize: 0.35,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'SWAP "${(day['workoutName'] as String).toUpperCase()}" WITH',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                itemCount: replacementDays.length,
                itemBuilder: (_, index) {
                  final other = replacementDays[index];
                  final otherExercises =
                      (other['exercises'] as List?)
                          ?.cast<Map<String, dynamic>>() ??
                      [];
                  final isRestDay = other['dayType'] == 'rest';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Pressable(
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _swapDays(day, other);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${(other['dayName'] as String).toUpperCase()} • ${isRestDay ? 'Rest Day' : other['workoutName']}',
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isRestDay
                                        ? 'REST DAY'
                                        : '${otherExercises.length} EXERCISES',
                                    style: GoogleFonts.manrope(
                                      fontSize: 10,
                                      letterSpacing: 1,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.swap_horiz_rounded,
                              color: AppColors.primary,
                            ),
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

  Future<void> _confirmCancelDay(Map<String, dynamic> day) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Cancel This Workout?',
          style: GoogleFonts.spaceGrotesk(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          '${day['dayName']} will be marked as a rest day. Its exercises will be removed from the schedule.',
          style: GoogleFonts.manrope(
            color: AppColors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Keep It',
              style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Cancel Day',
              style: GoogleFonts.manrope(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await _runMutation(
      () => WorkoutPlanService().cancelDay(
        uid: FirebaseAuth.instance.currentUser!.uid,
        planId: _plan!['id'] as String,
        dayId: day['id'] as String,
      ),
    );
  }

  /// Edit mode: manage sheet for rest days — lets the user convert a rest
  /// day into a workout day by naming it, then opens the detail screen to
  /// populate exercises.
  void _showManageRestDaySheet(Map<String, dynamic> day) {
    final dayName = day['dayName'] as String? ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dayName.toUpperCase(),
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Rest Day',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 24),
            _manageOptionTile(
              icon: Icons.fitness_center_rounded,
              title: 'Convert to Workout Day',
              subtitle: 'Turn this rest day into a training day',
              onTap: () {
                Navigator.pop(sheetContext);
                _promptWorkoutNameAndConvert(day);
              },
            ),
            const SizedBox(height: 10),
            _manageOptionTile(
              icon: Icons.swap_horiz_rounded,
              title: 'Move a Workout Here',
              subtitle: 'Swap with one of your training days',
              onTap: () {
                Navigator.pop(sheetContext);
                _showReplaceDayPicker(day);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Prompts for a workout name, converts the rest day to a workout day,
  /// then opens the day detail screen for exercise population.
  Future<void> _promptWorkoutNameAndConvert(Map<String, dynamic> day) async {
    final dayNumber = day['dayNumber'] as int;
    final controller = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'New Workout Name',
          style: GoogleFonts.spaceGrotesk(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: '$dayNumber Workout',
            hintStyle: GoogleFonts.manrope(
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: AppColors.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            filled: true,
            fillColor: AppColors.surfaceContainerHigh,
          ),
          style: GoogleFonts.manrope(color: AppColors.onSurface, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Convert',
              style: GoogleFonts.manrope(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final workoutName = controller.text.trim().isEmpty
        ? '$dayNumber Workout'
        : controller.text.trim();

    final useTemplate = await _showUseTemplateDialog();
    if (!mounted) return;

    Map<String, dynamic>? updatedDay;

    if (useTemplate == true) {
      final muscleGroup = await _pickMuscleGroupSheet();
      if (muscleGroup == null) return;

      final uid = FirebaseAuth.instance.currentUser!.uid;
      final profile = await UserProfileService().getUserProfile(uid);
      final userEquipment =
          (profile?['equipment'] as List?)?.cast<String>() ?? [];
      final userExperience =
          profile?['experienceLevel'] as String? ?? 'beginner';

      final exercises = buildTemplateExercises(
        muscleGroup: muscleGroup,
        userEquipment: userEquipment,
        userExperience: userExperience,
      );

      await _runMutation(() async {
        updatedDay = await WorkoutPlanService().convertRestDayToWorkout(
          uid: uid,
          planId: _plan!['id'] as String,
          dayId: day['id'] as String,
          workoutName: workoutName,
          templateExercises: exercises,
        );
      });
    } else {
      await _runMutation(() async {
        updatedDay = await WorkoutPlanService().convertRestDayToWorkout(
          uid: FirebaseAuth.instance.currentUser!.uid,
          planId: _plan!['id'] as String,
          dayId: day['id'] as String,
          workoutName: workoutName,
        );
      });
    }

    if (!mounted || updatedDay == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkoutDayDetailScreen(
          day: updatedDay!,
          planId: _plan!['id'] as String,
        ),
      ),
    );
  }

  /// Asks if the user wants to start with a pre-built template for the
  /// chosen muscle group, or begin with an empty workout.
  Future<bool?> _showUseTemplateDialog() {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Start with a template?',
          style: GoogleFonts.spaceGrotesk(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Pick a muscle group and we\'ll add 3–4 exercises matched to your equipment and experience level.',
          style: GoogleFonts.manrope(
            color: AppColors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Empty Workout',
              style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Use Template',
              style: GoogleFonts.manrope(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shows the muscle-group picker sheet (Chest, Back, Shoulders, Arms, Legs, Glutes, Core).
  Future<String?> _pickMuscleGroupSheet() {
    const groups = [
      'Chest',
      'Back',
      'Shoulders',
      'Arms',
      'Legs',
      'Glutes',
      'Core',
    ];
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose a focus',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: groups.map((g) {
                return ActionChip(
                  label: Text(
                    g,
                    style: GoogleFonts.manrope(color: AppColors.onSurface),
                  ),
                  backgroundColor: AppColors.surfaceContainerHigh,
                  shape: const StadiumBorder(),
                  onPressed: () => Navigator.pop(ctx, g),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // Template exercise helpers
  static const Map<String, int> _kDifficultyRank = {
    'Beginner': 0,
    'Intermediate': 1,
    'Advanced': 2,
  };

  /// Absolute distance between exercise difficulty and user experience level.
  int _difficultyDistance(String exerciseDifficulty, String userExperience) {
    final exRank = _kDifficultyRank[exerciseDifficulty] ?? 1;
    final normalized = userExperience.isEmpty
        ? 'beginner'
        : userExperience[0].toUpperCase() +
              userExperience.substring(1).toLowerCase();
    final userRank = _kDifficultyRank[normalized] ?? 0;
    return (exRank - userRank).abs();
  }

  /// Template exercise pools per muscle group (exercise names from kExercises).
  /// Note: some exercise `equipment` strings in exercise_data.dart use '/'
  /// to mean "OR" between alternative setups (e.g. 'Bodyweight / Dumbbells, Bench').
  /// See equipmentMatches() for how this is parsed.
  static const Map<String, List<String>> _kMuscleGroupTemplatePools = {
    'Chest': [
      'Push-Up',
      'Dumbbell Bench Press',
      'Dumbbell Flye',
      'Incline Push-Up',
      'Incline Dumbbell Press',
      'Machine Chest Press',
      'Pec Deck Flye',
      'Resistance Band Chest Press',
      'Resistance Band Chest Flye',
      'Dumbbell Floor Press',
    ],
    'Back': [
      'Inverted Row',
      'Dumbbell Row',
      'Lat Pulldown',
      'Seated Cable Row',
      'Pull-Up',
      'Chin-Up',
      'Resistance Band Row',
      'Resistance Band Lat Pulldown',
      'Chest-Supported Dumbbell Row',
      'Single-Arm Cable Row',
    ],
    'Shoulders': [
      'Pike Push-Up',
      'Dumbbell Shoulder Press',
      'Dumbbell Lateral Raise',
      'Dumbbell Front Raise',
      'Dumbbell Rear Delt Flye',
      'Arnold Press',
      'Seated Dumbbell Shoulder Press',
      'Machine Shoulder Press',
      'Resistance Band Lateral Raise',
      'Resistance Band Face Pull',
    ],
    'Arms': [
      'Dumbbell Bicep Curl',
      'Dumbbell Hammer Curl',
      'Dumbbell Tricep Overhead Extension',
      'Tricep Dip',
      'Resistance Band Bicep Curl',
      'Resistance Band Tricep Pushdown',
      'Bench Dip',
      'Dumbbell Concentration Curl',
      'Incline Dumbbell Curl',
      'Dumbbell Skull Crusher',
    ],
    'Legs': [
      'Bodyweight Squat',
      'Reverse Lunge',
      'Dumbbell Goblet Squat',
      'Dumbbell Romanian Deadlift',
      'Split Squat',
      'Bulgarian Split Squat',
      'Step-Up',
      'Wall Sit',
      'Leg Press',
      'Leg Curl',
    ],
    'Glutes': [
      'Glute Bridge',
      'Hip Thrust',
      'Single-Leg Glute Bridge',
      'Frog Pump',
      'Fire Hydrant',
      'Donkey Kick',
      'Dumbbell Hip Thrust',
      'Dumbbell Step-Up',
      'Cable Glute Kickback',
      'Resistance Band Glute Bridge',
    ],
    'Core': [
      'Plank',
      'Crunch',
      'Leg Raise',
      'Mountain Climber',
      'Russian Twist',
      'Dead Bug',
      'Bird Dog',
      'Bicycle Crunch',
      'Flutter Kick',
      'Side Plank',
    ],
  };

  /// Builds a list of template exercises for the given muscle group,
  /// filtered by user's equipment and sorted by difficulty proximity
  /// to the user's experience level.
  List<ExerciseData> buildTemplateExercises({
    required String muscleGroup,
    required List<String> userEquipment,
    required String userExperience,
    int maxExercises = 4,
  }) {
    final pool = _kMuscleGroupTemplatePools[muscleGroup] ?? [];

    final resolved = pool
        .map((name) => findExerciseByName(name))
        .whereType<ExerciseData>()
        .where((ex) => equipmentMatches(ex.equipment, userEquipment))
        .toList();

    resolved.sort(
      (a, b) => _difficultyDistance(
        a.difficulty,
        userExperience,
      ).compareTo(_difficultyDistance(b.difficulty, userExperience)),
    );

    return resolved.take(maxExercises).toList();
  }

  /// Runs a swap/cancel write, showing a lightweight loading state and
  /// reloading the plan from Firestore afterward so the UI reflects the
  /// authoritative saved state rather than a locally-guessed one. Returns
  /// whether the write succeeded.
  Future<bool> _runMutation(Future<void> Function() action) async {
    if (_isMutating) return false;
    setState(() => _isMutating = true);
    try {
      await action();
      await _loadPlan();
      return true;
    } catch (e) {
      // Put back anything shown optimistically.
      await _loadPlan();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Something went wrong. Please try again.',
              style: GoogleFonts.manrope(),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  /// Opens the full-screen, editable day view (WorkoutDayDetailScreen)
  /// instead of the old bottom sheet — lets the user reorder, add/remove
  /// exercises, and view exercise details, then start the workout
  /// directly from there if it's today.
  Future<void> _openDayDetail(Map<String, dynamic> day) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            WorkoutDayDetailScreen(day: day, planId: _plan!['id'] as String),
      ),
    );
    // Always refresh on return — cheap, and correctly reflects any
    // add/remove/reorder edits made on the detail screen without needing
    // to track exactly what changed.
    _loadPlan();
  }
}
