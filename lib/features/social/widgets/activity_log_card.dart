import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';

/// Renders a single completed-workout card — shared by Home's own activity
/// feed (full `workoutLogs` data, tappable into WorkoutLogDetailScreen) and
/// a followed user's profile feed (thin `activityFeed` copy, no tap target).
/// Missing fields (volume, PR badge, photo — all deliberately absent from
/// the follower-visible copy) degrade gracefully rather than erroring.
class ActivityLogCard extends StatelessWidget {
  final Map<String, dynamic> log;
  final VoidCallback? onTap;

  const ActivityLogCard({super.key, required this.log, this.onTap});

  @override
  Widget build(BuildContext context) {
    final workoutName = log['workoutName'] as String? ?? 'Workout';
    final completedAt = log['completedAt'] as String? ?? '';
    final totalVolume = (log['totalVolume'] as num?)?.toDouble() ?? 0;
    final durationMins = log['totalDurationMins'] as int? ?? 0;
    final totalSets = log['totalSetsCompleted'] as int?;
    final prReached = log['prReached'] as bool? ?? false;
    final photoBase64 = log['progressPhotoBase64'] as String?;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: icon + title + date/time
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.fitness_center_rounded,
                      color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        workoutName,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _dateTimeLabel(completedAt).toUpperCase(),
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Stats row
            Row(
              children: [
                Expanded(child: _buildLogStat('VOLUME', _formatVolume(totalVolume))),
                Expanded(child: _buildLogStat('TIME', '${durationMins}m')),
                Expanded(
                  child: _buildLogStat('SETS', totalSets != null ? '$totalSets' : '—'),
                ),
              ],
            ),

            if (prReached) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.emoji_events_rounded,
                            size: 13, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text('PR REACHED',
                            style: GoogleFonts.manrope(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: AppColors.primary,
                            )),
                      ],
                    ),
                  ),
                ],
              ),
            ],

            if (photoBase64 != null && photoBase64.isNotEmpty) ...[
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  base64Decode(photoBase64),
                  width: double.infinity,
                  height: 160,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLogStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurface,
          ),
        ),
      ],
    );
  }

  String _formatVolume(double kg) {
    if (kg <= 0) return '—';
    if (kg >= 1000) return '${(kg / 1000).toStringAsFixed(1)}k kg';
    return '${kg.toStringAsFixed(0)} kg';
  }

  /// Relative day label
  String _dateTimeLabel(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final diff = DateTime.now().difference(date);
      final String dayLabel;
      if (diff.inDays == 0) {
        dayLabel = 'Today';
      } else if (diff.inDays == 1) {
        dayLabel = 'Yesterday';
      } else {
        dayLabel = '${diff.inDays} days ago';
      }
      final hour24 = date.hour;
      final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
      final minute = date.minute.toString().padLeft(2, '0');
      final meridiem = hour24 < 12 ? 'AM' : 'PM';
      return '$dayLabel • ${hour12.toString().padLeft(2, '0')}:$minute $meridiem';
    } catch (_) {
      return '';
    }
  }
}
