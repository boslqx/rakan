import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';
import '../../workout/services/weekly_summary_service.dart';

/// Third Records subsection, alongside Body Journey and Workout Records
class PlanChangesSection extends StatefulWidget {
  const PlanChangesSection({super.key});

  @override
  State<PlanChangesSection> createState() => _PlanChangesSectionState();
}

class _PlanChangesSectionState extends State<PlanChangesSection> {
  final _service = WeeklySummaryService();
  late Future<List<Map<String, dynamic>>> _historyFuture;

  static const Map<String, String> _tierLabels = {
    'high': 'Reduced',
    'medium': 'Maintained',
    'low': 'Increased',
    'session_priority': 'Adjusted',
    'deload': 'Deload',
  };

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _historyFuture = uid == null
        ? Future.value(<Map<String, dynamic>>[])
        : _service.getChangeHistory(uid);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _historyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final weeks = snapshot.data ?? [];
        if (weeks.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
            child: Center(
              child: Text(
                'No plan changes yet.\nThey\'ll show up here after your first\nfull week of logged workouts.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < weeks.length; i++) ...[
              _weekCard(weeks[i]),
              if (i != weeks.length - 1) const SizedBox(height: 16),
            ],
          ],
        );
      },
    );
  }

  Widget _weekCard(Map<String, dynamic> week) {
    final changes = week['changes'] as List<dynamic>? ?? [];
    final weekStart = DateTime.tryParse(week['weekStart'] as String? ?? '');
    final weekEnd = DateTime.tryParse(week['weekEnd'] as String? ?? '');
    final dateLabel = (weekStart != null && weekEnd != null)
        ? '${_fmt(weekStart)} – ${_fmt(weekEnd)}'
        : '';
    final isDeload = week['isDeloadWeek'] as bool? ?? false;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                dateLabel,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              if (isDeload) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'DELOAD WEEK',
                    style: GoogleFonts.manrope(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          for (final c in changes) _changeLine(c as Map<String, dynamic>),
        ],
      ),
    );
  }

  Widget _changeLine(Map<String, dynamic> change) {
    final muscleGroup = change['muscleGroup'] as String? ?? '';
    final tier = change['tier'] as String? ?? '';
    final adjustment = (change['adjustment'] as num?)?.toDouble() ?? 0.0;
    final pct = (adjustment * 100).round();
    final label = _tierLabels[tier] ?? 'Adjusted';
    final isIncrease = adjustment > 0;
    final isDecrease = adjustment < 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            isIncrease
                ? Icons.trending_up_rounded
                : isDecrease
                    ? Icons.trending_down_rounded
                    : Icons.trending_flat_rounded,
            size: 15,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              muscleGroup,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
          ),
          Text(
            '$label${pct != 0 ? ' ${pct > 0 ? '+' : ''}$pct%' : ''}',
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}';
}