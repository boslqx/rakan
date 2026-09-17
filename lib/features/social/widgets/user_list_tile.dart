import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/user_avatar.dart';

/// A single row for a user list — search results, followers, following,
/// pending requests. [profile] is a `users/{uid}` public-doc map (must
/// include `uid`); [trailing] is the row's action (FollowButton, or
/// Accept/Decline for a request).
class UserListTile extends StatelessWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onTap;
  final Widget? trailing;

  const UserListTile({
    super.key,
    required this.profile,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = profile['displayName'] as String? ?? 'Athlete';
    final username = profile['username'] as String?;
    final photoBase64 = profile['photoBase64'] as String?;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              UserAvatar(
                photoBase64: photoBase64,
                initialsSource: displayName,
                size: 44,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (username != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@$username',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: AppColors.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
