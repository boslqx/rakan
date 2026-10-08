import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/theme/app_colors.dart';
import '../../onboarding/services/user_profile_service.dart';
import '../../social/screens/find_users_screen.dart';
import '../../social/services/public_profile_service.dart';
import '../../social/widgets/activity_log_card.dart';
import '../../workout/data/exercise_data.dart';
import '../../workout/services/workout_plan_service.dart';
import '../../workout/screens/workout_preview_screen.dart';
import '../../workout/screens/workout_log_detail_screen.dart';
import '../../workout/services/workout_log_service.dart';
import '../../workout/services/weekly_summary_service.dart';
import '../../workout/services/schedule_matcher.dart';
import '../../workout/services/adapt_service.dart';
import '../../workout/widgets/exercise_media.dart';
import '../widgets/plan_changes_dialog.dart';
import '../widgets/missed_day_dialog.dart';
import '../../../shared/utils/number_format.dart';
import '../../../shared/widgets/pressable.dart';
import '../../../shared/widgets/skeleton.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // will create a proper UserProfile model in Phase 2.
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  List<Map<String, dynamic>> _allLogs = [];
  List<Map<String, dynamic>> _planDays = [];
  List<Map<String, dynamic>> _scheduleOverrides = [];

  Map<String, dynamic>? _todayDay;
  String? _loadError;
  String? _debugUid;
  int? _weekNumber;

  static const int _calendarLogScanLimit = 30;
  static const int _feedDisplayLimit = 5;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _debugUid = uid;

    Map<String, dynamic>? profile;
    List<Map<String, dynamic>> allLogs = [];
    Map<String, dynamic>? plan;
    List<Map<String, dynamic>> scheduleOverrides = [];
    String? loadError;

    try {
      profile = await UserProfileService().getUserProfile(uid);
      // Backfills the public users/{uid} doc's displayName/photo from the
      // private profile — fire-and-forget, cheap merge-write. Covers
      // accounts that uploaded a photo before the social feature existed
      // (and so never had it synced), without needing a one-time migration.
      if (profile != null) {
        PublicProfileService().syncPublicProfile(
          uid: uid,
          displayName: profile['name'] as String?,
          photoBase64: profile['profilePictureBase64'] as String?,
        );
      }
    } catch (e, st) {
      debugPrint('HomeScreen: profile load failed for uid=$uid: $e');
      debugPrint(st.toString());
      loadError = 'Unable to load your profile. Please check your network.';
    }

    try {
      allLogs = await WorkoutLogService()
          .getRecentLogs(uid, limit: _calendarLogScanLimit);
    } catch (e, st) {
      debugPrint('HomeScreen: recent logs load failed for uid=$uid: $e');
      debugPrint(st.toString());
      loadError ??= 'Unable to load workout history. Please try again.';
    }

    try {
      plan = await WorkoutPlanService().getActivePlan(uid);
      debugPrint('HomeScreen: current uid=$uid activePlanExists=${plan != null}');
    } catch (e, st) {
      debugPrint('HomeScreen: plan load failed for uid=$uid: $e');
      debugPrint(st.toString());
      loadError ??= 'Unable to load your workout plan. Please try again.';
    }

    try {
      scheduleOverrides = await WorkoutPlanService().getScheduleOverrides(uid);
    } catch (e, st) {
      debugPrint('HomeScreen: schedule overrides load failed for uid=$uid: $e');
      debugPrint(st.toString());
    }

    WeeklySummaryService().checkAndGenerateWeeklySummary(uid);
    // Fire-and-forget; a no-op once old inline photos have been moved.
    WorkoutLogService().migrateLegacyProgressPhotos(uid);

    Map<String, dynamic>? todayDay;
    List<Map<String, dynamic>> planDays = [];
    if (plan != null) {
      planDays = (plan['days'] as List).cast<Map<String, dynamic>>();
      todayDay = ScheduleMatcher.resolvedDayForDate(
        planDays, scheduleOverrides, DateTime.now());
    }

    if (mounted) {
      setState(() {
        _profile = profile;
        _allLogs = allLogs;
        _planDays = planDays;
        _scheduleOverrides = scheduleOverrides;
        _todayDay = todayDay;
        _loadError = loadError;
        _weekNumber = plan?['weekNumber'] as int?;
        _isLoading = false;
      });
      // Check for missed days, then the weekly recap, after the initial
      // load and UI are ready. Missed days first — resolving one can
      // change what's scheduled today/this week, so it takes priority.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _checkForMissedDays();
        if (mounted) await _checkForWeeklySummary();
      });
    }
  }

  Future<void> _checkForMissedDays() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // findMissedDays also auto-resolves (as skipped) anything past the
    // 7-day reschedule window before returning — autoSkipped is what it
    // just resolved, shown read-only; actionable is what's still live.
    final swept = await AdaptService().findMissedDays(uid);
    if ((swept.actionable.isEmpty && swept.autoSkipped.isEmpty) || !mounted) {
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => MissedDayDialog(
        uid: uid,
        actionable: swept.actionable,
        autoSkipped: swept.autoSkipped,
      ),
    );

    // A reschedule may have added a schedule override that affects what's
    // shown today/this week — refresh just that state (not the full
    // _loadProfile, which would re-queue the missed-day/plan-changes
    // checks and could double-show the plan changes dialog).
    if (mounted) await _refreshScheduleOverrides();
  }

  Future<void> _refreshScheduleOverrides() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final scheduleOverrides = await WorkoutPlanService().getScheduleOverrides(uid);
      if (!mounted) return;
      setState(() {
        _scheduleOverrides = scheduleOverrides;
        _todayDay = ScheduleMatcher.resolvedDayForDate(
            _planDays, scheduleOverrides, DateTime.now());
      });
    } catch (e, st) {
      debugPrint('HomeScreen: schedule overrides refresh failed for uid=$uid: $e');
      debugPrint(st.toString());
    }
  }

  /// Shows the weekly recap popup once a new summary is due — it surfaces
  /// progress (sessions/avg RPE/volume) even on weeks with no plan changes,
  /// so `changes` may be empty; see `getLatestUnacknowledgedChanges`.
  Future<void> _checkForWeeklySummary() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final summary = await WeeklySummaryService().getLatestUnacknowledgedChanges(uid);
    if (summary == null || !mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PlanChangesDialog(
        changes: summary['changes'] as List<dynamic>,
        trend: summary['trend'] as String?,
        sessionsCompleted: summary['sessionsCompleted'] as int?,
        avgRpe: (summary['avgRpe'] as num?)?.toDouble(),
        totalVolume: (summary['totalVolume'] as num?)?.toDouble(),
      ),
    );

    await WeeklySummaryService().acknowledgeChanges(uid, summary['id'] as String);
  }

  // Calendar → plan day / log resolution. Goes through
  // ScheduleMatcher.resolvedDayForDate so a Phase 25 reschedule override
  // for this specific date takes precedence over the recurring weekday
  // template — the same lookup the "start workout" flow uses.
  Map<String, dynamic>? _resolvedDayForDate(DateTime date) {
    return ScheduleMatcher.resolvedDayForDate(_planDays, _scheduleOverrides, date);
  }

  /// Finds a completed workout log whose completed
  Map<String, dynamic>? _logForDate(DateTime date) {
    return ScheduleMatcher.logForDate(_allLogs, date);
  }

  /// TODAY is the only date a workout can be started or resumed from the
  /// calendar. Past and future dates are view-only — tapping them shows a
  /// status sheet (completed / skipped / upcoming) rather than launching
  /// anything, so the calendar can't be used to "start" a workout early or
  /// re-do/skip-ahead into a day that isn't the current one.
  void _onCalendarDayTap(DateTime date) {
    final day = _resolvedDayForDate(date);

    if (day == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No plan set for this day yet.', style: GoogleFonts.manrope()),
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
      return;
    }

    if (day['dayType'] == 'rest') {
      _showRestDaySheet(_goalLabel(_profile?['fitnessGoal'] as String?));
      return;
    }

    final today = DateTime.now();
    final isToday = date.year == today.year &&
        date.month == today.month &&
        date.day == today.day;
    final existingLog = _logForDate(date);

    if (isToday) {
      if (existingLog != null) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => WorkoutLogDetailScreen(log: existingLog)),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => WorkoutPreviewScreen(day: day)),
        );
      }
      return;
    }

    final isFuture = DateTime(date.year, date.month, date.day)
        .isAfter(DateTime(today.year, today.month, today.day));

    _showWorkoutStatusSheet(
      day: day,
      date: date,
      isFuture: isFuture,
      existingLog: existingLog,
    );
  }

  /// View-only status sheet for any workout day that isn't today.
  void _showWorkoutStatusSheet({
    required Map<String, dynamic> day,
    required DateTime date,
    required bool isFuture,
    required Map<String, dynamic>? existingLog,
  }) {
    final workoutName = day['workoutName'] as String? ?? 'Workout';

    final IconData icon;
    final Color color;
    final String statusLabel;
    final String description;

    if (existingLog != null) {
      icon = Icons.check_circle_rounded;
      color = AppColors.primary;
      statusLabel = 'Completed';
      description = 'You completed this session on ${_weekdayLabel(date.weekday)}.';
    } else if (isFuture) {
      icon = Icons.event_rounded;
      color = AppColors.onSurfaceVariant;
      statusLabel = 'Upcoming';
      description = 'This session unlocks when its day arrives.';
    } else {
      icon = Icons.remove_circle_outline_rounded;
      color = AppColors.error;
      statusLabel = 'Skipped';
      description = 'This session\'s day has passed without a logged workout.';
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 20),
            Text(statusLabel,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface)),
            const SizedBox(height: 6),
            Text(workoutName,
                style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 12),
            Text(
              description,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                  fontSize: 14, color: AppColors.onSurfaceVariant, height: 1.5),
            ),
            if (existingLog != null) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WorkoutLogDetailScreen(log: existingLog),
                      ),
                    );
                  },
                  child: Text('VIEW SUMMARY',
                      style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.w700, letterSpacing: 1)),
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showRestDaySheet(String goal) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.1),
              ),
              child: const Icon(Icons.bedtime_rounded,
                  color: AppColors.primary, size: 32),
            ),
            const SizedBox(height: 20),
            Text('Rest Day',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface)),
            const SizedBox(height: 8),
            Text(
              'Today is your recovery day. Your muscles grow during rest — this is part of the plan.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: AppColors.onSurfaceVariant,
                  height: 1.5),
            ),
            const SizedBox(height: 24),
            Text('Check the Schedule tab to see your next workout.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant.withValues(alpha: 0.6))),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Future<void> _startTodaysWorkout() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final plan = await WorkoutPlanService().getActivePlan(uid);
    if (plan == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No active plan found.',
                style: GoogleFonts.manrope()),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    final days = (plan['days'] as List).cast<Map<String, dynamic>>();
    final overrides = await WorkoutPlanService().getScheduleOverrides(uid);
    final todayDay =
        ScheduleMatcher.resolvedDayForDate(days, overrides, DateTime.now());

    if (todayDay == null || todayDay['dayType'] == 'rest') {
      if (mounted) {
        _showRestDaySheet(_goalLabel(_profile?['fitnessGoal'] as String?));
      }
      return;
    }

    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WorkoutPreviewScreen(day: todayDay),
        ),
      );
    }
  }

  // Converts the stored fitnessGoal string into a readable label
  String _goalLabel(String? goal) {
    switch (goal) {
      case 'muscleGain':
        return 'Muscle Gain';
      case 'weightLoss':
        return 'Weight Loss';
      case 'endurance':
        return 'Endurance';
      case 'flexibility':
        return 'Flexibility';
      default:
        return 'Performance';
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedLogs = _allLogs.take(_feedDisplayLimit).toList();

    return Scaffold(
      backgroundColor: AppColors.surface,
      // No AppBar — matches your design spec
      body: SafeArea(
        child: _isLoading
            ? _buildLoadingSkeleton()
            : RefreshIndicator(
                // Pull to refresh reloads the profile from Firestore
                onRefresh: _loadProfile,
                color: AppColors.primary,
                backgroundColor: AppColors.surfaceContainerLow,
                child: CustomScrollView(
                  // CustomScrollView lets us mix a pinned header
                  // with a scrollable list below it — more flexible
                  // than a plain Column for feed-style layouts
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(),
                            if (_loadError != null) ...[
                              const SizedBox(height: 16),
                              _buildLoadErrorCard(_loadError!),
                            ],
                            const SizedBox(height: 20),
                            if (_planDays.isNotEmpty) ...[
                              _buildWeekStrip(),
                              const SizedBox(height: 16),
                            ],
                            _buildHeroCard(),
                            const SizedBox(height: 32),
                            _buildSectionLabel('ACTIVITY LOG'),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),

                    feedLogs.isEmpty
                      ? SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.fitness_center_rounded,
                                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
                                      size: 32),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No workouts yet',
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Complete your first session\nto see your activity here.',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.manrope(
                                      fontSize: 13,
                                      color: AppColors.onSurfaceVariant,
                                      height: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => Padding(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                              child: ActivityLogCard(
                                log: feedLogs[index],
                                authorName: _profile?['name'] as String?,
                                authorPhotoBase64:
                                    _profile?['profilePictureBase64'] as String?,
                                ownerUid: FirebaseAuth.instance.currentUser?.uid,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        WorkoutLogDetailScreen(log: feedLogs[index]),
                                  ),
                                ),
                              ),
                            ),
                            childCount: feedLogs.length,
                          ),
                        ),

                    // Bottom padding so last card isn't cut off
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 32),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  // Header: one compact row — today's date and where you are in the plan
  // (rather than a greeting that took two lines and said nothing new),
  // the streak, and people search.
  Widget _buildHeader() {
    final today = _today;
    final weekNumber = _weekNumber;
    final isDeloadWeek = weekNumber != null && weekNumber % 4 == 0;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_weekdayNames[today.weekday - 1]} · ${today.day} ${_monthLabels[today.month - 1]}'
                    .toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _labelStyle(),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      weekNumber != null ? 'Week $weekNumber' : 'No plan yet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                        height: 1.15,
                      ),
                    ),
                  ),
                  if (isDeloadWeek) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(100), // full roundedness, per design system
                      ),
                      child: Text(
                        'DELOAD',
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _buildStreakChip(_workoutStreak(today)),
        const SizedBox(width: 8),
        Pressable(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FindUsersScreen()),
          ),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person_search_rounded,
                color: AppColors.onSurface, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildStreakChip(int streak) {
    final active = streak > 0;

    return Pressable(
      onTap: () => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              active
                  ? '$streak workout${streak == 1 ? '' : 's'} in a row. Rest days don\'t break your streak — missed workouts do.'
                  : 'Complete a scheduled workout to start a streak. Rest days don\'t break it.',
              style: GoogleFonts.manrope(color: AppColors.onSurface),
            ),
            backgroundColor: AppColors.surfaceContainerHigh,
          ),
        ),
      child: Semantics(
        label: '$streak workout streak',
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? AppColors.primary.withValues(alpha: 0.25)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                size: 17,
                color: active
                    ? AppColors.primary
                    : AppColors.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 4),
              Text(
                '$streak',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: active ? AppColors.onSurface : AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── This week ───────────────────────────────────────────────────────
  /// Monday–Sunday at a glance: each day's status (done / missed / to do /
  /// rest), and progress toward the week's workouts. Seeing progress toward
  /// the week's target is a simple, well-evidenced adherence nudge —
  /// relevant to Objective 3. Days are tappable, same as the old calendar.
  Widget _buildWeekStrip() {
    final today = _today;
    // Built from calendar fields, not Duration arithmetic, so a DST change
    // mid-week can't shift a day to 23:00 the day before.
    final week = List.generate(
        7, (i) => DateTime(today.year, today.month, today.day - today.weekday + 1 + i));
    final monday = week.first;

    final scheduled = <DateTime>{};
    for (final date in week) {
      final day = _resolvedDayForDate(date);
      if (day != null && day['dayType'] != 'rest') scheduled.add(date);
    }
    final doneDates = week.where((d) => _logForDate(d) != null).toSet();
    final doneScheduled = scheduled.where(doneDates.contains).length;

    int minutes = 0;
    for (final log in _allLogs) {
      final at = DateTime.tryParse(log['completedAt'] as String? ?? '');
      if (at != null && !at.isBefore(monday)) {
        minutes += (log['totalDurationMins'] as num?)?.toInt() ?? 0;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: [
                Text('THIS WEEK', style: _labelStyle(fontSize: 11, letterSpacing: 2)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: '$doneScheduled',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                      TextSpan(
                        text: ' / ${scheduled.length} workouts'
                            '${minutes > 0 ? '  ·  $minutes min' : ''}',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ]),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (int i = 0; i < 7; i++) ...[
                if (i > 0) const SizedBox(width: 5),
                Expanded(
                  child: _buildDayCell(
                    week[i],
                    isToday: week[i] == today,
                    isPast: week[i].isBefore(today),
                    isScheduled: scheduled.contains(week[i]),
                    isDone: doneDates.contains(week[i]),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell(
    DateTime date, {
    required bool isToday,
    required bool isPast,
    required bool isScheduled,
    required bool isDone,
  }) {
    final fg = isToday ? AppColors.onPrimary : AppColors.onSurface;
    final muted =
        isToday ? AppColors.onPrimary.withValues(alpha: 0.7) : AppColors.onSurfaceVariant;

    // Done ✓, missed ✕, still to do ○, rest —
    final Widget mark;
    if (isDone) {
      mark = Icon(Icons.check_circle_rounded,
          size: 13, color: isToday ? AppColors.onPrimary : AppColors.primary);
    } else if (isScheduled && isPast) {
      mark = Icon(Icons.close_rounded,
          size: 13, color: AppColors.error.withValues(alpha: 0.8));
    } else if (isScheduled) {
      mark = Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: muted, width: 1.2),
        ),
      );
    } else {
      mark = Container(
        width: 8,
        height: 2,
        decoration: BoxDecoration(
          color: muted.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(1),
        ),
      );
    }

    return Pressable(
      onTap: () => _onCalendarDayTap(date),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isToday
              ? AppColors.primary
              : isDone
                  ? AppColors.primary.withValues(alpha: 0.08)
                  : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isToday ? AppColors.primary : AppColors.outlineVariant,
          ),
        ),
        child: Column(
          children: [
            Text(
              _weekdayLabel(date.weekday)[0],
              style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: muted,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${date.day}',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(height: 13, child: Center(child: mark)),
          ],
        ),
      ),
    );
  }

  // Hero Card: today's workout
  Widget _buildHeroCard() {
    final goal = _goalLabel(_profile?['fitnessGoal'] as String?);
    final experience = _profile?['experienceLevel'] as String? ?? 'beginner';

    // No plan generated yet
    if (_todayDay == null) {
      return _buildHeroNoPlan(goal, experience);
    }

    if (_todayDay!['dayType'] == 'rest') {
      return _buildHeroRestDay(goal);
    }

    final todayLog = _logForDate(DateTime.now());
    return todayLog != null
        ? _buildHeroDone(goal, todayLog)
        : _buildHeroWorkoutDay(goal);
  }

  /// Photo card shared by the hero states. The photos are 5,000–9,000px
  /// wide; decoding them full-size cost ~80–200 MB each, so they're decoded
  /// at twice the screen width (enough to cover the card's height too).
  Widget _buildHeroShell({required String image, required Widget child}) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final width = MediaQuery.sizeOf(context).width;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.surfaceContainerLow,
              child: Image.asset(
                image,
                fit: BoxFit.cover,
                cacheWidth: (width * dpr * 2).round(),
                opacity: const AlwaysStoppedAnimation(0.7),
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
                    Colors.black.withValues(alpha: 0.35),
                    Colors.black.withValues(alpha: 0.8),
                  ],
                ),
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.all(20), child: child),
        ],
      ),
    );
  }

  // Hero: no plan yet
  Widget _buildHeroNoPlan(String goal, String experience) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildHeroChip('GETTING STARTED', icon: Icons.auto_awesome_rounded, highlighted: true),
              const SizedBox(width: 8),
              Expanded(
                child: Text(goal.toUpperCase(),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _labelStyle()),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('YOUR PLAN IS\nBEING PREPARED',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  height: 1.15)),
          const SizedBox(height: 8),
          Text('Complete your first session to\nactivate adaptive training.',
              style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: AppColors.onSurfaceVariant,
                  height: 1.5)),
          const SizedBox(height: 24),
          Row(children: [
            _buildStat(label: 'LEVEL',
                value: experience[0].toUpperCase() + experience.substring(1)),
            const SizedBox(width: 24),
            _buildStat(label: 'GOAL', value: goal),
          ]),
        ],
      ),
    );
  }

  // Hero: rest day — and what's coming next, instead of sending the user
  // off to the Schedule tab to find out.
  Widget _buildHeroRestDay(String goal) {
    final next = _nextSessionAfter(_today);

    return _buildHeroShell(
      image: 'assets/images/rest_day.jpg',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildHeroChip('REST DAY', icon: Icons.bedtime_rounded),
              const SizedBox(width: 8),
              Expanded(
                child: Text(goal.toUpperCase(),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _labelStyle()),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('RECOVER &\nRECHARGE',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  height: 1.15)),
          const SizedBox(height: 8),
          Text(
            'Your muscles grow during rest. Today is part of the plan — embrace recovery.',
            style: GoogleFonts.manrope(
                fontSize: 13, color: AppColors.onSurfaceVariant, height: 1.5),
          ),
          const SizedBox(height: 20),
          if (next != null)
            _buildNextSessionCard(next)
          else
            Text('CHECK THE SCHEDULE TAB FOR YOUR NEXT SESSION',
                style: _labelStyle(color: AppColors.onSurfaceVariant.withValues(alpha: 0.6))),
        ],
      ),
    );
  }

  // Hero: workout day, not trained yet
  Widget _buildHeroWorkoutDay(String goal) {
    final workoutName = _todayDay!['workoutName'] as String? ?? 'Workout';
    final focusDescription =
        _todayDay!['focusDescription'] as String? ?? '';
    final durationMins = _todayDay!['durationMinutes'] as int? ?? 0;
    final exercises =
        (_todayDay!['exercises'] as List?)?.cast<Map<String, dynamic>>() ??
            [];
    final totalSets = exercises.fold<int>(
        0, (sum, ex) => sum + ((ex['sets'] as num?)?.toInt() ?? 0));

    return _buildHeroShell(
      image: 'assets/images/workout_day.jpg',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildHeroChip("TODAY'S SESSION", highlighted: true),
              const SizedBox(width: 8),
              Expanded(
                child: Text(goal.toUpperCase(),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _labelStyle()),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            workoutName.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
                height: 1.15),
          ),
          if (focusDescription.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(focusDescription,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                    fontSize: 13,
                    color: AppColors.onSurfaceVariant,
                    height: 1.5)),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (durationMins > 0)
                _buildGlassChip(Icons.timer_outlined, '$durationMins MIN'),
              _buildGlassChip(Icons.fitness_center_rounded,
                  '${exercises.length} EXERCISE${exercises.length == 1 ? '' : 'S'}'),
              if (totalSets > 0)
                _buildGlassChip(Icons.repeat_rounded, '$totalSets SETS'),
            ],
          ),
          if (exercises.isNotEmpty) ...[
            const SizedBox(height: 16),
            ExerciseThumbStrip(
              exerciseNames: [
                for (final ex in exercises) ex['exerciseName'] as String? ?? '',
              ],
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _startTodaysWorkout,
            child: Text('START WORKOUT →',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
          ),
        ],
      ),
    );
  }

  // Hero: today's workout is already logged — show what was done (the old
  // card just greyed out its button).
  Widget _buildHeroDone(String goal, Map<String, dynamic> log) {
    final workoutName = log['workoutName'] as String? ??
        _todayDay!['workoutName'] as String? ??
        'Workout';
    final minutes = (log['totalDurationMins'] as num?)?.toInt() ?? 0;
    final sets = (log['totalSetsCompleted'] as num?)?.toInt();
    final volume = (log['totalVolume'] as num?)?.toDouble() ?? 0;
    final prs = (log['prExerciseNames'] as List?)?.cast<String>() ?? const [];
    final next = _nextSessionAfter(_today);

    return _buildHeroShell(
      image: 'assets/images/workout_day.jpg',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildHeroChip('DONE TODAY', icon: Icons.check_circle_rounded, highlighted: true),
              const SizedBox(width: 8),
              Expanded(
                child: Text(goal.toUpperCase(),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _labelStyle()),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            workoutName.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
                height: 1.15),
          ),
          const SizedBox(height: 4),
          Text('Session logged — recovery starts now.',
              style: GoogleFonts.manrope(
                  fontSize: 13, color: AppColors.onSurfaceVariant, height: 1.5)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildGlassStat('$minutes', 'MIN')),
              const SizedBox(width: 8),
              Expanded(child: _buildGlassStat(sets == null ? '—' : '$sets', 'SETS')),
              if (volume > 0) ...[
                const SizedBox(width: 8),
                Expanded(child: _buildGlassStat(formatThousands(volume), 'KG VOLUME')),
              ],
            ],
          ),
          if (prs.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildGlassChip(
              Icons.emoji_events_rounded,
              'NEW PR · ${prs.join(', ').toUpperCase()}',
              highlighted: true,
            ),
          ],
          if (next != null) ...[
            const SizedBox(height: 12),
            _buildNextSessionCard(next),
          ],
          const SizedBox(height: 18),
          ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => WorkoutLogDetailScreen(log: log)),
            ),
            child: Text('VIEW SUMMARY',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
          ),
        ],
      ),
    );
  }

  /// The next scheduled workout after [from], looking up to two weeks ahead.
  ({DateTime date, int daysAway, Map<String, dynamic> day})? _nextSessionAfter(
      DateTime from) {
    for (int i = 1; i <= 14; i++) {
      final date = DateTime(from.year, from.month, from.day + i);
      final day = _resolvedDayForDate(date);
      if (day != null && day['dayType'] != 'rest') {
        return (date: date, daysAway: i, day: day);
      }
    }
    return null;
  }

  Widget _buildNextSessionCard(
      ({DateTime date, int daysAway, Map<String, dynamic> day}) next) {
    final exercises =
        (next.day['exercises'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final firstExercise = exercises.isEmpty
        ? null
        : findExerciseByName(exercises.first['exerciseName'] as String? ?? '');
    final minutes = next.day['durationMinutes'] as int? ?? 0;
    final when = next.daysAway == 1
        ? 'TOMORROW'
        : next.daysAway < 7
            ? _weekdayNames[next.date.weekday - 1].toUpperCase()
            : '${_weekdayLabel(next.date.weekday)} ${next.date.day} ${_monthLabels[next.date.month - 1]}'
                .toUpperCase();

    return Pressable(
      onTap: () => _onCalendarDayTap(next.date),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            ExerciseThumb(asset: firstExercise?.thumbnailAsset, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('NEXT SESSION · $when', style: _labelStyle(fontSize: 9)),
                  const SizedBox(height: 3),
                  Text(
                    next.day['workoutName'] as String? ?? 'Workout',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    [
                      '${exercises.length} exercise${exercises.length == 1 ? '' : 's'}',
                      if (minutes > 0) '$minutes min',
                    ].join(' · '),
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroChip(String label, {IconData? icon, bool highlighted = false}) {
    final color = highlighted ? AppColors.primary : AppColors.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.primary.withValues(alpha: 0.16)
            : Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(48),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: color)),
        ],
      ),
    );
  }

  /// Translucent chip that reads over the hero photo.
  Widget _buildGlassChip(IconData icon, String label, {bool highlighted = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlighted
              ? AppColors.primary.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 13,
              color: highlighted ? AppColors.primary : AppColors.onSurfaceVariant),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: AppColors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassStat(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, style: _labelStyle(fontSize: 9, letterSpacing: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadErrorCard(String message) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Small stat block used inside hero card
  Widget _buildStat({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
        ),
      ],
    );
  }

  // ── Loading skeleton ────────────────────────────────────────────────
  /// Mirrors the real layout (header, week strip, hero card, feed) so the
  /// page doesn't jump when data arrives — replaces a lone spinner.
  Widget _buildLoadingSkeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      children: const [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 110, height: 9, radius: 4),
                  SizedBox(height: 7),
                  SkeletonBox(width: 80, height: 16, radius: 6),
                ],
              ),
            ),
            SkeletonBox(width: 52, height: 40, radius: 12),
            SizedBox(width: 8),
            SkeletonBox(width: 40, height: 40, radius: 12),
          ],
        ),
        SizedBox(height: 20),
        SkeletonBox(height: 116, radius: 20),
        SizedBox(height: 16),
        SkeletonBox(height: 340, radius: 24),
        SizedBox(height: 32),
        SkeletonBox(width: 110, height: 10, radius: 4),
        SizedBox(height: 16),
        SkeletonBox(height: 120, radius: 20),
        SizedBox(height: 12),
        SkeletonBox(height: 120, radius: 20),
      ],
    );
  }

  /// Consecutive scheduled workouts completed, counting back from today.
  /// Rest days don't break a streak; today only counts once it's logged
  /// (an unfinished today doesn't break it either). Bounded by the logs
  /// Home already loads (last 30).
  int _workoutStreak(DateTime today) {
    int streak = 0;
    for (int offset = 0; offset < 60; offset++) {
      final date = DateTime(today.year, today.month, today.day - offset);
      final day = _resolvedDayForDate(date);
      final logged = _logForDate(date) != null;
      final isWorkoutDay = day != null && day['dayType'] != 'rest';

      if (logged) {
        streak++;
      } else if (isWorkoutDay && offset > 0) {
        break; // a missed scheduled workout ends the streak
      }
    }
    return streak;
  }

  // Section label
  Widget _buildSectionLabel(String text) {
    return Text(text, style: _labelStyle(fontSize: 11, letterSpacing: 2));
  }

  TextStyle _labelStyle({
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

  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  static const _monthLabels = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _weekdayLabel(int weekday) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[weekday - 1];
  }
}
