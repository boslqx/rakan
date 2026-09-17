import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/main_shell.dart';
import '../services/public_profile_service.dart';

enum _Status { idle, checking, available, taken, invalid }

/// One-time gate for accounts created before the social feature shipped —
/// same claim flow as Step1Profile's username field, just standalone since
/// these users have already finished onboarding. Shown by
/// AuthNavigationService whenever a completed profile has no username yet.
class ChooseUsernameScreen extends StatefulWidget {
  const ChooseUsernameScreen({super.key});

  @override
  State<ChooseUsernameScreen> createState() => _ChooseUsernameScreenState();
}

class _ChooseUsernameScreenState extends State<ChooseUsernameScreen> {
  final _controller = TextEditingController();
  final _service = PublicProfileService();

  _Status _status = _Status.idle;
  Timer? _debounce;
  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();

    final formatError = PublicProfileService.validateUsernameFormat(value);
    if (formatError != null) {
      setState(() => _status = _Status.invalid);
      return;
    }

    setState(() => _status = _Status.checking);
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final available = await _service.isUsernameAvailable(value);
        if (!mounted || _controller.text != value) return;
        setState(() => _status = available ? _Status.available : _Status.taken);
      } catch (e) {
        debugPrint('ChooseUsernameScreen: availability check failed: $e');
        if (!mounted || _controller.text != value) return;
        setState(() => _status = _Status.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not check availability: $e',
                style: GoogleFonts.manrope()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    });
  }

  Future<void> _claim() async {
    final username = _controller.text.trim();
    final formatError = PublicProfileService.validateUsernameFormat(username);
    if (formatError != null || _status == _Status.taken) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(formatError ?? 'That username is taken',
              style: GoogleFonts.manrope()),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    final uid = FirebaseAuth.instance.currentUser!.uid;
    try {
      await _service.claimUsername(uid: uid, username: username);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell()),
        (_) => false,
      );
    } catch (e) {
      debugPrint('ChooseUsernameScreen: claim failed: $e');
      if (!mounted) return;
      final isTaken = e is StateError;
      setState(() {
        _isSaving = false;
        _status = isTaken ? _Status.taken : _Status.idle;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              isTaken ? 'That username is taken' : 'Could not save username: $e',
              style: GoogleFonts.manrope()),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = switch (_status) {
      _Status.taken || _Status.invalid => AppColors.error,
      _Status.available => AppColors.primary,
      _ => AppColors.outlineVariant,
    };

    Widget? suffixIcon;
    switch (_status) {
      case _Status.checking:
        suffixIcon = const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case _Status.available:
        suffixIcon = const Icon(Icons.check_circle_rounded, color: AppColors.primary);
      case _Status.taken:
      case _Status.invalid:
        suffixIcon = const Icon(Icons.error_rounded, color: AppColors.error);
      case _Status.idle:
        suffixIcon = null;
    }

    final (hintText, hintColor) = switch (_status) {
      _Status.taken => ('That username is already taken', AppColors.error),
      _Status.invalid => ('3-20 characters: letters, numbers, underscore only', AppColors.error),
      _Status.available => ('Available', AppColors.primary),
      _ => ('Used for other people to find and follow you.', AppColors.onSurfaceVariant),
    };

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CHOOSE A\nUSERNAME',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Rakan now supports following other athletes — pick a handle so people can find you.",
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: AppColors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 1),
                ),
                child: TextField(
                  controller: _controller,
                  onChanged: _onChanged,
                  autofocus: true,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                    LengthLimitingTextInputFormatter(20),
                  ],
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 18,
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'yourname',
                    prefixText: '@',
                    prefixStyle: GoogleFonts.spaceGrotesk(
                      fontSize: 18,
                      color: AppColors.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                    hintStyle: GoogleFonts.spaceGrotesk(
                      fontSize: 18,
                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    suffixIcon: suffixIcon,
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(hintText, style: GoogleFonts.manrope(fontSize: 12, color: hintColor)),
              const Spacer(),
              ElevatedButton(
                onPressed: _isSaving ? null : _claim,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                      )
                    : Text(
                        'CONTINUE',
                        style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, letterSpacing: 1.5),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
