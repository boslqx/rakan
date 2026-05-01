import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/main_shell.dart';
import '../models/onboarding_data.dart';

class WorkoutSummaryScreen extends StatelessWidget {
  final OnboardingData data;

  const WorkoutSummaryScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceBright,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text(
                'YOUR PLAN\nIS READY.',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 48,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'We\'ve built your personalized 7-day\ntraining protocol based on your profile.',
                style: GoogleFonts.manrope(
                  fontSize: 15,
                  color: AppColors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const Spacer(flex: 2),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => const MainShell(),
                    ),
                    (_) => false, // clears entire navigation stack
                  );
                },
                child: Text(
                  'START TRAINING →',
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}