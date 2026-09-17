import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../workout/services/workout_log_service.dart';
import '../services/follow_service.dart';
import '../widgets/activity_log_card.dart';
import '../widgets/follow_button.dart';
import 'followers_following_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final String uid;

  const UserProfileScreen({super.key, required this.uid});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _followService = FollowService();
  final _workoutLogService = WorkoutLogService();

  bool _isLoading = true;
  Map<String, dynamic>? _profile;
  int _followerCount = 0;
  int _followingCount = 0;
  List<Map<String, dynamic>> _feed = [];
  bool get _isOwner => FirebaseAuth.instance.currentUser?.uid == widget.uid;
  bool _canViewDetails = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final viewerUid = FirebaseAuth.instance.currentUser?.uid;
    if (viewerUid == null) return;

    final results = await Future.wait([
      FirebaseFirestore.instance.collection('users').doc(widget.uid).get(),
      _followService.getFollowerCount(widget.uid),
      _followService.getFollowingCount(widget.uid),
      _followService.getFollowStatus(viewerUid: viewerUid, targetUid: widget.uid),
    ]);

    final profileSnap = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    final followerCount = results[1] as int;
    final followingCount = results[2] as int;
    final status = results[3] as FollowStatus;

    final profile = profileSnap.data();
    final isPrivate = profile?['isPrivate'] as bool? ?? false;
    final canView = _isOwner || !isPrivate || status == FollowStatus.accepted;

    List<Map<String, dynamic>> feed = [];
    if (canView) {
      feed = await _workoutLogService.getActivityFeed(widget.uid);
    }

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _followerCount = followerCount;
      _followingCount = followingCount;
      _canViewDetails = canView;
      _feed = feed;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 1.5),
              )
            : _profile == null
                ? _buildNotFound()
                : RefreshIndicator(
                    onRefresh: _load,
                    color: AppColors.primary,
                    backgroundColor: AppColors.surfaceContainerLow,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                      children: [
                        _buildBackButton(),
                        const SizedBox(height: 24),
                        _buildHeader(),
                        const SizedBox(height: 20),
                        if (!_isOwner) ...[
                          FollowButton(
                            targetUid: widget.uid,
                            compact: false,
                            onChanged: _load,
                          ),
                          const SizedBox(height: 24),
                        ],
                        if (_canViewDetails) ...[
                          _buildStatsRow(),
                          const SizedBox(height: 28),
                          _buildFeed(),
                        ] else
                          _buildLockedState(),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Text('User not found', style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant)),
    );
  }

  Widget _buildBackButton() {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface, size: 18),
      ),
    );
  }

  Widget _buildHeader() {
    final displayName = _profile?['displayName'] as String? ?? 'Athlete';
    final username = _profile?['username'] as String?;
    final photoBase64 = _profile?['photoBase64'] as String?;

    return Column(
      children: [
        UserAvatar(photoBase64: photoBase64, initialsSource: displayName, size: 84),
        const SizedBox(height: 14),
        Text(
          displayName,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
        if (username != null) ...[
          const SizedBox(height: 2),
          Text(
            '@$username',
            style: GoogleFonts.manrope(fontSize: 14, color: AppColors.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _buildStatsRow() {
    final totalExercises = _profile?['totalExercisesLogged'] as int? ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatColumn(
              label: 'FOLLOWERS',
              value: '$_followerCount',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FollowersFollowingScreen(uid: widget.uid, initialTab: 0),
                ),
              ),
            ),
          ),
          _StatDivider(),
          Expanded(
            child: _StatColumn(
              label: 'FOLLOWING',
              value: '$_followingCount',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FollowersFollowingScreen(uid: widget.uid, initialTab: 1),
                ),
              ),
            ),
          ),
          _StatDivider(),
          Expanded(
            child: _StatColumn(label: 'EXERCISES', value: '$totalExercises'),
          ),
        ],
      ),
    );
  }

  Widget _buildFeed() {
    if (_feed.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            'No workouts logged yet.',
            style: GoogleFonts.manrope(fontSize: 13, color: AppColors.onSurfaceVariant),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final log in _feed) ...[
          ActivityLogCard(log: log),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildLockedState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Icon(Icons.lock_outline_rounded, color: AppColors.onSurfaceVariant, size: 32),
          const SizedBox(height: 12),
          Text(
            'This account is private',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Follow this account to see their activity.',
            style: GoogleFonts.manrope(fontSize: 13, color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _StatColumn({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: AppColors.outlineVariant.withValues(alpha: 0.3));
  }
}
