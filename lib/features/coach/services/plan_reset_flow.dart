import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_colors.dart';
import '../../onboarding/models/onboarding_data.dart';
import '../../onboarding/screens/onboarding_shell.dart';
import '../../onboarding/screens/plan_generation_screen.dart';

/// Shared "reset/regenerate workout plan" flow: confirm, let the user
/// choose whether to keep their existing goals or walk onboarding again,
/// then rebuild the plan from the saved profile. Used from both the Coach
/// tab's "Protocol Reset" button and Settings' "Update Fitness Goals"
/// entry — both need to do exactly the same thing.
class PlanResetFlow {
  PlanResetFlow._();

  static Future<void> start(BuildContext context) async {
    final confirm = await _showResetConfirmation(context);
    if (confirm != true || !context.mounted) return;

    final keepGoals = await _showRegenerateChoiceSheet(context);
    if (keepGoals == null || !context.mounted) return;

    await _resetPlan(context, keepGoals: keepGoals);
  }

  static Future<bool?> _showResetConfirmation(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reset Workout Plan?',
            style: GoogleFonts.spaceGrotesk(
                color: AppColors.onSurface, fontWeight: FontWeight.w600)),
        content: Text(
            'Your current plan and all adaptations will be removed. A new plan will be generated.',
            style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: GoogleFonts.manrope(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Reset',
                style: GoogleFonts.manrope(
                    color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// true = regenerate with the existing profile as-is (same goal,
  /// equipment, schedule — just a fresh exercise selection, since the
  /// backend shuffles its exercise pool on every call). false = walk the
  /// onboarding wizard again, pre-filled, so the user can actually change
  /// something. null = dismissed without choosing.
  static Future<bool?> _showRegenerateChoiceSheet(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NEW PLAN',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'How should Rakan build it?',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 20),
              _buildOption(
                icon: Icons.refresh_rounded,
                title: 'Keep My Goals',
                subtitle:
                    'Same goal, equipment, and schedule — just a fresh set of exercises.',
                onTap: () => Navigator.of(ctx).pop(true),
              ),
              const SizedBox(height: 12),
              _buildOption(
                icon: Icons.edit_note_rounded,
                title: 'Update My Goals',
                subtitle:
                    'Walk through your training profile again to change anything.',
                onTap: () => Navigator.of(ctx).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  static Future<void> _resetPlan(
    BuildContext context, {
    required bool keepGoals,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final db = FirebaseFirestore.instance;
    try {
      // Mark all active plans as inactive
      final plansSnap = await db
          .collection('users')
          .doc(uid)
          .collection('workoutPlans')
          .get();

      for (final doc in plansSnap.docs) {
        if (doc.data()['status'] == 'active') {
          await doc.reference.update({'status': 'inactive'});
        }
      }

      // Rebuild from the already-saved profile instead of starting blank
      // — a bare OnboardingData() here would send empty
      // equipment/workout_days/focus_areas to the backend and silently
      // produce a plan with zero workout days.
      final profileSnap = await db
          .collection('users')
          .doc(uid)
          .collection('profile')
          .doc('data')
          .get();
      final data = OnboardingData.fromMap(profileSnap.data() ?? {});

      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => keepGoals
              ? PlanGenerationScreen(data: data)
              : OnboardingShell(initialData: data),
        ),
      );
    } catch (e) {
      debugPrint('Reset plan error: $e');
    }
  }
}
