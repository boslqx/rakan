import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/onboarding_data.dart';
import '../../widgets/equipment_selector.dart';

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
              color: AppColors.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),

          const SizedBox(height: 28),

          // Shared picker — mutates widget.data.equipment directly via
          // onChanged, same as the old inline logic did.
          EquipmentSelector(
            initialSelection: widget.data.equipment,
            onChanged: (selected) {
              widget.data.equipment = selected;
            },
          ),

          const SizedBox(height: 16),

          // AI finalizing label
          Center(
            child: Text(
              'YOUR AI COACH IS FINALIZING YOUR PROFILE...',
              style: GoogleFonts.manrope(
                fontSize: 10,
                letterSpacing: 1.5,
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.4),
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