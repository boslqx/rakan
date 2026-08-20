import 'package:flutter/widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';
import '../screens/email_verification_screen.dart';
import '../screens/login_screen.dart';
import '../../onboarding/screens/onboarding_shell.dart';
import '../../onboarding/services/user_profile_service.dart';
import '../../../shared/widgets/main_shell.dart';


class AuthNavigationService {
  final AuthService _authService = AuthService();
  final UserProfileService _profileService = UserProfileService();

  Future<Widget> resolveNextScreen() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const LoginScreen();
    }

    final verified = await _authService.reloadAndCheckVerified();
    if (!verified) {
      return const EmailVerificationScreen();
    }

    final hasProfile = await _profileService.hasCompletedOnboarding(user.uid);
    return hasProfile ? const MainShell() : const OnboardingShell();
  }
}