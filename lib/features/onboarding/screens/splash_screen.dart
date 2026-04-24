import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import 'onboarding_shell.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceBright,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              // Top label
              const SizedBox(height: 24),
              Text(
                'R A K A N',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 6,
                  color: AppColors.onSurfaceVariant,
                ),
              ),

              // Logo circle
              const Spacer(),
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceContainerLow,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.08),
                      blurRadius: 60,
                      spreadRadius: 20,
                    ),
                  ],
                ),
                child: Center(
                  // Placeholder for logo
                  child: Image.asset(
                    'assets/images/transparent_bg.png',
                    width: 200,
                    height: 200,
                  ),
                ),
              ),

              // Headline 
              const Spacer(),
              Text(
                'Start working\nout your way\nwith Rakan',
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  height: 1.15,
                ),
              ),

              // Buttons
              const Spacer(),
              // Get Started button
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const OnboardingShell(),
                    ),
                  );
                },
                child: Text(
                  'Get Started',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Already a member row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'ALREADY A MEMBER?  ',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      letterSpacing: 1.5,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      // TODO: navigate to login screen (Phase 3)
                    },
                    child: Text(
                      'LOG IN',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Neural Evolution divider
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 1,
                      color: AppColors.outlineVariant,
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

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}