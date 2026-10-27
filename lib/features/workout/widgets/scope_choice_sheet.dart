import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/pressable.dart';

/// Asks whether a change goes into the plan for good or applies to one
/// date only — when adding an exercise, or swapping two days. Resolves to
/// true for the plan, false for this time only, null if dismissed.
///
/// [oneTimeUnavailable], when set, says why "this time only" can't apply
/// (e.g. the day already passed); the option is shown disabled with that
/// reason rather than hidden, so it's clear why only the plan is offered.
Future<bool?> showScopeChoiceSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  Widget? leading,
  required String planTitle,
  required String planDescription,
  required String oneTimeTitle,
  required String oneTimeDescription,
  String? oneTimeUnavailable,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.surfaceContainerLow,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(sheetContext).viewPadding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              if (leading != null) ...[leading, const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface, height: 1.15)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: GoogleFonts.manrope(fontSize: 13, color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _ScopeOption(
            icon: Icons.event_repeat_rounded,
            title: planTitle,
            description: planDescription,
            highlighted: true,
            onTap: () => Navigator.pop(sheetContext, true),
          ),
          const SizedBox(height: 10),
          _ScopeOption(
            icon: Icons.bolt_rounded,
            title: oneTimeTitle,
            description: oneTimeUnavailable ?? oneTimeDescription,
            onTap: oneTimeUnavailable == null ? () => Navigator.pop(sheetContext, false) : null,
          ),
        ],
      ),
    ),
  );
}

class _ScopeOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool highlighted;

  /// Null shows the option disabled.
  final VoidCallback? onTap;

  const _ScopeOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: highlighted ? AppColors.primary.withValues(alpha: 0.12) : AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: highlighted ? AppColors.primary.withValues(alpha: 0.5) : Colors.transparent),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: highlighted ? AppColors.primary : AppColors.onSurface),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: highlighted ? AppColors.primary : AppColors.onSurface)),
                    const SizedBox(height: 2),
                    Text(description,
                        style: GoogleFonts.manrope(fontSize: 12, color: AppColors.onSurfaceVariant, height: 1.3)),
                  ],
                ),
              ),
              if (onTap != null) const Icon(Icons.chevron_right_rounded, color: AppColors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
