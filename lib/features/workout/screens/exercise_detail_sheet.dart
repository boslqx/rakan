import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/theme/app_colors.dart';
import '../data/exercise_data.dart';
import '../services/workout_plan_service.dart';
import '../widgets/exercise_media.dart';
import 'pose_detection_screen.dart';
import '../../../shared/widgets/pressable.dart';

/// Exercise library detail. Pops with `true` if the exercise was added to
/// a plan day, so the library can refresh its IN PLAN badges.
class ExerciseDetailSheet extends StatefulWidget {
  final ExerciseData exercise;

  /// The active plan, when the caller already has it — shows which days
  /// the exercise is on and saves a reload when adding. Fetched on demand
  /// otherwise.
  final Map<String, dynamic>? plan;

  const ExerciseDetailSheet({super.key, required this.exercise, this.plan});

  @override
  State<ExerciseDetailSheet> createState() => _ExerciseDetailSheetState();
}

class _ExerciseDetailSheetState extends State<ExerciseDetailSheet> {
  WebViewController? _webController;
  bool _videoLoaded = false;

  /// The exercise on show — starts as the one opened, changes when a
  /// "similar exercise" is tapped.
  late ExerciseData _exercise = widget.exercise;
  ScrollController? _scrollController;

  @override
  void initState() {
    super.initState();
    _initWebViewIfNeeded();
  }

  // Only spin up the WebView if we'll actually need it (no GIF, but a real YouTube ID)
  void _initWebViewIfNeeded() {
    if (_exercise.localGifAsset == null && _exercise.youtubeId.isNotEmpty) {
      _videoLoaded = false;
      _initWebView();
    }
  }

  void _showExercise(ExerciseData exercise) {
    setState(() {
      _exercise = exercise;
      _initWebViewIfNeeded();
    });
    _scrollController?.animateTo(0,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  /// Plan days (by short name) this exercise is already on.
  List<String> get _planDayNames {
    final days = (widget.plan?['days'] as List? ?? const []).cast<Map<String, dynamic>>();
    return [
      for (final day in days)
        if (day['dayType'] == 'workout' &&
            (day['exercises'] as List? ?? const [])
                .any((e) => (e as Map)['exerciseName'] == _exercise.name))
          (day['dayName'] as String? ?? '').length >= 3
              ? (day['dayName'] as String).substring(0, 3).toUpperCase()
              : (day['dayName'] as String? ?? '').toUpperCase(),
    ];
  }

  void _initWebView() {
    // Use embedded YouTube player with minimal UI for better mobile experience
    final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { background: #0c0e10; }
    .wrapper {
      position: relative;
      width: 100%;
      padding-bottom: 56.25%;
      height: 0;
      overflow: hidden;
    }
    iframe {
      position: absolute;
      top: 0; left: 0;
      width: 100%; height: 100%;
      border: none;
    }
  </style>
</head>
<body>
  <div class="wrapper">
    <iframe
      src="https://www.youtube.com/embed/${_exercise.youtubeId}?rel=0&modestbranding=1&playsinline=1"
      allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
      allowfullscreen>
    </iframe>
  </div>
</body>
</html>
''';

    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.surface)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _videoLoaded = true);
        },
      ))
      ..loadHtmlString(html);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      maxChildSize: 0.97,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scrollController) {
        _scrollController = scrollController;
        return Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Drag handle
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 4),

            // Scrollable content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: [
                  // Video player
                  _buildVideoPlayer(),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Difficulty + category badges
                        Row(
                          children: [
                            _buildBadge(_exercise.difficulty),
                            const SizedBox(width: 8),
                            _buildBadge(_exercise.muscleGroup),
                            if (_exercise.hasPoseDetection) ...[
                              const SizedBox(width: 8),
                              _buildBadge('AI Form Check',
                                  highlight: true),
                            ],
                          ],
                        ),

                        const SizedBox(height: 14),

                        // Exercise name
                        Text(
                          _exercise.name,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface,
                            height: 1.1,
                          ),
                        ),

                        const SizedBox(height: 6),

                        // Equipment
                        Row(
                          children: [
                            const Icon(Icons.fitness_center_rounded,
                                size: 13,
                                color: AppColors.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(
                              _exercise.equipment,
                              style: GoogleFonts.manrope(
                                fontSize: 13,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        if (_planDayNames.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.event_available_rounded,
                                  size: 14, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Text(
                                'IN YOUR PLAN · ${_planDayNames.join(' · ')}',
                                style: GoogleFonts.manrope(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 20),

                        // Target anatomy
                        _buildSectionTitle('TARGET ANATOMY'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            // Primary muscle is always first
                            _buildMuscleChip(
                                _exercise.muscleGroup,
                                isPrimary: true),
                            ..._exercise.secondaryMuscles
                                .map((m) => _buildMuscleChip(m)),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Sets / reps guide
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.repeat_rounded,
                                  size: 18, color: AppColors.primary),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'RECOMMENDED VOLUME',
                                    style: GoogleFonts.manrope(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.5,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _exercise.setsRepsGuide,
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Step-by-step instructions
                        _buildSectionTitle('STEP-BY-STEP'),
                        const SizedBox(height: 12),
                        ..._exercise.steps.asMap().entries.map(
                              (entry) => _buildStep(
                                  entry.key + 1, entry.value),
                            ),

                        const SizedBox(height: 24),

                        // Tips
                        _buildTipsCard(),

                        _buildSimilarExercises(),

                        // Exercise actions
                        const SizedBox(height: 24),
                        if (_exercise.hasPoseDetection) ...[
                          _buildFormCheckButton(context),
                          const SizedBox(height: 12),
                        ],
                        _buildAddToWorkoutButton(context),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      },
    );
  }

  /// Other exercises for the same muscle group — tap one to switch this
  /// sheet to it, for comparing options without backing out.
  Widget _buildSimilarExercises() {
    final similar = kExercises
        .where((e) => e.muscleGroup == _exercise.muscleGroup && e.name != _exercise.name)
        .take(12)
        .toList();
    if (similar.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('SIMILAR EXERCISES'),
          const SizedBox(height: 12),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: similar.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final ex = similar[i];
                return Pressable(
                  onTap: () => _showExercise(ex),
                  child: SizedBox(
                    width: 76,
                    child: Column(
                      children: [
                        ExerciseThumb(asset: ex.thumbnailAsset, size: 72),
                        const SizedBox(height: 6),
                        Text(
                          ex.name,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Video player with loading state
  Widget _buildVideoPlayer() {
    // Case 1: GIF available — show it directly, no WebView involved
    if (_exercise.localGifAsset != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Image.asset(
              _exercise.localGifAsset!,
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
    }

    // Case 2: no GIF, but a real YouTube ID — existing WebView behaviour
    if (_exercise.youtubeId.isNotEmpty) {
      return SizedBox(
        height: MediaQuery.of(context).size.width * 9 / 16,
        child: Stack(
          children: [
            WebViewWidget(controller: _webController!),
            if (!_videoLoaded)
              Container(
                color: AppColors.surfaceContainerHigh,
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.primary,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Case 3: neither — empty state instead of a blank/broken player
    return SizedBox(
      height: MediaQuery.of(context).size.width * 9 / 16,
      child: Container(
        color: AppColors.surfaceContainerHigh,
        child: const Center(
          child: Icon(Icons.videocam_off_rounded,
              size: 32, color: AppColors.onSurfaceVariant),
        ),
      ),
    );
  }

  // Helpers 
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }

  Widget _buildBadge(String label, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.primary.withValues(alpha: 0.15)
            : AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(48),
        border: highlight
            ? Border.all(
                color: AppColors.primary.withValues(alpha: 0.4))
            : null,
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.manrope(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: highlight ? AppColors.primary : AppColors.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildMuscleChip(String label, {bool isPrimary = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isPrimary
            ? AppColors.primary.withValues(alpha: 0.12)
            : AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(48),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isPrimary
              ? AppColors.primary
              : AppColors.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildStep(int number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step number circle
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                text,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: AppColors.onSurface,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tips_and_updates_rounded,
                  size: 15, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'FORM TIPS',
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._exercise.tips.map(
            (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(top: 7, right: 10),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      tip,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: AppColors.onSurface,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCheckButton(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () {
        Navigator.pop(context); // Close the sheet
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PoseDetectionScreen(
              exerciseName: _exercise.name,
              targetReps: 10,
            ),
          ),
        );
      },
      icon: const Icon(Icons.camera_alt_rounded, size: 18),
      label: Text(
        'TRY WITH FORM CHECK →',
        style: GoogleFonts.spaceGrotesk(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildAddToWorkoutButton(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: () => _showAddToWorkoutDialog(context),
      icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
      label: Text(
        'ADD TO WORKOUT',
        style: GoogleFonts.spaceGrotesk(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryContainer,
        foregroundColor: AppColors.onPrimary,
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(48),
        ),
        elevation: 0,
      ),
    );
  }

  Future<void> _showAddToWorkoutDialog(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final plan = widget.plan ?? await WorkoutPlanService().getActivePlan(uid);
      if (plan == null || !mounted) return;
      final planId = plan['id'] as String;

      final days = (plan['days'] as List).cast<Map<String, dynamic>>();
      final workoutDays = days.where((d) => d['dayType'] == 'workout').toList();

      if (workoutDays.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No workout days in your active plan.',
                  style: GoogleFonts.manrope()),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      if (!mounted) return;

      final selectedDay = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        backgroundColor: AppColors.surfaceContainerLow,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) => _WorkoutDayPickerSheet(
          workoutDays: workoutDays,
          exerciseName: _exercise.name,
        ),
      );

      if (selectedDay != null && mounted) {
        await _confirmAddToWorkout(context, selectedDay, planId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Failed to load workout plan: $e', style: GoogleFonts.manrope()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _confirmAddToWorkout(
      BuildContext context, Map<String, dynamic> day, String planId) async {
    final dayName = day['dayName'] as String? ?? 'this day';
    final workoutName = day['workoutName'] as String? ?? 'Workout';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Add to Workout?',
            style: GoogleFonts.spaceGrotesk(
                color: AppColors.onSurface, fontWeight: FontWeight.w600)),
        content: Text(
          'Add "${_exercise.name}" to $dayName ($workoutName)?',
          style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Add',
                style: GoogleFonts.manrope(
                    color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await _addExerciseToDay(day, planId, dayName);
    }
  }

  Future<void> _addExerciseToDay(
      Map<String, dynamic> day, String planId, String dayName) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final dayId = day['id'] as String? ?? '';

    if (planId.isEmpty || dayId.isEmpty) return;

    // We need to get the current exercises for this day to calculate order and duration
    // The day object from the picker already has exercises
    final exercises = (day['exercises'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final newExercise = {
      'exerciseId': DateTime.now().millisecondsSinceEpoch.toString(),
      'exerciseName': _exercise.name,
      'muscleGroup': _exercise.muscleGroup,
      'sets': 3,
      'reps': 10,
      'restSeconds': 60,
    };

    final finalDuration =
        WorkoutPlanService.estimateDurationMinutes([...exercises, newExercise]);

    try {
      await WorkoutPlanService().addExerciseToDay(
        uid: uid,
        planId: planId,
        dayId: dayId,
        exercise: newExercise,
        order: exercises.length,
        newDurationMinutes: finalDuration,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added "${_exercise.name}" to $dayName',
                style: GoogleFonts.manrope(color: AppColors.onSurface)),
            backgroundColor: AppColors.surfaceContainerHigh,
          ),
        );
        Navigator.pop(context, true); // Close the exercise detail sheet
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add exercise: $e', style: GoogleFonts.manrope()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

/// Bottom sheet to pick a workout day
class _WorkoutDayPickerSheet extends StatelessWidget {
  final List<Map<String, dynamic>> workoutDays;
  final String exerciseName;

  const _WorkoutDayPickerSheet({
    required this.workoutDays,
    required this.exerciseName,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Drag handle
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text(
                'ADD "$exerciseName" TO',
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                itemCount: workoutDays.length,
                itemBuilder: (_, index) {
                  final day = workoutDays[index];
                  final dayNumber = day['dayNumber'] as int;
                  final dayName = day['dayName'] as String;
                  final workoutName = day['workoutName'] as String;
                  final focusDescription = day['focusDescription'] as String? ?? '';
                  final durationMinutes = day['durationMinutes'] as int? ?? 0;
                  final exercises = (day['exercises'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                  final alreadyIn = exercises.any((e) => e['exerciseName'] == exerciseName);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Opacity(
                    opacity: alreadyIn ? 0.5 : 1,
                    child: Pressable(
                      onTap: alreadyIn ? null : () => Navigator.pop(context, day),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text('D$dayNumber',
                                        style: GoogleFonts.spaceGrotesk(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(dayName.toUpperCase(),
                                          style: GoogleFonts.manrope(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 1.5,
                                              color: AppColors.onSurfaceVariant)),
                                      Text(workoutName,
                                          style: GoogleFonts.spaceGrotesk(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.onSurface)),
                                    ],
                                  ),
                                ),
                                if (alreadyIn)
                                  Text('ALREADY ADDED',
                                      style: GoogleFonts.manrope(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.2,
                                          color: AppColors.primary))
                                else
                                  const Icon(Icons.arrow_forward_ios_rounded,
                                      size: 16, color: AppColors.onSurfaceVariant),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(focusDescription,
                                style: GoogleFonts.manrope(
                                    fontSize: 12, color: AppColors.onSurfaceVariant)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.timer_outlined,
                                    size: 13, color: AppColors.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text('$durationMinutes MIN',
                                    style: GoogleFonts.manrope(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.onSurfaceVariant)),
                                const SizedBox(width: 16),
                                const Icon(Icons.fitness_center_rounded,
                                    size: 13, color: AppColors.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text('${exercises.length} EXERCISES',
                                    style: GoogleFonts.manrope(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.onSurfaceVariant)),
                              ],
                            ),
                          ],
                        ),
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
