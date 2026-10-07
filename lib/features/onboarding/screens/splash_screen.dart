import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/screens/login_screen.dart';
import '../../auth/screens/register_screen.dart';
import '../../auth/services/auth_navigation_service.dart';
import '../../../shared/widgets/pressable.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _isCheckingAuth = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _checkAuthAndRoute();
  }

    Future<void> _checkAuthAndRoute() async {
      // Wait for Firebase to restore persisted session.
      final user = await FirebaseAuth.instance.authStateChanges().first;

      if (!mounted) return;

      if (user == null) {
        // Not logged in → show splash UI
        setState(() => _isCheckingAuth = false);
        return;
      }

      // Logged in → let the centralized navigation service decide.
      // This reads Firestore; if it fails (no connection, a timeout) show a
      // retry instead of leaving the user on an endless spinner.
      try {
        final next = await AuthNavigationService()
            .resolveNextScreen()
            .timeout(const Duration(seconds: 20));
        if (!mounted) return;

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => next),
        );
      } catch (e) {
        debugPrint('Startup routing failed: $e');
        if (!mounted) return;
        setState(() => _loadFailed = true);
      }
    }

  void _retry() {
    setState(() => _loadFailed = false);
    _checkAuthAndRoute();
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingAuth && _loadFailed) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_rounded,
                      color: AppColors.onSurfaceVariant, size: 40),
                  const SizedBox(height: 16),
                  Text(
                    "Couldn't load your account",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Check your internet connection and try again.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _retry,
                    child: const Text('TRY AGAIN'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Show minimal spinner while checking auth
    if (_isCheckingAuth) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: const Center(
          child: CircularProgressIndicator(
            color: AppColors.primary,
            strokeWidth: 1.5,
          ),
        ),
      );
    }

    // Auth check done — no logged in user — show splash UI
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/welcome_bg.jpg',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.surface.withValues(alpha: 0.6),
                    AppColors.surface.withValues(alpha: 0.95),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
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
                  const Spacer(),
                  Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surfaceContainerLow,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          blurRadius: 60,
                          spreadRadius: 20,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/images/transparent_bg.png',
                        width: 200,
                        height: 200,
                      ),
                    ),
                  ),
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
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    ),
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
                      Pressable(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                        ),
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
        ],
      ),
    );
  }
}
