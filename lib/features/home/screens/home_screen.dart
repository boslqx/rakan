import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/theme/app_colors.dart';
import '../../onboarding/services/user_profile_service.dart';
import '../../workout/screens/workout_active_screen.dart';
import '../../workout/services/workout_plan_service.dart';
import '../../workout/screens/workout_preview_screen.dart';
import '../../workout/screens/workout_log_detail_screen.dart';
import '../../workout/services/workout_log_service.dart';
import '../../workout/services/weekly_summary_service.dart';


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

  Map<String, dynamic>? _todayDay;
  String? _loadError;
  String? _debugUid;

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
    final todayNumber = DateTime.now().weekday; 

    Map<String, dynamic>? profile;
    List<Map<String, dynamic>> allLogs = [];
    Map<String, dynamic>? plan;
    String? loadError;

    try {
      profile = await UserProfileService().getUserProfile(uid);
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

    WeeklySummaryService().checkAndGenerateWeeklySummary(uid);

    Map<String, dynamic>? todayDay;
    List<Map<String, dynamic>> planDays = [];
    if (plan != null) {
      planDays = (plan['days'] as List).cast<Map<String, dynamic>>();
      todayDay = planDays.firstWhere(
        (d) => d['dayNumber'] == todayNumber,
        orElse: () => {},
      );
      if (todayDay!.isEmpty) todayDay = null;
    }

    if (mounted) {
      setState(() {
        _profile = profile;
        _allLogs = allLogs;
        _planDays = planDays;
        _todayDay = todayDay;
        _loadError = loadError;
        _isLoading = false;
      });
    }
  }

  // Calendar → plan day / log resolution
  Map<String, dynamic>? _planDayForWeekday(int weekday) {
    if (_planDays.isEmpty) return null;
    final match = _planDays.firstWhere(
      (d) => d['dayNumber'] == weekday,
      orElse: () => {},
    );
    return match.isEmpty ? null : match;
  }

  /// Finds a completed workout log whose completed
  Map<String, dynamic>? _logForDate(DateTime date) {
    for (final log in _allLogs) {
      final completedAt = log['completedAt'] as String?;
      if (completedAt == null) continue;
      try {
        final logDate = DateTime.parse(completedAt);
        if (logDate.year == date.year &&
            logDate.month == date.month &&
            logDate.day == date.day) {
          return log;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// TODAY is the only date a workout can be started or resumed from the
  /// calendar. Past and future dates are view-only — tapping them shows a
  /// status sheet (completed / skipped / upcoming) rather than launching
  /// anything, so the calendar can't be used to "start" a workout early or
  /// re-do/skip-ahead into a day that isn't the current one.
  void _onCalendarDayTap(DateTime date) {
    final day = _planDayForWeekday(date.weekday);

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

    final todayNumber = DateTime.now().weekday;
    debugPrint('TODAY WEEKDAY: $todayNumber'); 

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
    final todayDay = days.firstWhere(
      (d) => d['dayNumber'] == todayNumber,
      orElse: () => {},
    );

    if (todayDay.isEmpty || todayDay['dayType'] == 'rest') {
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
                              child: _buildRealLogCard(feedLogs[index]),
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

    return Column(
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

          // Start Workout CTA
          ElevatedButton(
            onPressed: () => _startTodaysWorkout(),
            child: Text('START WORKOUT →',
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

  // Formats a number of kg 
  String _formatVolume(double kg) {
    if (kg <= 0) return '—';
    if (kg >= 1000) return '${(kg / 1000).toStringAsFixed(1)}k kg';
    return '${kg.toStringAsFixed(0)} kg';
  }

  /// Relative day label 
  String _dateTimeLabel(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final diff = DateTime.now().difference(date);
      final String dayLabel;
      if (diff.inDays == 0) {
        dayLabel = 'Today';
      } else if (diff.inDays == 1) {
        dayLabel = 'Yesterday';
      } else {
        dayLabel = '${diff.inDays} days ago';
      }
      final hour24 = date.hour;
      final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
      final minute = date.minute.toString().padLeft(2, '0');
      final meridiem = hour24 < 12 ? 'AM' : 'PM';
      return '$dayLabel • ${hour12.toString().padLeft(2, '0')}:$minute $meridiem';
    } catch (_) {
      return '';
    }
  }

  // Activity feed card 
  Widget _buildRealLogCard(Map<String, dynamic> log) {
    final workoutName = log['workoutName'] as String? ?? 'Workout';
    final completedAt = log['completedAt'] as String? ?? '';
    final totalVolume = (log['totalVolume'] as num?)?.toDouble() ?? 0;
    final durationMins = log['totalDurationMins'] as int? ?? 0;
    final totalSets = log['totalSetsCompleted'] as int?;
    final prReached = log['prReached'] as bool? ?? false;
    final photoBase64 = log['progressPhotoBase64'] as String?;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => WorkoutLogDetailScreen(log: log)),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: icon + title + date/time
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.fitness_center_rounded,
                      color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        workoutName,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _dateTimeLabel(completedAt).toUpperCase(),
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
              ],
            ),
            const SizedBox(height: 20),

            // Stats row
            Row(
              children: [
                Expanded(child: _buildLogStat('VOLUME', _formatVolume(totalVolume))),
                Expanded(child: _buildLogStat('TIME', '${durationMins}m')),
                Expanded(
                  child: _buildLogStat('SETS', totalSets != null ? '$totalSets' : '—'),
                ),
              ],
            ),

            if (prReached) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.emoji_events_rounded,
                            size: 13, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text('PR REACHED',
                            style: GoogleFonts.manrope(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: AppColors.primary,
                            )),
                      ],
                    ),
                  ),
                ],
              ),
            ],

            if (photoBase64 != null && photoBase64.isNotEmpty) ...[
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  base64Decode(photoBase64),
                  width: double.infinity,
                  height: 160,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ],
          ],
        ),
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

            final planDay = _planDayForWeekday(date.weekday);
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

  Widget _buildLogStat(String label, String value) {
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
}