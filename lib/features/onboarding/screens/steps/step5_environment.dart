import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/onboarding_data.dart';

class Step5Environment extends StatefulWidget {
  final OnboardingData data;
  final VoidCallback onNext;

  const Step5Environment({
    super.key,
    required this.data,
    required this.onNext,
  });

  @override
  State<Step5Environment> createState() => _Step5EnvironmentState();
}

class _Step5EnvironmentState extends State<Step5Environment> {
  void _handleTap(EquipmentType tapped) {
    setState(() {
      // Rules:
      // 1. Tapping fullGym selects everything except noEquipment
      // 2. Tapping noEquipment clears everything else
      // 3. If fullGym is already selected and user taps something else, deselect fullGym and select only that item

      if (tapped == EquipmentType.noEquipment) {
        // Clear all, select only noEquipment
        widget.data.equipment = {EquipmentType.noEquipment};
        return;
      }

      if (tapped == EquipmentType.fullGym) {
        if (widget.data.equipment.contains(EquipmentType.fullGym)) {
          // Deselect fullGym
          widget.data.equipment.remove(EquipmentType.fullGym);
        } else {
          // Select everything except noEquipment
          widget.data.equipment = {
            EquipmentType.fullGym,
            EquipmentType.barbell,
            EquipmentType.dumbbell,
            EquipmentType.kettlebell,
            EquipmentType.resistanceBand,
            EquipmentType.pullUpBar,
            EquipmentType.bench,
            EquipmentType.machines,
          };
        }
        return;
      }

      // Remove noEquipment if it was selected
      widget.data.equipment.remove(EquipmentType.noEquipment);

      if (widget.data.equipment.contains(tapped)) {
        widget.data.equipment.remove(tapped);
        // Also deselect fullGym if we're removing something from it
        widget.data.equipment.remove(EquipmentType.fullGym);
      } else {
        widget.data.equipment.add(tapped);
      }
    });
  }

  void _saveAndContinue() {
    if (!widget.data.isStep5Valid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please select at least one equipment option',
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
            'TRAINING\nRESOURCES',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 36,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'What equipment do you have access to?\nSelect all that apply.',
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: AppColors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You can update this anytime in settings.',
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: AppColors.onSurfaceVariant.withOpacity(0.6),
            ),
          ),

          const SizedBox(height: 28),

          // Full gym — full width
          _EquipmentTile(
            type: EquipmentType.fullGym,
            isSelected: widget.data.equipment
                .contains(EquipmentType.fullGym),
            onTap: () => _handleTap(EquipmentType.fullGym),
          ),

          const SizedBox(height: 10),

          // Individual equipment
          ...[
            EquipmentType.barbell,
            EquipmentType.dumbbell,
            EquipmentType.kettlebell,
            EquipmentType.resistanceBand,
            EquipmentType.pullUpBar,
            EquipmentType.bench,
            EquipmentType.machines,
          ].map(
            (type) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _EquipmentTile(
                type: type,
                isSelected: widget.data.equipment.contains(type),
                onTap: () => _handleTap(type),
              ),
            ),
          ),

          const SizedBox(height: 4),

          // Divider 
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 1,
                    color: AppColors.outlineVariant,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'OR',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      letterSpacing: 2,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    height: 1,
                    color: AppColors.outlineVariant,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // No equipment
          _EquipmentTile(
            type: EquipmentType.noEquipment,
            isSelected: widget.data.equipment
                .contains(EquipmentType.noEquipment),
            onTap: () => _handleTap(EquipmentType.noEquipment),
          ),

          const SizedBox(height: 16),

          // AI finalizing label
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

          const SizedBox(height: 24),

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

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// Equipment Tile
class _EquipmentTile extends StatelessWidget {
  final EquipmentType type;
  final bool isSelected;
  final VoidCallback onTap;

  const _EquipmentTile({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  static const Map<EquipmentType, Map<String, dynamic>> _content = {
    EquipmentType.fullGym: {
      'title': 'Full Gym',
      'sub': 'Complete access to all equipment',
      'icon': Icons.business_rounded,
    },
    EquipmentType.barbell: {
      'title': 'Barbells',
      'sub': 'Barbell + weight plates',
      'icon': Icons.fitness_center_rounded,
    },
    EquipmentType.dumbbell: {
      'title': 'Dumbbells',
      'sub': 'Fixed or adjustable dumbbells',
      'icon': Icons.sports_gymnastics_rounded,
    },
    EquipmentType.kettlebell: {
      'title': 'Kettlebells',
      'sub': 'One or more kettlebells',
      'icon': Icons.sports_mma_rounded,
    },
    EquipmentType.resistanceBand: {
      'title': 'Resistance Bands',
      'sub': 'Loop or tube bands',
      'icon': Icons.cable_rounded,
    },
    EquipmentType.pullUpBar: {
      'title': 'Pull-Up Bar',
      'sub': 'Doorframe or wall-mounted bar',
      'icon': Icons.arrow_upward_rounded,
    },
    EquipmentType.bench: {
      'title': 'Workout Bench',
      'sub': 'Flat, incline, or adjustable bench',
      'icon': Icons.weekend_rounded,
    },
    EquipmentType.machines: {
      'title': 'Machines',
      'sub': 'Cable machines, leg press, etc.',
      'icon': Icons.precision_manufacturing_rounded,
    },
    EquipmentType.noEquipment: {
      'title': 'None of the above',
      'sub': 'Bodyweight training only',
      'icon': Icons.directions_run_rounded,
    },
  };

  @override
  Widget build(BuildContext context) {
    final content = _content[type]!;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
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
            // Icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
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
                size: 20,
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
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.onSurface,
                    ),
                  ),
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

            // Checkbox
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
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