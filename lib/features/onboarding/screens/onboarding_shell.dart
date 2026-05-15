import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../models/onboarding_data.dart';
import 'plan_generation_screen.dart';
import 'steps/step1_profile.dart';
import 'steps/step2_goal.dart';
import 'steps/step3_experience.dart';
import 'steps/step4_preference.dart';
import 'steps/step5_environment.dart';
import 'steps/step6_motivation.dart';
import 'steps/step7_focus_areas.dart';
import 'steps/step8_safety.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_profile_service.dart';

class OnboardingShell extends StatefulWidget {
  const OnboardingShell({super.key});

  @override
  State<OnboardingShell> createState() => _OnboardingShellState();
}

class _OnboardingShellState extends State<OnboardingShell> {
  final OnboardingData _data = OnboardingData();
  int _currentStep = 0;
  static const int _totalSteps = 8;

  static const List<String> _stepTitles = [
    'Personal Profile',
    'Primary Focus',
    'Workout Experience',
    'Workout Preference',
    'Training Resources',
    'Your Motivation',
    'Focus Areas',
    'Safety Profile',
  ];

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
    } else {
      _finishOnboarding(); // no await needed here, fire and forget
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _finishOnboarding() async {
    // Get the currently logged-in user's uid
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      // Safety check: if somehow no user is logged in, don't crash
      debugPrint('ERROR: No user logged in during onboarding finish');
      return;
    }

    try {
      // Save to Firestore before navigating
      await UserProfileService().saveOnboardingProfile(
        uid: uid,
        data: _data,
      );
      debugPrint('✅ Onboarding data saved for user: $uid');
    } catch (e) {
      // Log the error but still navigate
      debugPrint('❌ Failed to save onboarding data: $e');
    }

    // Navigate regardless of save success
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, animation, __) => PlanGenerationScreen(data: _data),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return Step1Profile(data: _data, onNext: _nextStep);
      case 1:
        return Step2Goal(data: _data, onNext: _nextStep);
      case 2:
        return Step3Experience(data: _data, onNext: _nextStep);
      case 3:
        return Step4Preference(data: _data, onNext: _nextStep);
      case 4:
        return Step5Environment(data: _data, onNext: _nextStep);
      case 5:
        return Step6Motivation(data: _data, onNext: _nextStep);
      case 6:
        return Step7FocusAreas(data: _data, onNext: _nextStep);
      case 7:
        return Step8Safety(data: _data, onNext: _nextStep);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final double progress = (_currentStep + 1) / _totalSteps;
    final String progressLabel = _currentStep == _totalSteps - 1
        ? '100% COMPLETE'
        : '${((_currentStep + 1) / _totalSteps * 100).round()}%';

    return Scaffold(
      backgroundColor: AppColors.surfaceBright,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _previousStep,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: AppColors.onSurface,
                        size: 20,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'RAKAN AI',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 40),
                ],
              ),
            ),

            // Progress
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'STEP ${_currentStep + 1} OF $_totalSteps',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.5,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        progressLabel,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: AppColors.surfaceContainerHigh,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                      minHeight: 3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _stepTitles[_currentStep],
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // Step content
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.05, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: KeyedSubtree(
                  key: ValueKey(_currentStep),
                  child: _buildCurrentStep(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}