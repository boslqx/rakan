import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../core/theme/app_colors.dart';
import '../../auth/services/auth_service.dart';
import '../../auth/screens/login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    // Show confirmation dialog — prevent accidental logout
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Log Out',
          style: GoogleFonts.spaceGrotesk(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Are you sure you want to log out?',
          style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Log Out',
              style: GoogleFonts.manrope(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await AuthService().signOut();

    // Clear entire nav stack and go to LoginScreen
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Read current user info from Firebase Auth
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              child: Text(
                'SETTINGS',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  letterSpacing: 2,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // User info card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    // Avatar circle
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surfaceContainerHigh,
                      ),
                      child: Center(
                        child: Text(
                          // Show first letter of email as avatar
                          (user?.email ?? 'R')[0].toUpperCase(),
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.displayName ?? 'Rakan Athlete',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user?.email ?? '',
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Settings items
            _SettingsTile(
              icon: Icons.lock_outline_rounded,
              label: 'Change Password',
              onTap: () {}, // placeholder for now
            ),
            _SettingsTile(
              icon: Icons.notifications_outlined,
              label: 'Notifications',
              onTap: () {},
            ),
            _SettingsTile(
              icon: Icons.info_outline_rounded,
              label: 'About Rakan',
              onTap: () {},
            ),

            const Spacer(),

            // Logout button at bottom
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: GestureDetector(
                onTap: () => _logout(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(48),
                    border: Border.all(
                      color: AppColors.error.withOpacity(0.3),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'LOG OUT',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Reusable settings row tile
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.onSurfaceVariant, size: 20),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}