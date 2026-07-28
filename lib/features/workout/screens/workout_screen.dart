import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/theme/app_colors.dart';
import '../services/workout_plan_service.dart';
import 'workout_day_detail_screen.dart';
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

  // Edit mode: when on, tapping a workout day opens the Replace/Cancel
  // management sheet instead of the normal "view exercises" sheet.
  bool _isEditMode = false;
  bool _isMutating = false; // true while a swap/cancel write is in flight

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
                      _segmentIndex == 0 ? 'Your 7-Day Plan' : 'Master Your Mechanics',
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
                GestureDetector(
                  onTap: () => setState(() => _isEditMode = !_isEditMode),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                          _isEditMode ? Icons.check_rounded : Icons.edit_calendar_rounded,
                          size: 16,
                          color: _isEditMode ? AppColors.onPrimary : AppColors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isEditMode ? 'DONE' : 'EDIT',
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: _isEditMode ? AppColors.onPrimary : AppColors.onSurfaceVariant,
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
                  const Icon(Icons.info_outline_rounded, size: 14, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap a workout day to replace or cancel it.',
                      style: GoogleFonts.manrope(fontSize: 12, color: AppColors.primary),
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

    // In edit mode, workout days open the manage sheet (replace/cancel)
    // instead of the normal view-exercises sheet. Rest days aren't
    // editable yet — only workout days can be replaced or cancelled.
    final VoidCallback? onTap = isRest
        ? null
        : (_isEditMode
            ? () => _showManageDaySheet(day)
            : () => _openDayDetail(day));

    return GestureDetector(
      onTap: onTap,
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
                  : (_isEditMode ? AppColors.primary : AppColors.primary.withValues(alpha: 0.6)),
              width: _isEditMode && !isRest ? 4 : 3,
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
                if (_isEditMode && !isRest)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.edit_rounded, size: 14, color: AppColors.primary),
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
                _isEditMode ? 'TAP TO REPLACE OR CANCEL →' : 'TAP TO VIEW EXERCISES →',
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
            Text(dayName.toUpperCase(),
                style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                    color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(workoutName,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
            const SizedBox(height: 24),

            _manageOptionTile(
              icon: Icons.swap_horiz_rounded,
              title: 'Replace Day',
              subtitle: 'Swap with another day in this plan',
              onTap: () {
                Navigator.pop(sheetContext);
                _showReplaceDayPicker(day);
              },
            ),
            const SizedBox(height: 10),
            _manageOptionTile(
              icon: Icons.remove_circle_outline_rounded,
              title: 'Cancel Day',
              subtitle: 'Mark this day as rest instead',
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
    return GestureDetector(
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
                  Text(title,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: GoogleFonts.manrope(fontSize: 12, color: AppColors.onSurfaceVariant)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  void _showReplaceDayPicker(Map<String, dynamic> day) {
    final days = (_plan!['days'] as List).cast<Map<String, dynamic>>();
    final replacementDays = days
        .where((d) => d['id'] != day['id'])
        .toList();

    if (replacementDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No other days to swap with.', style: GoogleFonts.manrope()),
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
                      color: AppColors.onSurfaceVariant),
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
                      (other['exercises'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                  final isRestDay = other['dayType'] == 'rest';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _confirmSwap(day, other);
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
                                        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isRestDay
                                        ? 'REST DAY'
                                        : '${otherExercises.length} EXERCISES',
                                    style: GoogleFonts.manrope(
                                        fontSize: 10, letterSpacing: 1, color: AppColors.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.swap_horiz_rounded, color: AppColors.primary),
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

  Future<void> _confirmSwap(Map<String, dynamic> dayA, Map<String, dynamic> dayB) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Swap Days?',
            style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface, fontWeight: FontWeight.w600)),
        content: Text(
          '${dayA['dayName']} will become "${dayB['workoutName']}", and ${dayB['dayName']} will become "${dayA['workoutName']}".',
          style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Swap',
                style: GoogleFonts.manrope(color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await _runMutation(() => WorkoutPlanService().swapDays(
          uid: FirebaseAuth.instance.currentUser!.uid,
          planId: _plan!['id'] as String,
          dayIdA: dayA['id'] as String,
          dayIdB: dayB['id'] as String,
        ));
  }

  Future<void> _confirmCancelDay(Map<String, dynamic> day) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Cancel This Workout?',
            style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface, fontWeight: FontWeight.w600)),
        content: Text(
          '${day['dayName']} will be marked as a rest day. Its exercises will be removed from the schedule.',
          style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Keep It', style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Cancel Day',
                style: GoogleFonts.manrope(color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await _runMutation(() => WorkoutPlanService().cancelDay(
          uid: FirebaseAuth.instance.currentUser!.uid,
          planId: _plan!['id'] as String,
          dayId: day['id'] as String,
        ));
  }

  /// Runs a swap/cancel write, showing a lightweight loading state and
  /// reloading the plan from Firestore afterward so the UI reflects the
  /// authoritative saved state rather than a locally-guessed one.
  Future<void> _runMutation(Future<void> Function() action) async {
    if (_isMutating) return;
    setState(() => _isMutating = true);
    try {
      await action();
      await _loadPlan();
    } catch (e) {
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

  /// Opens the full-screen, editable day view (WorkoutDayDetailScreen)
  /// instead of the old bottom sheet — lets the user reorder, add/remove
  /// exercises, and view exercise details, then start the workout
  /// directly from there if it's today.
  Future<void> _openDayDetail(Map<String, dynamic> day) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkoutDayDetailScreen(
          day: day,
          planId: _plan!['id'] as String,
        ),
      ),
    );
    // Always refresh on return — cheap, and correctly reflects any
    // add/remove/reorder edits made on the detail screen without needing
    // to track exactly what changed.
    _loadPlan();
  }
}
