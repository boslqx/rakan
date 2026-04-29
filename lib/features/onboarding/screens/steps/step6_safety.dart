import 'package:flutter/material.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/onboarding_data.dart';
import 'body_map_painter.dart';

class Step6Safety extends StatefulWidget {
  final OnboardingData data;
  final VoidCallback onNext;

  const Step6Safety({super.key, required this.data, required this.onNext});

  @override
  State<Step6Safety> createState() => _Step6SafetyState();
}

class _Step6SafetyState extends State<Step6Safety> {
  // Which side of the body is currently shown
  bool _showFront = true;

  // Maps BodyRegion enum to the package's Muscle enum
  // Not every BodyRegion has a direct Muscle equivalent — map the closest
  static const Map<Muscle, BodyRegion> _muscleToRegion = {
    // Head & Neck
    Muscle.head: BodyRegion.head,
    Muscle.neck: BodyRegion.neck,

    // Upper body front
    Muscle.chest: BodyRegion.chest,
    Muscle.deltoids: BodyRegion.leftShoulder,
    Muscle.trapezius: BodyRegion.upperBack,
    Muscle.biceps: BodyRegion.leftArm,
    Muscle.triceps: BodyRegion.rightArm,
    Muscle.forearm: BodyRegion.leftArm,

    // Core
    Muscle.abs: BodyRegion.core,
    Muscle.obliques: BodyRegion.core,

    // Back
    Muscle.upperBack: BodyRegion.upperBack,
    Muscle.lowerBack: BodyRegion.lowerBack,

    // Hips & Glutes
    Muscle.gluteal: BodyRegion.leftHip,
    Muscle.adductors: BodyRegion.rightHip,

    // Legs
    Muscle.quadriceps: BodyRegion.leftKnee,
    Muscle.hamstring: BodyRegion.rightKnee,
    Muscle.tibialis: BodyRegion.leftKnee,
    Muscle.knees: BodyRegion.leftKnee,

    // Lower leg
    Muscle.calves: BodyRegion.leftAnkle,
    Muscle.ankles: BodyRegion.rightAnkle,
  };

  // Build heatmap data from current injuries
  // Injured regions show as red (error color) at full intensity
  Map<Muscle, MuscleData> get _heatmapData {
    final Map<Muscle, MuscleData> data = {};
    final injuredRegions = widget.data.injuries
        .map((i) => i.region)
        .toSet();

    for (final entry in _muscleToRegion.entries) {
      if (injuredRegions.contains(entry.value)) {
        data[entry.key] = const MuscleData(intensity: 1.0);
      }
    }
    return data;
  }

  void _onMuscleTapped(Muscle muscle, MuscleSide side) {
    final region = _muscleToRegion[muscle];
    if (region == null) return;
    _showInjuryBottomSheet(region);
  }

  void _showInjuryBottomSheet(BodyRegion region) {
    final injuries = regionInjuries[region] ?? [];
    final zoneName = _regionDisplayName(region);

    final currentLabels = widget.data.injuries
        .where((i) => i.region == region)
        .map((i) => i.label)
        .toSet();

    final TextEditingController customController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 16),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            zoneName.toUpperCase(),
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface,
                            ),
                          ),
                          Text(
                            'Select all injuries that apply',
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Predefined options
                          ...injuries.map((injury) {
                            final isSelected =
                                currentLabels.contains(injury);
                            return GestureDetector(
                              onTap: () {
                                setSheetState(() {
                                  if (isSelected) {
                                    currentLabels.remove(injury);
                                  } else {
                                    currentLabels.add(injury);
                                  }
                                });
                              },
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 150),
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.error.withOpacity(0.1)
                                      : AppColors.surfaceContainerHigh,
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.error
                                        : AppColors.outlineVariant,
                                    width: isSelected ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        injury,
                                        style: GoogleFonts.manrope(
                                          fontSize: 14,
                                          color: isSelected
                                              ? AppColors.error
                                              : AppColors.onSurface,
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                        ),
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(
                                        Icons.check_circle_rounded,
                                        color: AppColors.error,
                                        size: 18,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),

                          // Custom input
                          const SizedBox(height: 8),
                          Text(
                            'OTHER',
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.outlineVariant,
                              ),
                            ),
                            child: TextField(
                              controller: customController,
                              style: GoogleFonts.manrope(
                                color: AppColors.onSurface,
                                fontSize: 14,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Describe your injury...',
                                hintStyle: GoogleFonts.manrope(
                                  color: AppColors.onSurfaceVariant
                                      .withOpacity(0.5),
                                  fontSize: 14,
                                ),
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          ElevatedButton(
                            onPressed: () {
                              widget.data.injuries.removeWhere(
                                (i) => i.region == region,
                              );
                              for (final label in currentLabels) {
                                widget.data.injuries.add(InjuryEntry(
                                  region: region,
                                  label: label,
                                ));
                              }
                              final custom =
                                  customController.text.trim();
                              if (custom.isNotEmpty) {
                                widget.data.injuries.add(InjuryEntry(
                                  region: region,
                                  label: custom,
                                  isCustom: true,
                                ));
                              }
                              setState(() {});
                              Navigator.pop(context);
                            },
                            child: Text(
                              'CONFIRM',
                              style: GoogleFonts.spaceGrotesk(
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _regionDisplayName(BodyRegion region) {
    const names = {
      BodyRegion.head: 'Head',
      BodyRegion.neck: 'Neck',
      BodyRegion.leftShoulder: 'Left Shoulder',
      BodyRegion.rightShoulder: 'Right Shoulder',
      BodyRegion.chest: 'Chest',
      BodyRegion.upperBack: 'Upper Back',
      BodyRegion.leftArm: 'Left Arm',
      BodyRegion.rightArm: 'Right Arm',
      BodyRegion.core: 'Core / Abs',
      BodyRegion.lowerBack: 'Lower Back',
      BodyRegion.leftHip: 'Left Hip',
      BodyRegion.rightHip: 'Right Hip',
      BodyRegion.leftKnee: 'Left Knee',
      BodyRegion.rightKnee: 'Right Knee',
      BodyRegion.leftAnkle: 'Left Ankle',
      BodyRegion.rightAnkle: 'Right Ankle',
    };
    return names[region] ?? region.name;
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
            'SAFETY\nPROFILE',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap any muscle where you have injuries\nor limitations. This step is optional.',
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: AppColors.onSurfaceVariant,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 24),

          // Front / Back toggle
          Center(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(48),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ViewToggleChip(
                    label: 'FRONT',
                    isSelected: _showFront,
                    onTap: () => setState(() => _showFront = true),
                  ),
                  _ViewToggleChip(
                    label: 'BACK',
                    isSelected: !_showFront,
                    onTap: () => setState(() => _showFront = false),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Body heatmap 
          Center(
            child: SizedBox(
              height: 500,
              width: 300,
              child: BodyHeatmap(
                side: _showFront ? BodySide.front : BodySide.back,
                // Use gender from onboarding data
                gender: widget.data.gender == Gender.female
                    ? BodyGender.female
                    : BodyGender.male,
                data: _heatmapData,
                // Red for injuries — matches our error color
                colors: [
                  AppColors.error.withOpacity(0.3),
                  AppColors.error,
                ],
                bodyColor: AppColors.surfaceContainerHigh,
                borderColor: AppColors.outlineVariant,
                showBorder: true,
                onMusclePressed: _onMuscleTapped,
              ),
            ),
          ),

          const SizedBox(height: 8),
          Center(
            child: Text(
              'TAP A MUSCLE TO LOG AN INJURY',
              style: GoogleFonts.manrope(
                fontSize: 10,
                letterSpacing: 1.5,
                color: AppColors.onSurfaceVariant.withOpacity(0.5),
              ),
            ),
          ),

          // Logged injuries
          if (widget.data.injuries.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'LOGGED INJURIES',
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.data.injuries.map((injury) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(48),
                    border: Border.all(
                      color: AppColors.error.withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_regionDisplayName(injury.region)} · ${injury.label}',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: AppColors.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            widget.data.injuries.remove(injury);
                          });
                        },
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 32),

          // Finish button
          ElevatedButton(
            onPressed: widget.onNext,
            child: Text(
              widget.data.injuries.isEmpty
                  ? 'SKIP & FINISH ONBOARDING →'
                  : 'FINISH ONBOARDING →',
              style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),

          const SizedBox(height: 16),

          Center(
            child: Text(
              'YOUR AI COACH IS FINALIZING YOUR PROFILE...',
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

// View Toggle Chip
class _ViewToggleChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ViewToggleChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(48),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
            color: isSelected
                ? AppColors.onPrimary
                : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}