import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';
import '../../../../core/theme/app_colors.dart';
import '../../workout/services/workout_log_service.dart';
import '../../workout/services/workout_plan_service.dart';
import '../../onboarding/models/onboarding_data.dart';
import '../../onboarding/screens/plan_generation_screen.dart';

class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key});

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends State<CoachScreen> {
  // Segmented switch
  int _selectedTab = 0; // 0 = Stats Report, 1 = Recovery Map

  // Auth
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Stats data
  bool _statsLoading = true;
  List<Map<String, dynamic>> _recentLogs = [];
  Map<int, double> _weeklyVolume = {}; // weekday(1-7) → total volume kg
  Map<String, int> _muscleFrequency = {}; // muscleGroup → times trained
  int _workoutsThisWeek = 0;
  int _plannedThisWeek = 0;

  // Recovery / Injury data
  bool _recoveryLoading = true;
  List<Map<String, dynamic>> _injuries = [];
  BodySide _heatmapSide = BodySide.front;
  // Gender read from profile
  BodyGender _bodyGender = BodyGender.male;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadRecovery();
  }

  // DATA LOADING
  Future<void> _loadStats() async {
    if (_uid == null) return;
    setState(() => _statsLoading = true);

    try {
      // Get all recent logs
      final logs = await WorkoutLogService().getRecentLogs(_uid!, limit: 50);

      // Get active plan to count planned workouts this week
      final plan = await WorkoutPlanService().getActivePlan(_uid!);

      // Compute weekly volume 
      final now = DateTime.now();
      // Find start of current week (Monday)
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekStartDate = DateTime(weekStart.year, weekStart.month, weekStart.day);

      final Map<int, double> weeklyVol = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0};
      int workoutsThisWeek = 0;

      for (final log in logs) {
        final completedStr = log['completedAt'] as String? ?? '';
        if (completedStr.isEmpty) continue;
        final completedAt = DateTime.tryParse(completedStr);
        if (completedAt == null) continue;

        final logDate = DateTime(completedAt.year, completedAt.month, completedAt.day);

        // Only count logs from this week
        if (logDate.isAfter(weekStartDate.subtract(const Duration(days: 1)))) {
          final weekday = completedAt.weekday; // 1=Mon, 7=Sun
          final volume = (log['totalVolume'] as num?)?.toDouble() ?? 0.0;
          weeklyVol[weekday] = (weeklyVol[weekday] ?? 0) + volume;
          workoutsThisWeek++;
        }
      }

      // Count planned workout days this week (non-rest days)
      int plannedThisWeek = 0;
      if (plan != null) {
        final days = plan['days'] as List<dynamic>? ?? [];
        for (final day in days) {
          final isRest = day['isRestDay'] as bool? ?? true;
          if (!isRest) plannedThisWeek++;
        }
      }

      // Compute muscle frequency from exerciseLogs subcollections
      final Map<String, int> muscleFreq = {};
      final logDocs = await _db
          .collection('users')
          .doc(_uid)
          .collection('workoutLogs')
          .get();

      for (final logDoc in logDocs.docs) {
        final completedStr = logDoc.data()['completedAt'] as String? ?? '';
        final completedAt = DateTime.tryParse(completedStr);
        if (completedAt == null) continue;
        final logDate = DateTime(completedAt.year, completedAt.month, completedAt.day);
        if (!logDate.isAfter(weekStartDate.subtract(const Duration(days: 1)))) continue;

        final exLogs = await logDoc.reference.collection('exerciseLogs').get();
        for (final ex in exLogs.docs) {
          final muscle = ex.data()['muscleGroup'] as String? ?? 'other';
          muscleFreq[muscle] = (muscleFreq[muscle] ?? 0) + 1;
        }
      }

      setState(() {
        _recentLogs = logs;
        _weeklyVolume = weeklyVol;
        _workoutsThisWeek = workoutsThisWeek;
        _plannedThisWeek = plannedThisWeek;
        _muscleFrequency = muscleFreq;
        _statsLoading = false;
      });
    } catch (e) {
      print('CoachScreen stats error: $e');
      setState(() => _statsLoading = false);
    }
  }

  Future<void> _loadRecovery() async {
    if (_uid == null) return;
    setState(() => _recoveryLoading = true);

    try {
      // Load gender from profile for heatmap body shape
      final profileSnap = await _db
          .collection('users')
          .doc(_uid)
          .collection('profile')
          .doc('data')
          .get();

      final gender = profileSnap.data()?['gender'] as String? ?? 'male';
      _bodyGender = gender == 'female' ? BodyGender.female : BodyGender.male;

      // Load injuries subcollection
      final injurySnap = await _db
          .collection('users')
          .doc(_uid)
          .collection('injuries')
          .get();

      // If no injuries subcollection yet, seed from profile onboarding data
      if (injurySnap.docs.isEmpty) {
        final profileInjuries = profileSnap.data()?['injuries'] as List<dynamic>? ?? [];
        if (profileInjuries.isNotEmpty) {
          await _seedInjuriesFromProfile(profileInjuries);
          // Reload after seeding
          final reloaded = await _db
              .collection('users')
              .doc(_uid)
              .collection('injuries')
              .get();
          setState(() {
            _injuries = reloaded.docs.map((d) => {'id': d.id, ...d.data()}).toList();
            _recoveryLoading = false;
          });
          return;
        }
      }

      setState(() {
        _injuries = injurySnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        _recoveryLoading = false;
      });
    } catch (e) {
      print('CoachScreen recovery error: $e');
      setState(() => _recoveryLoading = false);
    }
  }

  Future<void> _seedInjuriesFromProfile(List<dynamic> profileInjuries) async {
    for (final inj in profileInjuries) {
      final injMap = inj as Map<String, dynamic>;
      await _db
          .collection('users')
          .doc(_uid)
          .collection('injuries')
          .add({
        'region': injMap['region'] ?? '',
        'label': injMap['label'] ?? '',
        'isCustom': injMap['isCustom'] ?? false,
        'status': 'active',
        'loggedAt': FieldValue.serverTimestamp(),
        'recoveredAt': null,
      });
    }
  }

  // BUILD
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildSegmentedSwitch(),
            Expanded(
              child: _selectedTab == 0
                  ? _buildStatsTab()
                  : _buildRecoveryTab(),
            ),
          ],
        ),
      ),
    );
  }

  // Header
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BIOMETRIC ANALYSIS',
            style: GoogleFonts.manrope(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'AI PERFORMANCE\nINSIGHTS',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }

  // Segmented switch
  Widget _buildSegmentedSwitch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            _buildSegmentBtn('STATS REPORT', 0),
            _buildSegmentBtn('RECOVERY MAP', 1),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentBtn(String label, int index) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedTab = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.surfaceContainerHigh : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: isSelected ? AppColors.onSurface : AppColors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  // STATS TAB
  Widget _buildStatsTab() {
    if (_statsLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        _buildWeeklyVolumeCard(),
        const SizedBox(height: 16),
        _buildConsistencyCard(),
        const SizedBox(height: 16),
        _buildMuscleBreakdownCard(),
        const SizedBox(height: 24),
        _buildResetPlanButton(),
      ],
    );
  }

  // Weekly Volume
  Widget _buildWeeklyVolumeCard() {
    final totalVolume = _weeklyVolume.values.fold(0.0, (a, b) => a + b);
    final maxVolume = _weeklyVolume.values.isEmpty
        ? 1.0
        : _weeklyVolume.values.reduce((a, b) => a > b ? a : b);
    final dayLabels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
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
                    Text(
                      'Weekly Volume',
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Total load displacement in kg',
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    totalVolume.toStringAsFixed(0),
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  Text(
                    'KG THIS WEEK',
                    style: GoogleFonts.manrope(
                      fontSize: 9,
                      letterSpacing: 1.5,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Bar chart
          SizedBox(
            height: 100,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final weekday = i + 1;
                final volume = _weeklyVolume[weekday] ?? 0.0;
                final ratio = maxVolume > 0 ? volume / maxVolume : 0.0;
                final isToday = DateTime.now().weekday == weekday;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Bar
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOut,
                          height: ratio > 0 ? (80 * ratio).clamp(4.0, 80.0) : 4,
                          decoration: BoxDecoration(
                            color: isToday
                                ? AppColors.primary
                                : volume > 0
                                    ? AppColors.primary.withOpacity(0.4)
                                    : AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          dayLabels[i],
                          style: GoogleFonts.manrope(
                            fontSize: 9,
                            fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                            color: isToday
                                ? AppColors.primary
                                : AppColors.onSurfaceVariant,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // Consistency
  Widget _buildConsistencyCard() {
    final rate = _plannedThisWeek > 0
        ? (_workoutsThisWeek / _plannedThisWeek).clamp(0.0, 1.0)
        : 0.0;
    final pct = (rate * 100).round();

    String message;
    if (pct >= 90) message = 'Elite level precision.';
    else if (pct >= 70) message = 'Solid consistency. Keep pushing.';
    else if (pct >= 50) message = 'Good start. Build the habit.';
    else if (_plannedThisWeek == 0) message = 'No plan active this week.';
    else message = 'Let\'s get moving. You\'ve got this.';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Text(
            'Consistency',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 24),
          // Ring
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    value: rate,
                    strokeWidth: 10,
                    backgroundColor: AppColors.surfaceContainerHigh,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$pct%',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      'GOAL HIT',
                      style: GoogleFonts.manrope(
                        fontSize: 9,
                        letterSpacing: 2,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "You've completed $_workoutsThisWeek of your $_plannedThisWeek scheduled sessions. $message",
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: AppColors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // Muscle Breakdown
  Widget _buildMuscleBreakdownCard() {
    if (_muscleFrequency.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          'Complete workouts to see muscle breakdown.',
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      );
    }

    final sorted = _muscleFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxFreq = sorted.first.value;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Muscle Focus This Week',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 20),
          ...sorted.take(5).map((entry) {
            final ratio = entry.value / maxFreq;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        entry.key.toUpperCase(),
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                          color: AppColors.onSurface,
                        ),
                      ),
                      Text(
                        '${entry.value}x',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      backgroundColor: AppColors.surfaceContainerHigh,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // Reset Plan
  Widget _buildResetPlanButton() {
    return Column(
      children: [
        Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.error, size: 18),
            const SizedBox(width: 8),
            Text(
              'Protocol Reset',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'This will erase your current AI-adapted plan. Only use this if your training goals have fundamentally shifted.',
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: AppColors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _showResetConfirmation,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error.withOpacity(0.15),
              foregroundColor: AppColors.error,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(
              'RESET WORKOUT PLAN',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showResetConfirmation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reset Workout Plan?',
            style: GoogleFonts.spaceGrotesk(
                color: AppColors.onSurface, fontWeight: FontWeight.w600)),
        content: Text(
            'Your current plan and all adaptations will be removed. A new plan will be generated.',
            style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: GoogleFonts.manrope(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Reset',
                style: GoogleFonts.manrope(
                    color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;
    await _resetPlan();
  }

  Future<void> _resetPlan() async {
    if (_uid == null) return;
    try {
      // Mark all active plans as inactive
      final plansSnap = await _db
          .collection('users')
          .doc(_uid)
          .collection('workoutPlans')
          .get();

      for (final doc in plansSnap.docs) {
        if (doc.data()['status'] == 'active') {
          await doc.reference.update({'status': 'inactive'});
        }
      }

      if (!mounted) return;
      // Navigate to plan generation screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlanGenerationScreen(
            data: OnboardingData(),
          ),
        ),
      );
    } catch (e) {
      print('Reset plan error: $e');
    }
  }

  // RECOVERY TAB
  Widget _buildRecoveryTab() {
    if (_recoveryLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      children: [
        _buildHeatmapCard(),
        const SizedBox(height: 16),
        _buildRecoveryStatusCard(),
        const SizedBox(height: 16),
        _buildInjuryActionButtons(),
        const SizedBox(height: 16),
        _buildCoachInsightCard(),
      ],
    );
  }

  // Heatmap
  Widget _buildHeatmapCard() {
    // Build heatmap data from injuries
    // WHY intensity values? active=1.0 (full red), recovering=0.5, recovered=0.1
    final Map<Muscle, MuscleData> heatmapData = {};

    for (final injury in _injuries) {
      final status = injury['status'] as String? ?? 'active';
      final region = injury['region'] as String? ?? '';
      final muscle = _regionToMuscle(region);
      if (muscle == null) continue;

      double intensity;
      Color? color;
      switch (status) {
        case 'active':
          intensity = 1.0;
          color = AppColors.error;
          break;
        case 'recovering':
          intensity = 0.6;
          color = const Color(0xFFE8A87C); // amber
          break;
        case 'recovered':
          intensity = 0.2;
          color = AppColors.primary.withOpacity(0.6);
          break;
        default:
          intensity = 1.0;
          color = AppColors.error;
      }

      heatmapData[muscle] = MuscleData(intensity: intensity, color: color);
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          // Front/Back toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Muscle Analysis',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      _buildSideBtn('FRONT', BodySide.front),
                      _buildSideBtn('BACK', BodySide.back),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Heatmap
          SizedBox(
            height: 300,
            child: heatmapData.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_outline_rounded,
                            color: AppColors.primary, size: 40),
                        const SizedBox(height: 12),
                        Text(
                          'No active injuries',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : BodyHeatmap(
                    side: _heatmapSide,
                    gender: _bodyGender,
                    data: heatmapData,
                    colors: [AppColors.primary, Colors.orange, AppColors.error],
                    bodyColor: const Color(0xFF2A2D32),
                    borderColor: AppColors.outlineVariant,
                    showBorder: true,
                  ),
          ),
          // Legend
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendDot(AppColors.error, 'Active'),
                const SizedBox(width: 16),
                _buildLegendDot(const Color(0xFFE8A87C), 'Recovering'),
                const SizedBox(width: 16),
                _buildLegendDot(AppColors.primary, 'Recovered'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideBtn(String label, BodySide side) {
    final isSelected = _heatmapSide == side;
    return GestureDetector(
      onTap: () => setState(() => _heatmapSide = side),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: isSelected ? AppColors.onPrimary : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.manrope(
                fontSize: 11, color: AppColors.onSurfaceVariant)),
      ],
    );
  }

  // Recovery Status List
  Widget _buildRecoveryStatusCard() {
    if (_injuries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          'No injuries logged. Log an injury if you experience pain during training.',
          style: GoogleFonts.manrope(
              fontSize: 13, color: AppColors.onSurfaceVariant),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recovery Status',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          ..._injuries.map((injury) => _buildInjuryRow(injury)),
        ],
      ),
    );
  }

  Widget _buildInjuryRow(Map<String, dynamic> injury) {
    final label = injury['label'] as String? ?? 'Unknown';
    final status = injury['status'] as String? ?? 'active';

    Color statusColor;
    String statusText;
    double progressValue;

    switch (status) {
      case 'active':
        statusColor = AppColors.error;
        statusText = 'Active';
        progressValue = 0.2;
        break;
      case 'recovering':
        statusColor = const Color(0xFFE8A87C);
        statusText = 'Recovering';
        progressValue = 0.6;
        break;
      case 'recovered':
        statusColor = AppColors.primary;
        statusText = 'Ready';
        progressValue = 1.0;
        break;
      default:
        statusColor = AppColors.error;
        statusText = 'Active';
        progressValue = 0.2;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface)),
              Text(
                statusText,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressValue,
              backgroundColor: AppColors.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }

  // Action Buttons
  Widget _buildInjuryActionButtons() {
    return Row(
      children: [
        Expanded(
          child: _buildActionBtn(
            icon: Icons.add_circle_outline_rounded,
            label: 'LOG NEW\nINJURY',
            onTap: _showLogInjurySheet,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionBtn(
            icon: Icons.check_circle_outline_rounded,
            label: 'MARK\nRECOVERED',
            onTap: _showMarkRecoveredSheet,
          ),
        ),
      ],
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: AppColors.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Coach Insight
  Widget _buildCoachInsightCard() {
    final activeInjuries =
        _injuries.where((i) => i['status'] == 'active').toList();
    final recoveringInjuries =
        _injuries.where((i) => i['status'] == 'recovering').toList();

    String insight;
    if (activeInjuries.isNotEmpty) {
      final labels = activeInjuries.map((i) => i['label']).join(', ');
      insight =
          'Active injury detected: $labels. Your next workout plan will avoid exercises that stress this area. Rest and ice if needed.';
    } else if (recoveringInjuries.isNotEmpty) {
      final labels = recoveringInjuries.map((i) => i['label']).join(', ');
      insight =
          'You are recovering from: $labels. Light mobility and rehab exercises will be prioritised in your plan.';
    } else {
      insight =
          'No active injuries. Your plan is running at full intensity. Keep monitoring how your body feels after each session.';
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
          Text(
            'COACH INSIGHT',
            style: GoogleFonts.manrope(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            insight,
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: AppColors.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // INJURY ACTIONS
  Future<void> _showLogInjurySheet() async {
    // All body regions from BodyRegion enum mapped to display names
    final regions = {
      'leftShoulder': 'Left Shoulder',
      'rightShoulder': 'Right Shoulder',
      'chest': 'Chest',
      'upperBack': 'Upper Back',
      'lowerBack': 'Lower Back',
      'leftArm': 'Left Arm',
      'rightArm': 'Right Arm',
      'core': 'Core / Abs',
      'leftHip': 'Left Hip',
      'rightHip': 'Right Hip',
      'leftKnee': 'Left Knee',
      'rightKnee': 'Right Knee',
      'leftAnkle': 'Left Ankle',
      'rightAnkle': 'Right Ankle',
      'neck': 'Neck',
    };

    String? selectedRegion;
    final labelController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('LOG NEW INJURY',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface)),
              const SizedBox(height: 20),
              Text('Body Region',
                  style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 10),
              // Region chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: regions.entries.map((entry) {
                  final isSelected = selectedRegion == entry.key;
                  return GestureDetector(
                    onTap: () =>
                        setSheetState(() => selectedRegion = entry.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withOpacity(0.2)
                            : AppColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(entry.value,
                          style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.onSurface)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Text('Description (optional)',
                  style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: AppColors.onSurfaceVariant)),
              const SizedBox(height: 8),
              TextField(
                controller: labelController,
                style: GoogleFonts.manrope(
                    fontSize: 14, color: AppColors.onSurface),
                decoration: InputDecoration(
                  hintText: "e.g. Runner's knee, shoulder strain",
                  hintStyle: GoogleFonts.manrope(
                      color: AppColors.onSurfaceVariant),
                  border: InputBorder.none,
                  fillColor: AppColors.surfaceContainerHigh,
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: selectedRegion == null
                    ? null
                    : () async {
                        final label = labelController.text.trim().isEmpty
                            ? regions[selectedRegion!]!
                            : labelController.text.trim();
                        await _saveInjury(selectedRegion!, label);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                child: Text('SAVE INJURY',
                    style: GoogleFonts.spaceGrotesk(
                        fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveInjury(String region, String label) async {
    if (_uid == null) return;
    await _db.collection('users').doc(_uid).collection('injuries').add({
      'region': region,
      'label': label,
      'isCustom': true,
      'status': 'active',
      'loggedAt': FieldValue.serverTimestamp(),
      'recoveredAt': null,
    });
    await _loadRecovery(); // refresh
  }

  Future<void> _showMarkRecoveredSheet() async {
    final activeInjuries = _injuries
        .where((i) => i['status'] != 'recovered')
        .toList();

    if (activeInjuries.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No active injuries to update.',
              style: GoogleFonts.manrope()),
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('UPDATE RECOVERY',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface)),
            const SizedBox(height: 20),
            ...activeInjuries.map((injury) {
              final label = injury['label'] as String? ?? 'Unknown';
              final status = injury['status'] as String? ?? 'active';
              final id = injury['id'] as String;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(label,
                            style: GoogleFonts.manrope(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurface)),
                      ),
                      // Toggle between active → recovering → recovered
                      GestureDetector(
                        onTap: () async {
                          final nextStatus = status == 'active'
                              ? 'recovering'
                              : 'recovered';
                          await _updateInjuryStatus(id, nextStatus);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            status == 'active' ? 'RECOVERING' : 'RECOVERED',
                            style: GoogleFonts.manrope(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _updateInjuryStatus(String injuryId, String newStatus) async {
    if (_uid == null) return;
    await _db
        .collection('users')
        .doc(_uid)
        .collection('injuries')
        .doc(injuryId)
        .update({
      'status': newStatus,
      if (newStatus == 'recovered')
        'recoveredAt': FieldValue.serverTimestamp(),
    });
    await _loadRecovery(); // refresh UI
  }

  // HELPERS
  Muscle? _regionToMuscle(String region) {
    switch (region) {
      case 'chest': return Muscle.chest;
      case 'upperBack': return Muscle.upperBack;
      case 'lowerBack': return Muscle.lowerBack;
      case 'leftShoulder':
      case 'rightShoulder': return Muscle.deltoids;
      case 'leftArm':
      case 'rightArm': return Muscle.biceps;
      case 'core': return Muscle.abs;
      case 'leftHip':
      case 'rightHip': return Muscle.gluteal;
      case 'leftKnee':
      case 'rightKnee': return Muscle.knees;
      case 'leftAnkle':
      case 'rightAnkle': return Muscle.ankles;
      case 'neck': return Muscle.neck;
      default: return null;
    }
  }
}