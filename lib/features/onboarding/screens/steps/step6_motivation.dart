import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/onboarding_data.dart';

class Step6Motivation extends StatefulWidget {
  final OnboardingData data;
  final VoidCallback onNext;

  const Step6Motivation({super.key, required this.data, required this.onNext});

  @override
  State<Step6Motivation> createState() => _Step6MotivationState();
}

class _Step6MotivationState extends State<Step6Motivation> {
  void _saveAndContinue() {
    if (!widget.data.isStep6Valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select what motivates you',
            style: GoogleFonts.manrope(),
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    widget.onNext();
  }

  static const Map<Motivation, Map<String, dynamic>> _content = {
    Motivation.lookBetter: {
      'title': 'Look Better',
      'sub': 'Transform your physique and appearance',
      'icon': Icons.auto_awesome_rounded,
    },
    Motivation.buildStrength: {
      'title': 'Build Strength',
      'sub': 'Get stronger and more powerful',
      'icon': Icons.fitness_center_rounded,
    },
    Motivation.improveHealth: {
      'title': 'Improve Health',
      'sub': 'Feel healthier and live longer',
      'icon': Icons.favorite_rounded,
    },
    Motivation.boostEnergy: {
      'title': 'Boost Energy',
      'sub': 'Feel more energetic throughout the day',
      'icon': Icons.bolt_rounded,
    },
    Motivation.reduceStress: {
      'title': 'Reduce Stress',
      'sub': 'Use fitness as a mental reset',
      'icon': Icons.self_improvement_rounded,
    },
    Motivation.athleticPerformance: {
      'title': 'Athletic Performance',
      'sub': 'Train like an athlete, perform at your peak',
      'icon': Icons.emoji_events_rounded,
    },
  };

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          //  Headline
          Text(
            'WHAT MOTIVATES\nYOU MOST?',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This helps Rakan personalise your\ncoaching style and daily messages.',
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: AppColors.onSurfaceVariant,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 32),

          // Motivation cards
          ...Motivation.values.map((motivation) {
            final content = _content[motivation]!;
            final isSelected = widget.data.motivation == motivation;

            return GestureDetector(
              onTap: () => setState(
                () => widget.data.motivation = motivation,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withOpacity(0.1)
                      : AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
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
                    const SizedBox(width: 14),
                    // Text
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            content['title'] as String,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            content['sub'] as String,
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Radio indicator
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 22,
                      height: 22,
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
          }),

          const SizedBox(height: 32),

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
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}