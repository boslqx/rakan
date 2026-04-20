import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../models/onboarding_data.dart';
import 'steps/step1_profile.dart';
import 'steps/step2_goal.dart';
import 'steps/step3_experience.dart';
import 'steps/step4_preference.dart';
import 'steps/step5_environment.dart';
import 'steps/step6_safety.dart';

class OnboardingShell extends StatefulWidget {
  const OnboardingShell({super.key});

  @override
  State<OnboardingShell> createState() => _OnboardingShellState();
}

class _OnboardingShellState extends State<OnboardingShell> {
  // The single OnboardingData object here passed to each step
  final OnboardingData _data = OnboardingData();

  // Steps that we are currently on
  int _currentStep = 0;

  // Total number of steps
  static const int _totalSteps = 6;

  // Step titles shown on the progress header
  static const List<String> _stepTitles = [
    'Personal Profile',
    'Primary Focus',
    'Workout Experience',
    'Workout Preference',
    'Training Resources',
    'Safety Profile',
  ];

  // Move to next step
  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
    } else {
      _finishOnboarding();
    }
  }

  // Move to previous step
  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    } else {
      // On step 0, back goes to splash
      Navigator.of(context).pop();
    }
  }

  // Called when user taps FINISH ONBOARDING
  void _finishOnboarding() {
    // Debug: print collected data to console
    // You'll see this in your VSCode terminal
    debugPrint(_data.toString());

    // TO BE CONTINUED
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Onboarding complete! Data collected.',
          style: GoogleFonts.manrope(),
        ),
        backgroundColor: AppColors.surfaceContainerHigh,
      ),
    );
  }

  // Returns the correct step widget for the current step index
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
        return Step6Safety(data: _data, onNext: _nextStep);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Progress as a value between 0.0 and 1.0
    final double progress = (_currentStep + 1) / _totalSteps;

    // Percentage string shown on the right
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
                  // Back button
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

                  // App name
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

                  // Spacer to balance the back button
                  const SizedBox(width: 40),
                ],
              ),
            ),

            // Progress section
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step label + percentage
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

                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: AppColors.surfaceContainerHigh,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primary,
                        ),
                        minHeight: 3,
                      ),
                    ),
                  ),

                  const SizedBox(height: 4),

                  // Step title
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

            // Expanded makes the step fill all remaining space
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) {
                  // Slide + fade transition between steps
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.05, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                  );
                },
                // Key tells AnimatedSwitcher that the child changed
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