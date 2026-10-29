import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/validators.dart';

/// Live password-strength checklist. Shared by sign-up and Change Password
/// so both enforce (and show) the same rules from
/// `Validators.passwordRequirements`.
class PasswordChecklist extends StatelessWidget {
  final String password;
  const PasswordChecklist({super.key, required this.password});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: Validators.passwordRequirements.map((req) {
        final met = req.test(password);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(
                met ? Icons.check_circle : Icons.circle_outlined,
                size: 14,
                color: met ? AppColors.primary : AppColors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                req.label,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: met ? AppColors.onSurface : AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
