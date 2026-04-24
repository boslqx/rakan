import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/onboarding_data.dart';

class Step3Experience extends StatefulWidget {
  final OnboardingData data;
  final VoidCallback onNext;

  const Step3Experience({super.key, required this.data, required this.onNext});

  @override
  State<Step3Experience> createState() => _Step3ExperienceState();
}

class _Step3ExperienceState extends State<Step3Experience> {
  void _saveAndContinue() {
    if (!widget.data.isStep3Valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select your experience level',
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
            'WORKOUT\nEXPERIENCE',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tailor your training plan by selecting the level\nthat matches your physical journey.',
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: AppColors.onSurfaceVariant,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 32),

          // Experience cards
          ...ExperienceLevel.values.map(
            (level) => _ExperienceCard(
              level: level,
              isSelected: widget.data.experienceLevel == level,
              onTap: () => setState(
                () => widget.data.experienceLevel = level,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Info box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: AppColors.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your experience level shapes exercise complexity, '
                    'rest periods, and progressive overload strategy. '
                    'You can always update this as you improve.',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Continue button
          ElevatedButton(
            onPressed: _saveAndContinue,
            child: Text(
              'CONTINUE >',
              style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),

          // AI initialising label ─────────────────────────────────────
          const SizedBox(height: 16),
          Center(
            child: Text(
              'PRECISION AI TRAINING ALGORITHM INITIALISING...',
              style: GoogleFonts.manrope(
                fontSize: 10,
                letterSpacing: 1.5,
                color: AppColors.onSurfaceVariant.withOpacity(0.4),
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// Experience Card
class _ExperienceCard extends StatelessWidget {
  final ExperienceLevel level;
  final bool isSelected;
  final VoidCallback onTap;

  const _ExperienceCard({
    required this.level,
    required this.isSelected,
    required this.onTap,
  });

  static const Map<ExperienceLevel, Map<String, dynamic>> _content = {
    ExperienceLevel.beginner: {
      'title': 'Beginner',
      'duration': '0 – 6 MONTHS',
      'description':
          'Focus on fundamental movements, proper form, and building a consistent routine.',
      'icon': Icons.fitness_center_rounded,
    },
    ExperienceLevel.intermediate: {
      'title': 'Intermediate',
      'duration': '6 – 24 MONTHS',
      'description':
          'Ready for advanced splits, progressive overload, and high-intensity performance metrics.',
      'icon': Icons.monitor_heart_rounded,
    },
    ExperienceLevel.advanced: {
      'title': 'Advanced',
      'duration': '24+ MONTHS',
      'description':
          'Optimized periodization, max strength protocols, and precision performance tracking.',
      'icon': Icons.bolt_rounded,
    },
  };

  @override
  Widget build(BuildContext context) {
    final content = _content[level]!;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Text block
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    content['title'] as String,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    content['duration'] as String,
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
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

            // Icon + checkmark stack
            Stack(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
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
                // Checkmark badge on top right of icon
                if (isSelected)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 10,
                        color: AppColors.onPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}