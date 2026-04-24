import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/onboarding_data.dart';

class Step2Goal extends StatefulWidget {
  final OnboardingData data;
  final VoidCallback onNext;

  const Step2Goal({super.key, required this.data, required this.onNext});

  @override
  State<Step2Goal> createState() => _Step2GoalState();
}

class _Step2GoalState extends State<Step2Goal> {
  void _saveAndContinue() {
    if (!widget.data.isStep2Valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select a goal',
            style: GoogleFonts.manrope(),
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Headline
          Text(
            'PRIMARY\nFOCUS',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select the core objective for your Rakan\ntraining protocol. This shapes your daily metrics.',
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: AppColors.onSurfaceVariant,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 32),

          // Goal cards
          ...FitnessGoal.values.map(
            (goal) => _GoalCard(
              goal: goal,
              isSelected: widget.data.fitnessGoal == goal,
              onTap: () => setState(
                () => widget.data.fitnessGoal = goal,
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Continue button
          ElevatedButton(
            onPressed: _saveAndContinue,
            child: Text(
              'CONFIRM GOAL >',
              style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// Goal Card
class _GoalCard extends StatelessWidget {
  final FitnessGoal goal;
  final bool isSelected;
  final VoidCallback onTap;

  const _GoalCard({
    required this.goal,
    required this.isSelected,
    required this.onTap,
  });

  // All content lives here 
  static const Map<FitnessGoal, Map<String, dynamic>> _content = {
    FitnessGoal.muscleGain: {
      'title': 'MUSCLE GAIN',
      'description':
          'Prioritize hypertrophy, heavy resistance loading, and optimized recovery windows.',
      'icon': Icons.fitness_center_rounded,
    },
    FitnessGoal.weightLoss: {
      'title': 'WEIGHT LOSS',
      'description':
          'Focus on caloric deficit management, metabolic conditioning, and fat oxidation.',
      'icon': Icons.monitor_weight_outlined,
    },
    FitnessGoal.endurance: {
      'title': 'ENDURANCE',
      'description':
          'Enhance VO2 max, aerobic capacity, and muscular fatigue resistance protocols.',
      'icon': Icons.speed_rounded,
    },
    FitnessGoal.flexibility: {
      'title': 'FLEXIBILITY',
      'description':
          'Optimize joint mobility, fascia release, and dynamic range of motion training.',
      'icon': Icons.self_improvement_rounded,
    },
  };

  @override
  Widget build(BuildContext context) {
    final content = _content[goal]!;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.1)
              : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.outlineVariant,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Icon circle
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? AppColors.primary.withOpacity(0.2)
                    : AppColors.surfaceContainerHigh,
              ),
              child: Icon(
                content['icon'] as IconData,
                color: isSelected
                    ? AppColors.primary
                    : AppColors.onSurfaceVariant,
                size: 22,
              ),
            ),

            const SizedBox(width: 14),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    content['title'] as String,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    content['description'] as String,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Checkmark
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? AppColors.primary
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.onSurfaceVariant.withOpacity(0.4),
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: AppColors.onPrimary,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}