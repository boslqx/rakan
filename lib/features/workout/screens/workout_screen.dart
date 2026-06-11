import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/theme/app_colors.dart';
import '../services/workout_plan_service.dart';
import 'workout_preview_screen.dart';
import 'exercise_library_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadPlan();
  }

  Future<void> _loadPlan() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final plan = await WorkoutPlanService().getActivePlan(uid);
      if (mounted) {
        setState(() {
          _plan = plan;
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
            _segmentIndex == 0 ? 'Your 7-Day Plan' : 'Master Your Mechanics',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
              height: 1.1,
            ),
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
        ],
      ),
    );
  }

  Widget _buildSegmentPill(String label, int index) {
    final isSelected = _segmentIndex == index;
    return GestureDetector(
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
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 48),
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
              child: Text('Retry',
                  style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w600)),
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
            const Icon(Icons.fitness_center_rounded,
                color: AppColors.onSurfaceVariant, size: 48),
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
    final planName = _plan!['planName'] as String? ?? '7-Day Plan';

    return RefreshIndicator(
      onRefresh: _loadPlan,
      color: AppColors.primary,
      backgroundColor: AppColors.surfaceContainerLow,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CURRENT CYCLE',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    planName,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildQuickStat(
                        '${days.where((d) => d['dayType'] == 'workout').length}',
                        'WORKOUT DAYS',
                      ),
                      const SizedBox(width: 24),
                      _buildQuickStat(
                        '${days.where((d) => d['dayType'] == 'rest').length}',
                        'REST DAYS',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final day = days[index];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: _buildDayCard(day),
                );
              },
              childCount: days.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildQuickStat(String value, String label) {
    return Row(
      children: [
        Text(value,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.primary)),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                color: AppColors.onSurfaceVariant)),
      ],
    );
  }

  Widget _buildDayCard(Map<String, dynamic> day) {
    final isRest = day['dayType'] == 'rest';
    final dayNumber = day['dayNumber'] as int;
    final dayName = day['dayName'] as String;
    final workoutName = day['workoutName'] as String;
    final focusDescription = day['focusDescription'] as String? ?? '';
    final durationMinutes = day['durationMinutes'] as int? ?? 0;
    final exercises =
        (day['exercises'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return GestureDetector(
      onTap: isRest ? null : () => _showExerciseSheet(day),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isRest
              ? AppColors.surfaceContainerLowest
              : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border(
            left: BorderSide(
              color: isRest
                  ? Colors.transparent
                  : AppColors.primary.withValues(alpha: 0.6),
              width: 3,
            ),
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
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: isRest
                          ? AppColors.onSurfaceVariant.withValues(alpha: 0.5)
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isRest
                        ? AppColors.surfaceContainerLow
                        : AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(48),
                  ),
                  child: Text(
                    isRest ? 'REST DAY' : 'WORKOUT',
                    style: GoogleFonts.manrope(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                      color: isRest
                          ? AppColors.onSurfaceVariant.withValues(alpha: 0.5)
                          : AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              workoutName.toUpperCase(),
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: isRest
                    ? AppColors.onSurfaceVariant.withValues(alpha: 0.4)
                    : AppColors.onSurface,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              focusDescription,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: isRest
                    ? AppColors.onSurfaceVariant.withValues(alpha: 0.3)
                    : AppColors.onSurfaceVariant,
              ),
            ),
            if (!isRest) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.timer_outlined,
                      size: 14, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    '$durationMinutes MIN',
                    style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                        color: AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.fitness_center_rounded,
                      size: 14, color: AppColors.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    '${exercises.length} EXERCISES',
                    style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                        color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
              if (exercises.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ...exercises.take(3).map((ex) => _buildExerciseChip(
                        ex['exerciseName'] as String? ?? '')),
                    if (exercises.length > 3)
                      _buildExerciseChip('+${exercises.length - 3} MORE',
                          isMore: true),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'TAP TO VIEW EXERCISES →',
                style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    color: AppColors.primary.withValues(alpha: 0.6)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseChip(String label, {bool isMore = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(48),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: AppColors.onSurfaceVariant),
      ),
    );
  }

  void _showExerciseSheet(Map<String, dynamic> day) {
    final exercises =
        (day['exercises'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final workoutName = day['workoutName'] as String;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        minChildSize: 0.4,
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
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      workoutName.toUpperCase(),
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface),
                    ),
                  ),
                  Text(
                    '${exercises.length} EXERCISES',
                    style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                        color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                itemCount: exercises.length,
                itemBuilder: (_, index) {
                  final ex = exercises[index];
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
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ex['exerciseName'] as String? ?? '',
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.onSurface),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  (ex['muscleGroup'] as String? ?? '').toUpperCase(),
                                  style: GoogleFonts.manrope(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.5,
                                      color: AppColors.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${ex['sets']} × ${ex['reps']}',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.onSurface),
                              ),
                              Text(
                                '${ex['restSeconds']}s REST',
                                style: GoogleFonts.manrope(
                                    fontSize: 10,
                                    color: AppColors.onSurfaceVariant,
                                    letterSpacing: 1),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => WorkoutPreviewScreen(day: day),
                    ),
                  );
                },
                child: Text(
                  'START THIS WORKOUT →',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}