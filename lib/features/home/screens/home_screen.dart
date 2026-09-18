import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/theme/app_colors.dart';
import '../../onboarding/services/user_profile_service.dart';
import '../../social/screens/find_users_screen.dart';
import '../../social/services/public_profile_service.dart';
import '../../social/widgets/activity_log_card.dart';
import '../../workout/screens/workout_active_screen.dart';
import '../../workout/services/workout_plan_service.dart';
import '../../workout/screens/workout_preview_screen.dart';
import '../../workout/screens/workout_log_detail_screen.dart';
import '../../workout/services/workout_log_service.dart';
import '../../workout/services/weekly_summary_service.dart';
import '../../workout/services/schedule_matcher.dart';
import '../../workout/services/adapt_service.dart';
import '../widgets/plan_changes_dialog.dart';
import '../widgets/missed_day_dialog.dart';


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

  // Returns a greeting based on current hour
  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final feedLogs = _allLogs.take(_feedDisplayLimit).toList();

    return Scaffold(
      backgroundColor: AppColors.surface,
      // No AppBar — matches your design spec
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 1.5,
                ),
              )
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
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(),
                            if (_loadError != null) ...[
                              const SizedBox(height: 16),
                              _buildLoadErrorCard(_loadError!),
                            ],
                            const SizedBox(height: 24),
                            if (_weekNumber != null) ...[
                              _buildWeekIndicator(),
                              const SizedBox(height: 12),
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

  // Header: greeting + name 
  Widget _buildHeader() {
    final name = _profile?['name'] as String? ?? 'Athlete';
    // Capitalize first letter only
    final displayName =
        name.isNotEmpty ? name[0].toUpperCase() + name.substring(1) : 'Athlete';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greeting.toUpperCase(),
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                displayName,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FindUsersScreen()),
          ),
          child: Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(top: 4),
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

  // Small mesocycle indicator — "WEEK N" label, with a DELOAD pill 
  Widget _buildWeekIndicator() {
    final weekNumber = _weekNumber!;
    final isDeloadWeek = weekNumber % 4 == 0;

    return Row(
      children: [
        Text(
          'WEEK $weekNumber',
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
            color: AppColors.onSurfaceVariant,
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

    final isRest = _todayDay!['dayType'] == 'rest';

    if (isRest) {
      return _buildHeroRestDay(goal);
    } else {
      return _buildHeroWorkoutDay(goal, experience);
    }
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
          _buildWeeklyCalendar(),
          const SizedBox(height: 16),
          _buildDailyEvolutionChip(goal),
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

  // Hero: rest day
  Widget _buildHeroRestDay(String goal) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.7,
              child: Image.asset(
                'assets/images/rest_day.jpg',
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWeeklyCalendar(),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(48),
                ),
                child: Text('REST DAY',
                    style: GoogleFonts.manrope(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                        color: AppColors.onSurfaceVariant)),
              ),
              const Spacer(),
              Text(goal.toUpperCase(),
                  style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: AppColors.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 20),
          Text('RECOVERY\nPROTOCOL',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                  height: 1.15)),
          const SizedBox(height: 8),
          Text(
            'Your muscles grow during rest. Today is part of the plan — embrace recovery.',
            style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
                height: 1.5),
          ),
          const SizedBox(height: 24),
          // Show next workout day
          Text('CHECK THE SCHEDULE TAB FOR YOUR NEXT SESSION',
              style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: AppColors.onSurfaceVariant.withValues(alpha: 0.4))),
        ],
      ),
          ),
        ],
      ),
    );
  }

  // Hero: workout day
  Widget _buildHeroWorkoutDay(String goal, String experience) {
    final workoutName = _todayDay!['workoutName'] as String? ?? 'Workout';
    final focusDescription =
        _todayDay!['focusDescription'] as String? ?? '';
    final durationMins = _todayDay!['durationMinutes'] as int? ?? 0;
    final exercises =
        (_todayDay!['exercises'] as List?)?.cast<Map<String, dynamic>>() ??
            [];
    final isCompleted = _logForDate(DateTime.now()) != null;

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.7,
              child: Image.asset(
                'assets/images/workout_day.jpg',
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          _buildWeeklyCalendar(),
          const SizedBox(height: 16),
          _buildDailyEvolutionChip(goal),
          const SizedBox(height: 20),

          // Workout name
          Text(
            workoutName.toUpperCase(),
            style: GoogleFonts.spaceGrotesk(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
                height: 1.15),
          ),

          const SizedBox(height: 4),

          Text(focusDescription,
              style: GoogleFonts.manrope(
                  fontSize: 13,
                  color: AppColors.onSurfaceVariant,
                  height: 1.5)),

          const SizedBox(height: 16),

          // Duration + exercise count
          Row(
            children: [
              Icon(Icons.timer_outlined,
                  size: 14, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('$durationMins MIN',
                  style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                      color: AppColors.onSurfaceVariant)),
              const SizedBox(width: 16),
              Icon(Icons.fitness_center_rounded,
                  size: 14, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('${exercises.length} EXERCISES',
                  style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                      color: AppColors.onSurfaceVariant)),
            ],
          ),

          const SizedBox(height: 24),

          // Start Workout CTA — unclickable once today's session is logged
          ElevatedButton(
            onPressed: isCompleted ? null : () => _startTodaysWorkout(),
            style: isCompleted
                ? ElevatedButton.styleFrom(
                    disabledBackgroundColor: AppColors.surfaceContainerLowest,
                    disabledForegroundColor: AppColors.onSurfaceVariant,
                  )
                : null,
            child: Text(isCompleted ? 'COMPLETED ✓' : 'START WORKOUT →',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5)),
          ),
              ],
            ),
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

  // Shared chip
  Widget _buildDailyEvolutionChip(String goal) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(48),
          ),
          child: Text('DAILY EVOLUTION',
              style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: AppColors.primary)),
        ),
        const Spacer(),
        Text(goal.toUpperCase(),
            style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                color: AppColors.onSurfaceVariant)),
      ],
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

  // Section label
  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }

  // Weekly calendar
  Widget _buildWeeklyCalendar() {
    final today = DateTime.now();
    final startDate = today.subtract(const Duration(days: 3));
    final days = List.generate(7, (index) => startDate.add(Duration(days: index)));

    return SizedBox(
      height: 80,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: days.map((date) {
            final isToday = date.year == today.year &&
                date.month == today.month &&
                date.day == today.day;

            final planDay = _resolvedDayForDate(date);
            final isWorkoutDay = planDay != null && planDay['dayType'] != 'rest';
            final isCompleted = isWorkoutDay && _logForDate(date) != null;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => _onCalendarDayTap(date),
                child: Container(
                  width: 44,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: BoxDecoration(
                    color: isToday
                        ? AppColors.primary
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isToday
                          ? AppColors.primary
                          : AppColors.outlineVariant,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${date.day}',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isToday ? Colors.white : AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _weekdayLabel(date.weekday),
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isToday
                              ? Colors.white.withValues(alpha: 0.92)
                              : AppColors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Completion indicator — only meaningful for workout
                      // days; rest days and days with no plan show nothing.
                      SizedBox(
                        height: 6,
                        child: isWorkoutDay
                            ? Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isCompleted
                                      ? (isToday ? Colors.white : AppColors.primary)
                                      : Colors.transparent,
                                  border: isCompleted
                                      ? null
                                      : Border.all(
                                          color: isToday
                                              ? Colors.white54
                                              : AppColors.outlineVariant,
                                          width: 1,
                                        ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _weekdayLabel(int weekday) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[weekday - 1];
  }
}