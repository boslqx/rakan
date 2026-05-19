import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/main_shell.dart';
import '../models/onboarding_data.dart';
import '../models/workout_plan.dart';

class WorkoutSummaryScreen extends StatelessWidget {
  final OnboardingData data;

  const WorkoutSummaryScreen({super.key, required this.data});

  // Helper: goal display string
  String _goalLabel(FitnessGoal? goal) {
    switch (goal) {
      case FitnessGoal.muscleGain:
        return 'Muscle Gain';
      case FitnessGoal.weightLoss:
        return 'Weight Loss';
      case FitnessGoal.endurance:
        return 'Endurance';
      case FitnessGoal.flexibility:
        return 'Flexibility';
      default:
        return 'General Fitness';
    }
  }

  // Helper: experience display string
  String _experienceLabel(ExperienceLevel? level) {
    switch (level) {
      case ExperienceLevel.beginner:
        return 'Beginner';
      case ExperienceLevel.intermediate:
        return 'Intermediate';
      case ExperienceLevel.advanced:
        return 'Advanced';
      default:
        return 'All Levels';
    }
  }

  // Helper: equipment summary
  String _equipmentLabel(Set<EquipmentType> equipment) {
    if (equipment.contains(EquipmentType.fullGym)) return 'Full Gym';
    if (equipment.contains(EquipmentType.noEquipment)) return 'Bodyweight';
    if (equipment.length == 1) {
      switch (equipment.first) {
        case EquipmentType.dumbbell:
          return 'Dumbbells';
        case EquipmentType.barbell:
          return 'Barbells';
        case EquipmentType.kettlebell:
          return 'Kettlebells';
        default:
          return 'Home Equipment';
      }
    }
    return 'Mixed Equipment';
  }

  @override
  Widget build(BuildContext context) {
    // Generate the fake plan from onboarding data
    final plan = generateFakePlan(
      userName: data.name ?? 'Athlete',
      goal: _goalLabel(data.fitnessGoal),
      experience: _experienceLabel(data.experienceLevel),
      workoutDays: data.workoutDays,
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Plan headline
                    Text(
                      plan.planName,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      plan.planDescription,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        color: AppColors.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Plan summary chips
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _SummaryChip(
                          icon: Icons.flag_rounded,
                          label: _goalLabel(data.fitnessGoal),
                        ),
                        _SummaryChip(
                          icon: Icons.bar_chart_rounded,
                          label: _experienceLabel(data.experienceLevel),
                        ),
                        _SummaryChip(
                          icon: Icons.fitness_center_rounded,
                          label: _equipmentLabel(data.equipment),
                        ),
                        _SummaryChip(
                          icon: Icons.calendar_today_rounded,
                          label:
                              '${data.workoutDays.length} days/week',
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // Day cards
                    ...plan.days.map(
                      (day) => _DayCard(day: day),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Confirm button — always visible at bottom
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  top: BorderSide(
                    color: AppColors.outlineVariant,
                    width: 1,
                  ),
                ),
              ),
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => const MainShell(),
                    ),
                    (_) => false,
                  );
                },
                child: Text(
                  'CONFIRM PLAN →',
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Summary Chip
class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SummaryChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(48),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// Day Card
class _DayCard extends StatelessWidget {
  final WorkoutDay day;

  const _DayCard({required this.day});

  @override
  Widget build(BuildContext context) {
    final isRest = day.type == DayType.rest;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isRest
            ? AppColors.surfaceContainerLow.withOpacity(0.5)
            : AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isRest
              ? AppColors.outlineVariant.withOpacity(0.5)
              : AppColors.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: day label + badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${day.dayName}  ·  DAY ${day.dayNumber.toString().padLeft(2, '0')}',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              // Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: isRest
                      ? AppColors.surfaceContainerHigh
                      : AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(48),
                  border: Border.all(
                    color: isRest
                        ? AppColors.outlineVariant
                        : AppColors.primary.withOpacity(0.4),
                  ),
                ),
                child: Text(
                  isRest ? 'REST DAY' : 'WORKOUT DAY',
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: isRest
                        ? AppColors.onSurfaceVariant
                        : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Workout name
          Text(
            day.workoutName ?? '',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: isRest
                  ? AppColors.onSurfaceVariant
                  : AppColors.onSurface,
              height: 1.1,
            ),
          ),

          // Focus description
          if (day.focusDescription != null) ...[
            const SizedBox(height: 4),
            Text(
              day.focusDescription!,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],

          // Workout day details
          if (!isRest) ...[
            const SizedBox(height: 12),

            // Duration + muscle chips row
            Row(
              children: [
                // Duration
                if (day.durationMinutes != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(48),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_rounded,
                          size: 12,
                          color: AppColors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${day.durationMinutes} MIN',
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(width: 8),

                // Muscle group chips
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: day.muscleGroups
                          .map(
                            (muscle) => Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary
                                    .withOpacity(0.08),
                                borderRadius:
                                    BorderRadius.circular(48),
                                border: Border.all(
                                  color: AppColors.primary
                                      .withOpacity(0.2),
                                ),
                              ),
                              child: Text(
                                muscle,
                                style: GoogleFonts.manrope(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Exercise list
            // Show first 3 exercises + "+X more" chip
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...day.exercises.take(3).map(
                      (ex) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          ex.name,
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            color: AppColors.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                if (day.exercises.length > 3)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '+${day.exercises.length - 3} MORE',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        color: AppColors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}