import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../models/onboarding_data.dart';

/// Shared equipment multi-select UI + selection rules.
class EquipmentSelector extends StatefulWidget {
  final Set<EquipmentType> initialSelection;
  final ValueChanged<Set<EquipmentType>> onChanged;

  const EquipmentSelector({
    super.key,
    required this.initialSelection,
    required this.onChanged,
  });

  @override
  State<EquipmentSelector> createState() => _EquipmentSelectorState();
}

class _EquipmentSelectorState extends State<EquipmentSelector> {
  late Set<EquipmentType> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<EquipmentType>.from(widget.initialSelection);
  }

  // Rules (unchanged from the original Step5Environment logic)
  void _handleTap(EquipmentType tapped) {
    setState(() {
      if (tapped == EquipmentType.noEquipment) {
        _selected = {EquipmentType.noEquipment};
      } else if (tapped == EquipmentType.fullGym) {
        if (_selected.contains(EquipmentType.fullGym)) {
          _selected.remove(EquipmentType.fullGym);
        } else {
          _selected = {
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
      } else {
        _selected.remove(EquipmentType.noEquipment);
        if (_selected.contains(tapped)) {
          _selected.remove(tapped);
          _selected.remove(EquipmentType.fullGym);
        } else {
          _selected.add(tapped);
        }
      }
    });
    widget.onChanged(_selected);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EquipmentTile(
          type: EquipmentType.fullGym,
          isSelected: _selected.contains(EquipmentType.fullGym),
          onTap: () => _handleTap(EquipmentType.fullGym),
        ),
        const SizedBox(height: 10),
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
              isSelected: _selected.contains(type),
              onTap: () => _handleTap(type),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Container(height: 1, color: AppColors.outlineVariant),
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
                child: Container(height: 1, color: AppColors.outlineVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _EquipmentTile(
          type: EquipmentType.noEquipment,
          isSelected: _selected.contains(EquipmentType.noEquipment),
          onTap: () => _handleTap(EquipmentType.noEquipment),
        ),
      ],
    );
  }
}

// Equipment Tile — moved here from step5_environment.dart
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.outlineVariant,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : AppColors.surfaceContainerHigh,
              ),
              child: Icon(
                content['icon'] as IconData,
                color:
                    isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
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
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: isSelected ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.onSurfaceVariant.withValues(alpha: 0.4),
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