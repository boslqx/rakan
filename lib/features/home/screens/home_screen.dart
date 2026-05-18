import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/theme/app_colors.dart';
import '../../onboarding/services/user_profile_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../workout/screens/workout_active_screen.dart';
import '../../workout/services/workout_plan_service.dart';
import '../../workout/screens/workout_preview_screen.dart';
import '../../workout/services/workout_log_service.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // will create a proper UserProfile model in Phase 2.
  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  List<Map<String, dynamic>> _recentLogs = [];
  Map<String, dynamic>? _todayDay; 

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final todayNumber = DateTime.now().weekday; // Mon=1 ... Sun=7

    final results = await Future.wait([
      UserProfileService().getUserProfile(uid),
      WorkoutLogService().getRecentLogs(uid, limit: 5),
      WorkoutPlanService().getActivePlan(uid),
    ]);

    Map<String, dynamic>? todayDay;
    final plan = results[2] as Map<String, dynamic>?;
    if (plan != null) {
      final days = (plan['days'] as List).cast<Map<String, dynamic>>();
      todayDay = days.firstWhere(
        (d) => d['dayNumber'] == todayNumber,
        orElse: () => {},
      );
      if (todayDay!.isEmpty) todayDay = null;
    }

    if (mounted) {
      setState(() {
        _profile = results[0] as Map<String, dynamic>?;
        _recentLogs = (results[1] as List).cast<Map<String, dynamic>>();
        _todayDay = todayDay;
        _isLoading = false;
      });
    }
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
                    color: AppColors.primary.withOpacity(0.1),
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
                        color: AppColors.onSurfaceVariant.withOpacity(0.6))),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
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
    return Scaffold(
      backgroundColor: AppColors.surfaceBright,
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
                            const SizedBox(height: 24),
                            _buildHeroCard(),
                            const SizedBox(height: 32),
                            _buildSectionLabel('ACTIVITY LOG'),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),

                    // Phase 4 will replace these with real workout logs
                    _recentLogs.isEmpty
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
                                      color: AppColors.onSurfaceVariant.withOpacity(0.4),
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
                              child: _buildRealLogCard(_recentLogs[index]),
                            ),
                            childCount: _recentLogs.length,
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

  // ── Hero: no plan yet ─────────────────────────────────────────────────
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

  // ── Hero: rest day ────────────────────────────────────────────────────
  Widget _buildHeroRestDay(String goal) {
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
                  color: AppColors.onSurfaceVariant.withOpacity(0.5),
                  height: 1.15)),
          const SizedBox(height: 8),
          Text(
            'Your muscles grow during rest. Today is part of the plan — embrace recovery.',
            style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.onSurfaceVariant.withOpacity(0.6),
                height: 1.5),
          ),
          const SizedBox(height: 24),
          // Show next workout day
          Text('CHECK THE SCHEDULE TAB FOR YOUR NEXT SESSION',
              style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: AppColors.onSurfaceVariant.withOpacity(0.4))),
        ],
      ),
    );
  }

  // ── Hero: workout day ─────────────────────────────────────────────────
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
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
    );
  }

  // ── Shared chip ───────────────────────────────────────────────────────
  Widget _buildDailyEvolutionChip(String goal) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
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

  // Placeholder log card
  Widget _buildRealLogCard(Map<String, dynamic> log) {
    final workoutName = log['workoutName'] as String? ?? 'Workout';
    final completedAt = log['completedAt'] as String? ?? '';
    final totalVolume = (log['totalVolume'] as num?)?.toDouble() ?? 0;
    final durationMins = log['totalDurationMins'] as int? ?? 0;

    // Convert ISO date string to readable relative time
    String dateLabel = '';
    try {
      final date = DateTime.parse(completedAt);
      final diff = DateTime.now().difference(date);
      if (diff.inDays == 0) {
        dateLabel = 'Today';
      } else if (diff.inDays == 1) {
        dateLabel = 'Yesterday';
      } else {
        dateLabel = '${diff.inDays} days ago';
      }
    } catch (_) {
      dateLabel = '';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  workoutName,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              Text(
                dateLabel,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildLogStat('DURATION', '${durationMins}min'),
              const SizedBox(width: 24),
              _buildLogStat(
                'VOLUME',
                totalVolume > 0
                    ? '${totalVolume.toStringAsFixed(0)}kg'
                    : '—',
              ),
            ],
          ),
        ],
      ),
    );
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