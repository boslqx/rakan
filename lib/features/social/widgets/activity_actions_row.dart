import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../services/activity_interaction_service.dart';

/// Like/comment/share row appended below an ActivityLogCard. Owns its own
/// like/comment-count state so the card itself stays a simple, stateless
/// renderer — same self-contained pattern as FollowButton.
class ActivityActionsRow extends StatefulWidget {
  final String ownerUid;
  final String logId;
  final Map<String, dynamic> log;

  const ActivityActionsRow({
    super.key,
    required this.ownerUid,
    required this.logId,
    required this.log,
  });

  @override
  State<ActivityActionsRow> createState() => _ActivityActionsRowState();
}

class _ActivityActionsRowState extends State<ActivityActionsRow> {
  final _service = ActivityInteractionService();

  bool _hasLiked = false;
  int _likeCount = 0;
  int _commentCount = 0;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final viewerUid = FirebaseAuth.instance.currentUser?.uid;
    if (viewerUid == null) return;

    final results = await Future.wait([
      _service.hasLiked(ownerUid: widget.ownerUid, logId: widget.logId, viewerUid: viewerUid),
      _service.getLikeCount(ownerUid: widget.ownerUid, logId: widget.logId),
      _service.getCommentCount(ownerUid: widget.ownerUid, logId: widget.logId),
    ]);

    if (!mounted) return;
    setState(() {
      _hasLiked = results[0] as bool;
      _likeCount = results[1] as int;
      _commentCount = results[2] as int;
      _isLoaded = true;
    });
  }

  Future<void> _toggleLike() async {
    final viewerUid = FirebaseAuth.instance.currentUser?.uid;
    if (viewerUid == null) return;

    // Optimistic update — feels instant, corrected below if the write fails.
    setState(() {
      _hasLiked = !_hasLiked;
      _likeCount += _hasLiked ? 1 : -1;
    });

    try {
      await _service.toggleLike(ownerUid: widget.ownerUid, logId: widget.logId, viewerUid: viewerUid);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasLiked = !_hasLiked;
        _likeCount += _hasLiked ? 1 : -1;
      });
    }
  }

  void _openComments() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _CommentsSheet(ownerUid: widget.ownerUid, logId: widget.logId),
    );
    // Comment count may have changed while the sheet was open.
    final count = await _service.getCommentCount(ownerUid: widget.ownerUid, logId: widget.logId);
    if (mounted) setState(() => _commentCount = count);
  }

  void _share() {
    final workoutName = widget.log['workoutName'] as String? ?? 'Workout';
    final durationMins = widget.log['totalDurationMins'] as int? ?? 0;
    final totalSets = widget.log['totalSetsCompleted'] as int?;

    final parts = <String>['Just completed "$workoutName" on Rakan 💪'];
    if (durationMins > 0) parts.add('$durationMins min');
    if (totalSets != null) parts.add('$totalSets sets');

    Share.share(parts.join(' • '));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          _ActionButton(
            icon: _hasLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            iconColor: _hasLiked ? AppColors.error : AppColors.onSurfaceVariant,
            label: _isLoaded && _likeCount > 0 ? '$_likeCount' : '',
            onTap: _isLoaded ? _toggleLike : null,
          ),
          const SizedBox(width: 20),
          _ActionButton(
            icon: Icons.chat_bubble_outline_rounded,
            label: _isLoaded && _commentCount > 0 ? '$_commentCount' : '',
            onTap: _openComments,
          ),
          const Spacer(),
          _ActionButton(icon: Icons.ios_share_rounded, onTap: _share),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final VoidCallback? onTap;

  const _ActionButton({required this.icon, this.iconColor, this.label = '', this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: iconColor ?? AppColors.onSurfaceVariant),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommentsSheet extends StatefulWidget {
  final String ownerUid;
  final String logId;

  const _CommentsSheet({required this.ownerUid, required this.logId});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _service = ActivityInteractionService();
  final _textController = TextEditingController();

  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = true;
  bool _isPosting = false;

  bool get _isOwner => FirebaseAuth.instance.currentUser?.uid == widget.ownerUid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final comments = await _service.getComments(ownerUid: widget.ownerUid, logId: widget.logId);
    if (!mounted) return;
    setState(() {
      _comments = comments;
      _isLoading = false;
    });
  }

  Future<void> _post() async {
    final text = _textController.text.trim();
    final user = FirebaseAuth.instance.currentUser;
    if (text.isEmpty || user == null || _isPosting) return;

    setState(() => _isPosting = true);
    try {
      await _service.addComment(
        ownerUid: widget.ownerUid,
        logId: widget.logId,
        authorUid: user.uid,
        authorName: user.displayName?.isNotEmpty == true ? user.displayName! : 'Athlete',
        text: text,
      );
      _textController.clear();
      await _load();
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _delete(String commentId) async {
    await _service.deleteComment(ownerUid: widget.ownerUid, logId: widget.logId, commentId: commentId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final viewerUid = FirebaseAuth.instance.currentUser?.uid;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'COMMENTS',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 1.5),
                      )
                    : _comments.isEmpty
                        ? Center(
                            child: Text(
                              'No comments yet.',
                              style: GoogleFonts.manrope(fontSize: 13, color: AppColors.onSurfaceVariant),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: _comments.length,
                            itemBuilder: (context, index) {
                              final comment = _comments[index];
                              final authorUid = comment['authorUid'] as String?;
                              final canDelete = viewerUid != null &&
                                  (viewerUid == authorUid || _isOwner);

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    UserAvatar(
                                      photoBase64: comment['authorPhotoBase64'] as String?,
                                      initialsSource: comment['authorName'] as String? ?? 'A',
                                      size: 32,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            comment['authorName'] as String? ?? 'Athlete',
                                            style: GoogleFonts.spaceGrotesk(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            comment['text'] as String? ?? '',
                                            style: GoogleFonts.manrope(
                                              fontSize: 13,
                                              color: AppColors.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (canDelete)
                                      GestureDetector(
                                        onTap: () => _delete(comment['id'] as String),
                                        child: const Padding(
                                          padding: EdgeInsets.all(4),
                                          child: Icon(Icons.close_rounded,
                                              size: 16, color: AppColors.onSurfaceVariant),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(48),
                        ),
                        child: TextField(
                          controller: _textController,
                          style: GoogleFonts.manrope(fontSize: 14, color: AppColors.onSurface),
                          decoration: InputDecoration(
                            hintText: 'Add a comment…',
                            hintStyle: GoogleFonts.manrope(
                                fontSize: 14, color: AppColors.onSurfaceVariant),
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: _isPosting ? null : _post,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                        child: _isPosting
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.onPrimary),
                              )
                            : const Icon(Icons.arrow_upward_rounded,
                                color: AppColors.onPrimary, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
