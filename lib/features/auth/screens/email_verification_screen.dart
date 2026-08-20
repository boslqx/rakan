import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';
import '../services/auth_service.dart';
import '../services/auth_navigation_service.dart';
import 'login_screen.dart';

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final AuthService _authService = AuthService();

  bool _isChecking = false;
  bool _isResending = false;
  int _resendCooldown = 0; // seconds remaining before resend is allowed again
  Timer? _cooldownTimer;
  Timer? _autoPollTimer;

  @override
  void initState() {
    super.initState();
    // Silently re-check every 5s
    _autoPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkVerified(silent: true);
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _autoPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkVerified({bool silent = false}) async {
    if (!silent) setState(() => _isChecking = true);

    final verified = await _authService.reloadAndCheckVerified();

    if (!mounted) return;

    if (verified) {
      _autoPollTimer?.cancel();
      final next = await AuthNavigationService().resolveNextScreen();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => next),
        (_) => false,
      );
      return;
    }

    if (!silent) {
      setState(() => _isChecking = false);
      _showMessage('Not verified yet — check your inbox (and spam folder).');
    }
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0 || _isResending) return;

    setState(() => _isResending = true);
    try {
      await _authService.resendVerificationEmail();
      if (!mounted) return;
      _showMessage('Verification email sent.');
      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _startCooldown() {
    setState(() => _resendCooldown = 60);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) timer.cancel();
      });
    });
  }

  Future<void> _signOutAndReturnToLogin() async {
    await _authService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.manrope()),
        backgroundColor:
            isError ? AppColors.error : AppColors.surfaceContainerHigh,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'your email';

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceContainerLow,
                ),
                child: const Icon(
                  Icons.mark_email_unread_outlined,
                  color: AppColors.primary,
                  size: 40,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'VERIFY YOUR EMAIL',
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "We've sent a verification link to\n$email",
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: AppColors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 40),

              ElevatedButton(
                onPressed: _isChecking ? null : () => _checkVerified(),
                child: _isChecking
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : Text(
                        "I'VE VERIFIED — CONTINUE",
                        style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
              ),
              const SizedBox(height: 16),

              TextButton(
                onPressed: (_resendCooldown > 0 || _isResending)
                    ? null
                    : _resend,
                child: Text(
                  _resendCooldown > 0
                      ? 'Resend available in ${_resendCooldown}s'
                      : (_isResending ? 'Sending...' : 'Resend email'),
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: (_resendCooldown > 0 || _isResending)
                        ? AppColors.onSurfaceVariant
                        : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              GestureDetector(
                onTap: _signOutAndReturnToLogin,
                child: Text(
                  'Wrong email? Sign out and try again',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant.withOpacity(0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}