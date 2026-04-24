import 'package:flutter/material.dart';
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
  // Which regions are currently injured
  Set<BodyRegion> get _injuredRegions =>
      widget.data.injuries.map((i) => i.region).toSet();

  void _onRegionTapped(BodyRegion region, Size mapSize) {
    _showInjuryBottomSheet(region);
  }

  void _showInjuryBottomSheet(BodyRegion region) {
    final injuries = regionInjuries[region] ?? [];
    final zoneName = bodyZones
        .firstWhere((z) => z.region == region)
        .label;

    // Current selections for this region
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
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
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

                        // Predefined injury options
                        ...injuries.map((injury) {
                          final isSelected = currentLabels.contains(injury);
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

                        // Custom injury input
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
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Confirm button
                        ElevatedButton(
                          onPressed: () {
                            // Remove all existing injuries for this region
                            widget.data.injuries
                                .removeWhere((i) => i.region == region);

                            // Add selected predefined injuries
                            for (final label in currentLabels) {
                              widget.data.injuries.add(InjuryEntry(
                                region: region,
                                label: label,
                              ));
                            }

                            // Add custom injury if filled
                            final custom = customController.text.trim();
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
            );
          },
        );
      },
    );
  }

  void _removeInjury(InjuryEntry injury) {
    setState(() {
      widget.data.injuries.remove(injury);
    });
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
            'Tap any body region where you have injuries\nor limitations. This step is optional.',
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: AppColors.onSurfaceVariant,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 24),

          // Body map 
          Center(
            child: SizedBox(
              width: 220,
              height: 380,
              child: GestureDetector(
                onTapDown: (details) {
                  // Convert tap position to normalized coordinates
                  final box = context.findRenderObject() as RenderBox?;
                  if (box == null) return;

                  // Find which zone was tapped
                  const mapWidth = 220.0;
                  const mapHeight = 380.0;

                  // Get local position within the map widget
                  final localPos = details.localPosition;
                  final normX = localPos.dx / mapWidth;
                  final normY = localPos.dy / mapHeight;

                  for (final zone in bodyZones) {
                    if (zone.normalizedRect.contains(
                      Offset(normX, normY),
                    )) {
                      _showInjuryBottomSheet(zone.region);
                      break;
                    }
                  }
                },
                child: CustomPaint(
                  painter: BodyMapPainter(
                    highlightedRegions: _injuredRegions,
                  ),
                  size: const Size(220, 380),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),
          Center(
            child: Text(
              'TAP A BODY REGION TO LOG AN INJURY',
              style: GoogleFonts.manrope(
                fontSize: 10,
                letterSpacing: 1.5,
                color: AppColors.onSurfaceVariant.withOpacity(0.5),
              ),
            ),
          ),

          // Selected injuries 
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
                final zoneName = bodyZones
                    .firstWhere((z) => z.region == injury.region)
                    .label;
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
                        '$zoneName · ${injury.label}',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: AppColors.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _removeInjury(injury),
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