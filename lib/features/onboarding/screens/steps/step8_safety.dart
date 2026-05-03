import 'package:flutter/material.dart';
import 'package:flutter_body_heatmap/flutter_body_heatmap.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/onboarding_data.dart';
import 'body_map_painter.dart';

class Step8Safety extends StatefulWidget {
  final OnboardingData data;
  final VoidCallback onNext;

  const Step8Safety({super.key, required this.data, required this.onNext});

  @override
  State<Step8Safety> createState() => _Step8SafetyState();
}

class _Step8SafetyState extends State<Step8Safety> {
  bool _showFront = true;

  // These dots are calibrated for the larger centered map
  // The BodyHeatmap widget has internal padding — dots are tuned accordingly
  static const List<Map<String, dynamic>> _frontDots = [
    {'region': BodyRegion.head, 'x': 0.50, 'y': 0.075},
    {'region': BodyRegion.neck, 'x': 0.50, 'y': 0.145},
    {'region': BodyRegion.leftShoulder, 'x': 0.41, 'y': 0.195},
    {'region': BodyRegion.rightShoulder, 'x': 0.59, 'y': 0.195},
    {'region': BodyRegion.chest, 'x': 0.50, 'y': 0.245},
    {'region': BodyRegion.leftArm, 'x': 0.37, 'y': 0.360},
    {'region': BodyRegion.rightArm, 'x': 0.63, 'y': 0.360},
    {'region': BodyRegion.core, 'x': 0.50, 'y': 0.340},
    {'region': BodyRegion.leftKnee, 'x': 0.45, 'y': 0.550},
    {'region': BodyRegion.rightKnee, 'x': 0.55, 'y': 0.550},
    {'region': BodyRegion.leftAnkle, 'x': 0.45, 'y': 0.740},
    {'region': BodyRegion.rightAnkle, 'x': 0.55, 'y': 0.740},
  ];

  static const List<Map<String, dynamic>> _backDots = [
    {'region': BodyRegion.head, 'x': 0.50, 'y': 0.075},
    {'region': BodyRegion.neck, 'x': 0.50, 'y': 0.145},
    {'region': BodyRegion.leftShoulder, 'x': 0.41, 'y': 0.195},
    {'region': BodyRegion.rightShoulder, 'x': 0.59, 'y': 0.195},
    {'region': BodyRegion.upperBack, 'x': 0.50, 'y': 0.235},
    {'region': BodyRegion.leftArm, 'x': 0.37, 'y': 0.360},
    {'region': BodyRegion.rightArm, 'x': 0.63, 'y': 0.360},
    {'region': BodyRegion.lowerBack, 'x': 0.50, 'y': 0.320},
    {'region': BodyRegion.leftHip, 'x': 0.46, 'y': 0.415},
    {'region': BodyRegion.rightHip, 'x': 0.54, 'y': 0.415},
    {'region': BodyRegion.leftKnee, 'x': 0.45, 'y': 0.550},
    {'region': BodyRegion.rightKnee, 'x': 0.55, 'y': 0.550},
    {'region': BodyRegion.leftAnkle, 'x': 0.45, 'y': 0.740},
    {'region': BodyRegion.rightAnkle, 'x': 0.55, 'y': 0.740},
  ];
  
  Set<BodyRegion> get _injuredRegions =>
      widget.data.injuries.map((i) => i.region).toSet();

  Map<Muscle, MuscleData> get _heatmapData {
    final Map<Muscle, MuscleData> data = {};
    const regionToMuscle = {
      BodyRegion.head: Muscle.head,
      BodyRegion.neck: Muscle.neck,
      BodyRegion.chest: Muscle.chest,
      BodyRegion.leftShoulder: Muscle.deltoids,
      BodyRegion.rightShoulder: Muscle.deltoids,
      BodyRegion.upperBack: Muscle.upperBack,
      BodyRegion.leftArm: Muscle.biceps,
      BodyRegion.rightArm: Muscle.triceps,
      BodyRegion.core: Muscle.abs,
      BodyRegion.lowerBack: Muscle.lowerBack,
      BodyRegion.leftHip: Muscle.adductors,
      BodyRegion.rightHip: Muscle.gluteal,
      BodyRegion.leftKnee: Muscle.quadriceps,
      BodyRegion.rightKnee: Muscle.hamstring,
      BodyRegion.leftAnkle: Muscle.calves,
      BodyRegion.rightAnkle: Muscle.ankles,
    };
    for (final region in _injuredRegions) {
      final muscle = regionToMuscle[region];
      if (muscle != null) {
        data[muscle] = MuscleData(
          intensity: 1.0,
          color: AppColors.error,
        );
      }
    }
    return data;
  }

  String _regionLabel(BodyRegion region) {
    const labels = {
      BodyRegion.head: 'Head',
      BodyRegion.neck: 'Neck',
      BodyRegion.leftShoulder: 'Left Shoulder',
      BodyRegion.rightShoulder: 'Right Shoulder',
      BodyRegion.chest: 'Chest',
      BodyRegion.upperBack: 'Upper Back',
      BodyRegion.leftArm: 'Left Arm',
      BodyRegion.rightArm: 'Right Arm',
      BodyRegion.core: 'Core',
      BodyRegion.lowerBack: 'Lower Back',
      BodyRegion.leftHip: 'Left Hip',
      BodyRegion.rightHip: 'Right Hip',
      BodyRegion.leftKnee: 'Left Knee',
      BodyRegion.rightKnee: 'Right Knee',
      BodyRegion.leftAnkle: 'Left Ankle',
      BodyRegion.rightAnkle: 'Right Ankle',
    };
    return labels[region] ?? region.name;
  }

  void _showInjurySheet(BodyRegion region) {
    final injuries = regionInjuries[region] ?? [];
    final zoneName = _regionLabel(region);
    final currentLabels = widget.data.injuries
        .where((i) => i.region == region)
        .map((i) => i.label)
        .toSet();
    final TextEditingController customController =
        TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
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
                      ...injuries.map((injury) {
                        final isSelected =
                            currentLabels.contains(injury);
                        return GestureDetector(
                          onTap: () => setSheetState(() {
                            if (isSelected) {
                              currentLabels.remove(injury);
                            } else {
                              currentLabels.add(injury);
                            }
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.error.withOpacity(0.1)
                                  : AppColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(12),
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
                              color: AppColors.outlineVariant),
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
                            contentPadding: const EdgeInsets.symmetric(
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
                              (i) => i.region == region);
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
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dots = _showFront ? _frontDots : _backDots;

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                'Tap the glowing dots to log injuries\nor limitations. This step is optional.',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: AppColors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),

              // Front/Back toggle — centered
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
                      _ToggleChip(
                        label: 'FRONT',
                        isSelected: _showFront,
                        onTap: () => setState(() => _showFront = true),
                      ),
                      _ToggleChip(
                        label: 'BACK',
                        isSelected: !_showFront,
                        onTap: () => setState(() => _showFront = false),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),

        // Body map with dots — centered and enlarged
        Expanded(
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Map takes 75% of available width, maintains aspect ratio
                final mapWidth = constraints.maxWidth * 0.98;
                final mapHeight = constraints.maxHeight * 1.2;

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Body heatmap
                    SizedBox(
                      width: mapWidth,
                      height: mapHeight,
                      child: BodyHeatmap(
                        side: _showFront
                            ? BodySide.front
                            : BodySide.back,
                        gender: widget.data.gender == Gender.female
                            ? BodyGender.female
                            : BodyGender.male,
                        data: _heatmapData,
                        colors: [
                          AppColors.error.withOpacity(0.3),
                          AppColors.error,
                        ],
                        bodyColor: AppColors.surfaceContainerHigh,
                        borderColor: AppColors.outlineVariant,
                        showBorder: true,
                      ),
                    ),

                    // Dot overlay — positioned relative to map size
                    SizedBox(
                      width: mapWidth,
                      height: mapHeight,
                      child: Stack(
                        key: ValueKey(_showFront),
                        children: dots.map((dot) {
                          final region = dot['region'] as BodyRegion;
                          final isInjured =
                              _injuredRegions.contains(region);
                          // Subtract half dot size (8px) to center the dot
                          final dx = (dot['x'] as double) * mapWidth - 8;
                          final dy =
                              (dot['y'] as double) * mapHeight - 8;

                          return Positioned(
                            left: dx,
                            top: dy,
                            child: GestureDetector(
                              onTap: () => _showInjurySheet(region),
                              child: _InjuryDot(isInjured: isInjured),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),

        // Logged injuries summary 
        if (widget.data.injuries.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.data.injuries.map((injury) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
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
                        '${_regionLabel(injury.region)} · ${injury.label}',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          color: AppColors.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () => setState(() {
                          widget.data.injuries.remove(injury);
                        }),
                        child: Icon(
                          Icons.close_rounded,
                          size: 12,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

        // Bottom buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            children: [
              if (widget.data.injuries.isEmpty)
                TextButton(
                  onPressed: widget.onNext,
                  child: Text(
                    'I HAVE NO INJURIES — SKIP',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              if (widget.data.injuries.isNotEmpty) ...[
                Text(
                  '${widget.data.injuries.length} injur${widget.data.injuries.length == 1 ? 'y' : 'ies'} logged',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              ElevatedButton(
                onPressed: widget.onNext,
                child: Text(
                  'FINISH ONBOARDING →',
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Pulsing dot
class _InjuryDot extends StatefulWidget {
  final bool isInjured;
  const _InjuryDot({required this.isInjured});

  @override
  State<_InjuryDot> createState() => _InjuryDotState();
}

class _InjuryDotState extends State<_InjuryDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.isInjured
              ? AppColors.error
              : AppColors.primary.withOpacity(0.9),
          border: Border.all(
            color: Colors.white.withOpacity(0.7),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: widget.isInjured
                  ? AppColors.error.withOpacity(0.6)
                  : AppColors.primary.withOpacity(0.5),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }
}

// Front/Back toggle chip
class _ToggleChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleChip({
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
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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