import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';

/// Shown once, on Home screen load
class PlanChangesDialog extends StatelessWidget {
  final List<dynamic> changes;
  final String? trend;
  final int? sessionsCompleted;
  final double? avgRpe;
  final double? totalVolume;

  const PlanChangesDialog({
    super.key,
    required this.changes,
    this.trend,
    this.sessionsCompleted,
    this.avgRpe,
    this.totalVolume,
  });

  static const Map<String, String> _tierLabels = {
    'high': 'Reduced',
    'medium': 'Maintained',
    'low': 'Increased',
    'session_priority': 'Adjusted',
    'deload': 'Deload',
  };

  // Same 0.7/0.4 fatigueScore thresholds as the Coach screen's recovery
  // heatmap, so "Low/Moderate/High fatigue" means the same thing everywhere.
  static const double _highFatigueThreshold = 0.7;
  static const double _lowFatigueThreshold = 0.4;
  static const Color _moderateFatigueColor = Color(0xFFE8A87C);

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
                    changes.isEmpty ? 'YOUR WEEK IN REVIEW' : 'YOUR PLAN UPDATED',
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
              changes.isEmpty
                  ? 'Here\'s a quick look back at last week — no plan adjustments were needed.'
                  : 'Based on last week\'s sessions, here\'s what changed:',
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (_hasProgressStats) ...[
              _progressStatsRow(),
              const SizedBox(height: 20),
            ],
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

  bool get _hasProgressStats =>
      sessionsCompleted != null || avgRpe != null || totalVolume != null;

  Widget _progressStatsRow() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _statTile(
              'SESSIONS',
              sessionsCompleted != null ? '$sessionsCompleted' : '—',
            ),
          ),
          Expanded(
            child: _statTile(
              'AVG RPE',
              avgRpe != null ? avgRpe!.toStringAsFixed(1) : '—',
            ),
          ),
          Expanded(
            child: _statTile('VOLUME', _formatVolume(totalVolume)),
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  String _formatVolume(double? kg) {
    if (kg == null || kg <= 0) return '—';
    if (kg >= 1000) return '${(kg / 1000).toStringAsFixed(1)}k kg';
    return '${kg.toStringAsFixed(0)} kg';
  }

  /// Same 0.7/0.4 fatigueScore split as the Coach screen's recovery heatmap.
  (String, Color) _recoveryLabelAndColor(double fatigueScore) {
    if (fatigueScore >= _highFatigueThreshold) {
      return ('Low recovery', AppColors.error);
    }
    if (fatigueScore < _lowFatigueThreshold) {
      return ('Well recovered', AppColors.primary);
    }
    return ('Recovering', _moderateFatigueColor);
  }

  Widget _changeRow(Map<String, dynamic> change) {
    final muscleGroup = change['muscleGroup'] as String? ?? '';
    final tier = change['tier'] as String? ?? '';
    final reason = change['reason'] as String? ?? '';
    final adjustment = (change['adjustment'] as num?)?.toDouble() ?? 0.0;
    final recoveryScore = (change['recoveryScore'] as num?)?.toDouble();
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
          if (recoveryScore != null) ...[
            const SizedBox(height: 8),
            _recoveryChip(recoveryScore),
          ],
        ],
      ),
    );
  }

  Widget _recoveryChip(double recoveryScore) {
    final (recoveryLabel, recoveryColor) =
        _recoveryLabelAndColor(recoveryScore);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: recoveryColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          recoveryLabel,
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: recoveryColor,
          ),
        ),
      ],
    );
  }
}