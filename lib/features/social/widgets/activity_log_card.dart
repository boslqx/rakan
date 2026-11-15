import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/utils/workout_stats_format.dart';
import '../../../shared/widgets/progress_photo.dart';
import '../../../shared/widgets/user_avatar.dart';
import 'activity_actions_row.dart';
import '../../../shared/widgets/pressable.dart';

/// Renders a single completed-workout card — shared by Home's own activity
/// feed (full `workoutLogs` data, tappable into WorkoutLogDetailScreen), a
/// user's profile feed and Home's following feed (both the thin
/// `activityFeed` copy). Missing fields degrade gracefully rather than
/// erroring: the photo (on a feed copy only when its owner shared it),
/// caption, or volume on copies saved before it was included.
class ActivityLogCard extends StatelessWidget {
  final Map<String, dynamic> log;
  final VoidCallback? onTap;

  /// The workout's author — shown as the card's avatar instead of the
  /// generic dumbbell icon when provided (e.g. on a profile screen, or
  /// Home's own feed once the viewer's own photo is known).
  final String? authorName;
  final String? authorPhotoBase64;

  /// Whoever's `activityFeed` this session belongs to — required for the
  /// like/comment/share row, which targets
  /// `users/{ownerUid}/activityFeed/{log['logId']}`. Omit only in contexts
  /// that genuinely have no owner uid; the actions row is skipped then.
  final String? ownerUid;

  /// Social-feed layout: the header names the author (with @username when
  /// known) and the workout name moves below it — used where cards from
  /// several people are mixed. Requires [authorName].
  final bool showAuthorHeader;
  final String? authorUsername;

  /// Tapping the author's avatar/name, e.g. to open their profile.
  final VoidCallback? onAuthorTap;

  const ActivityLogCard({
    super.key,
    required this.log,
    this.onTap,
    this.authorName,
    this.authorPhotoBase64,
    this.ownerUid,
    this.showAuthorHeader = false,
    this.authorUsername,
    this.onAuthorTap,
  });

  @override
  Widget build(BuildContext context) {
    final workoutName = log['workoutName'] as String? ?? 'Workout';
    final completedAt = log['completedAt'] as String? ?? '';
    final totalSets = (log['totalSetsCompleted'] as num?)?.toInt();
    final prReached = log['prReached'] as bool? ?? false;
    final logId = log['logId'] as String?;
    final caption = (log['caption'] as String? ?? '').trim();

    return Pressable(
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
            if (showAuthorHeader && authorName != null) ...[
              _buildAuthorHeader(completedAt),
              const SizedBox(height: 14),
              Text(
                workoutName,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
            ] else
              _buildWorkoutHeader(workoutName, completedAt),
            if (caption.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                caption,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  height: 1.45,
                  color: AppColors.onSurface,
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Stats row
            Row(
              children: [
                Expanded(child: _buildLogStat('KG LIFTED', formatLogVolume(log))),
                Expanded(child: _buildLogStat('TIME', formatLogDuration(log))),
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

            if (ProgressPhoto.hasPhoto(log)) ...[
              const SizedBox(height: 20),
              ProgressPhoto(
                log: log,
                ownerUid: ownerUid,
                // Bigger where the photo is the post (the following feed).
                height: showAuthorHeader ? 220 : 160,
              ),
            ],

            if (ownerUid != null && logId != null)
              ActivityActionsRow(ownerUid: ownerUid!, logId: logId, log: log),
          ],
        ),
      ),
    );
  }

  /// Avatar (or fallback icon) + workout name + date/time.
  Widget _buildWorkoutHeader(String workoutName, String completedAt) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        authorName != null
            ? UserAvatar(
                photoBase64: authorPhotoBase64,
                initialsSource: authorName!,
                size: 40,
              )
            : Container(
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
    );
  }

  /// Avatar + author name + "@username · date/time", tappable as one
  /// target ([onAuthorTap]).
  Widget _buildAuthorHeader(String completedAt) {
    final when = _dateTimeLabel(completedAt);
    final meta = [
      if (authorUsername != null && authorUsername!.isNotEmpty) '@$authorUsername',
      if (when.isNotEmpty) when.toUpperCase(),
    ].join(' · ');

    return GestureDetector(
      onTap: onAuthorTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          UserAvatar(
            photoBase64: authorPhotoBase64,
            initialsSource: authorName!,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  authorName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
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
