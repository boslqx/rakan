import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';

/// Shown once, on Home screen load
class PlanChangesDialog extends StatelessWidget {
  final List<dynamic> changes;
  final String? trend;

  const PlanChangesDialog({super.key, required this.changes, this.trend});

  static const Map<String, String> _tierLabels = {
    'high': 'Reduced',
    'medium': 'Maintained',
    'low': 'Increased',
    'session_priority': 'Adjusted',
    'deload': 'Deload',
  };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_graph_rounded, color: AppColors.primary, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'YOUR PLAN UPDATED',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Based on last week\'s sessions, here\'s what changed:',
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            ...changes.map((c) => _changeRow(c as Map<String, dynamic>)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  'GOT IT',
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _changeRow(Map<String, dynamic> change) {
    final muscleGroup = change['muscleGroup'] as String? ?? '';
    final tier = change['tier'] as String? ?? '';
    final reason = change['reason'] as String? ?? '';
    final adjustment = (change['adjustment'] as num?)?.toDouble() ?? 0.0;
    final pct = (adjustment * 100).round();
    final label = _tierLabels[tier] ?? 'Adjusted';
    final isIncrease = adjustment > 0;
    final isDecrease = adjustment < 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  muscleGroup,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              Icon(
                isIncrease
                    ? Icons.trending_up_rounded
                    : isDecrease
                        ? Icons.trending_down_rounded
                        : Icons.trending_flat_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 4),
              Text(
                '$label ${pct != 0 ? '${pct > 0 ? '+' : ''}$pct%' : ''}',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              reason,
              style: GoogleFonts.manrope(
                fontSize: 12,
                color: AppColors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}