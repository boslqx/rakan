import 'package:flutter/material.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/onboarding_data.dart';

class Step7FocusAreas extends StatefulWidget {
  final OnboardingData data;
  final VoidCallback onNext;

  const Step7FocusAreas({
    super.key,
    required this.data,
    required this.onNext,
  });

  @override
  State<Step7FocusAreas> createState() => _Step7FocusAreasState();
}

class _Step7FocusAreasState extends State<Step7FocusAreas> {
  bool _showFront = true;

  // Maps FocusArea to which muscles to highlight on the body map
  static const Map<FocusArea, List<Muscle>> _focusToMuscles = {
    FocusArea.chest: [Muscle.chest],
    FocusArea.back: [Muscle.upperBack, Muscle.lowerBack, Muscle.trapezius],
    FocusArea.arms: [Muscle.biceps, Muscle.triceps, Muscle.forearm],
    FocusArea.shoulders: [Muscle.deltoids],
    FocusArea.abs: [Muscle.abs, Muscle.obliques],
    FocusArea.legs: [
      Muscle.quadriceps,
      Muscle.hamstring,
      Muscle.calves,
      Muscle.adductors,
    ],
    FocusArea.glutes: [Muscle.gluteal],
    FocusArea.fullBody: [], // fullBody = all muscles highlighted
  };

  static const Map<FocusArea, String> _focusLabels = {
    FocusArea.chest: 'Chest',
    FocusArea.back: 'Back',
    FocusArea.arms: 'Arms',
    FocusArea.shoulders: 'Shoulders',
    FocusArea.abs: 'Abs',
    FocusArea.legs: 'Legs',
    FocusArea.glutes: 'Glutes',
    FocusArea.fullBody: 'Full Body',
  };

  static const Map<FocusArea, IconData> _focusIcons = {
    FocusArea.chest: Icons.accessibility_new_rounded,
    FocusArea.back: Icons.airline_seat_flat_rounded,
    FocusArea.arms: Icons.sports_gymnastics_rounded,
    FocusArea.shoulders: Icons.sports_handball_rounded,
    FocusArea.abs: Icons.crop_rounded,
    FocusArea.legs: Icons.directions_run_rounded,
    FocusArea.glutes: Icons.airline_seat_recline_normal_rounded,
    FocusArea.fullBody: Icons.person_rounded,
  };

  void _toggleFocusArea(FocusArea area) {
    setState(() {
      if (area == FocusArea.fullBody) {
        // Full body clears all others and selects only fullBody
        if (widget.data.focusAreas.contains(FocusArea.fullBody)) {
          widget.data.focusAreas.remove(FocusArea.fullBody);
        } else {
          widget.data.focusAreas = {FocusArea.fullBody};
        }
        return;
      }
      // Remove fullBody if selecting specific area
      widget.data.focusAreas.remove(FocusArea.fullBody);
      if (widget.data.focusAreas.contains(area)) {
        widget.data.focusAreas.remove(area);
      } else {
        widget.data.focusAreas.add(area);
      }
    });
  }

  // Build heatmap data from selected focus areas
  Map<Muscle, MuscleData> get _heatmapData {
    final Map<Muscle, MuscleData> data = {};

    if (widget.data.focusAreas.contains(FocusArea.fullBody)) {
      // Highlight everything
      for (final muscles in _focusToMuscles.values) {
        for (final muscle in muscles) {
          data[muscle] = const MuscleData(intensity: 1.0);
        }
      }
      return data;
    }

    for (final area in widget.data.focusAreas) {
      final muscles = _focusToMuscles[area] ?? [];
      for (final muscle in muscles) {
        data[muscle] = const MuscleData(intensity: 1.0);
      }
    }
    return data;
  }

  void _saveAndContinue() {
    if (!widget.data.isStep7Valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select at least one focus area',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Headline
              Text(
                'FOCUS\nAREAS',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Which areas do you want to prioritize?',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),

        // Side by side layout
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Body map
                SizedBox(
                  width: 140,
                  child: Column(
                    children: [
                      // Front/Back toggle
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(48),
                          border:
                              Border.all(color: AppColors.outlineVariant),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _SmallToggleChip(
                              label: 'F',
                              isSelected: _showFront,
                              onTap: () =>
                                  setState(() => _showFront = true),
                            ),
                            _SmallToggleChip(
                              label: 'B',
                              isSelected: !_showFront,
                              onTap: () =>
                                  setState(() => _showFront = false),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Body heatmap
                      Expanded(
                        child: BodyHeatmap(
                          side: _showFront
                              ? BodySide.front
                              : BodySide.back,
                          gender:
                              widget.data.gender == Gender.female
                                  ? BodyGender.female
                                  : BodyGender.male,
                          data: _heatmapData,
                          colors: [
                            AppColors.primary.withOpacity(0.4),
                            AppColors.primary,
                          ],
                          bodyColor: AppColors.surfaceContainerHigh,
                          borderColor: AppColors.outlineVariant,
                          showBorder: true,
                          // Tapping body syncs to chip selection
                          onMusclePressed: (muscle, side) {
                            // Find which FocusArea this muscle belongs to
                            for (final entry
                                in _focusToMuscles.entries) {
                              if (entry.value.contains(muscle)) {
                                _toggleFocusArea(entry.key);
                                break;
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Right: Chips
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 36),
                        ...FocusArea.values.map((area) {
                          final isSelected =
                              widget.data.focusAreas.contains(area);
                          return GestureDetector(
                            onTap: () => _toggleFocusArea(area),
                            child: AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary.withOpacity(0.15)
                                    : AppColors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.outlineVariant,
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _focusIcons[area]!,
                                    size: 16,
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _focusLabels[area]!,
                                    style: GoogleFonts.manrope(
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: isSelected
                                          ? AppColors.primary
                                          : AppColors.onSurface,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (isSelected)
                                    Icon(
                                      Icons.check_rounded,
                                      size: 14,
                                      color: AppColors.primary,
                                    ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Continue button
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: ElevatedButton(
            onPressed: _saveAndContinue,
            child: Text(
              'CONTINUE >',
              style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Small toggle chip for F/B toggle
class _SmallToggleChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SmallToggleChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(48),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? AppColors.onPrimary
                : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}