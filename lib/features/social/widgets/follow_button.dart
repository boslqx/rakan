import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';
import '../services/follow_service.dart';

/// Follow/unfollow/request button — shared by FindUsersScreen's result
/// rows, UserProfileScreen's header, and FollowersFollowingScreen's rows.
/// Loads its own status and manages the follow/unfollow round-trip so
/// callers just drop it in with a target uid.
class FollowButton extends StatefulWidget {
  final String targetUid;

  /// Small pill for list rows vs a full-width button on the profile screen.
  final bool compact;

  /// Called after a successful follow/unfollow/cancel so the parent (e.g.
  /// follower counts on a profile screen) can refresh.
  final VoidCallback? onChanged;

  const FollowButton({
    super.key,
    required this.targetUid,
    this.compact = true,
    this.onChanged,
  });

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  final _followService = FollowService();
  FollowStatus? _status;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final viewerUid = FirebaseAuth.instance.currentUser?.uid;
    if (viewerUid == null) return;
    final status = await _followService.getFollowStatus(
      viewerUid: viewerUid,
      targetUid: widget.targetUid,
    );
    if (mounted) setState(() => _status = status);
  }

  Future<void> _handleTap() async {
    final viewerUid = FirebaseAuth.instance.currentUser?.uid;
    if (viewerUid == null || _status == null || _isBusy) return;

    setState(() => _isBusy = true);
    try {
      switch (_status!) {
        case FollowStatus.none:
          await _followService.followUser(followerUid: viewerUid, followingUid: widget.targetUid);
        case FollowStatus.pending:
        case FollowStatus.accepted:
          await _followService.removeFollow(followerUid: viewerUid, followingUid: widget.targetUid);
        case FollowStatus.self:
          break;
      }
      await _loadStatus();
      widget.onChanged?.call();
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_status == null || _status == FollowStatus.self) {
      return const SizedBox.shrink();
    }

    final (label, filled) = switch (_status!) {
      FollowStatus.none => ('FOLLOW', true),
      FollowStatus.pending => ('REQUESTED', false),
      FollowStatus.accepted => ('FOLLOWING', false),
      FollowStatus.self => ('', false),
    };

    final child = _isBusy
        ? SizedBox(
            width: widget.compact ? 12 : 18,
            height: widget.compact ? 12 : 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: filled ? AppColors.onPrimary : AppColors.onSurface,
            ),
          )
        : Text(
            label,
            style: GoogleFonts.spaceGrotesk(
              fontSize: widget.compact ? 11 : 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: filled ? AppColors.onPrimary : AppColors.onSurface,
            ),
          );

    return GestureDetector(
      onTap: _isBusy ? null : _handleTap,
      child: Container(
        width: widget.compact ? null : double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 14 : 20,
          vertical: widget.compact ? 8 : 14,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? AppColors.primary : AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(widget.compact ? 48 : 14),
          border: filled ? null : Border.all(color: AppColors.outlineVariant),
        ),
        child: child,
      ),
    );
  }
}
