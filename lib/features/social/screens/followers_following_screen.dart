import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';
import '../services/follow_service.dart';
import '../widgets/follow_button.dart';
import '../widgets/user_list_tile.dart';
import 'user_profile_screen.dart';

/// Followers/Following list for [uid], with a switchable tab bar. When
/// [uid] is the signed-in user's own uid, a third "Requests" tab shows
/// incoming pending follow requests with Accept/Decline — only meaningful
/// for your own account, so it's hidden when viewing someone else's list.
class FollowersFollowingScreen extends StatefulWidget {
  final String uid;
  final int initialTab;

  const FollowersFollowingScreen({super.key, required this.uid, this.initialTab = 0});

  @override
  State<FollowersFollowingScreen> createState() => _FollowersFollowingScreenState();
}

class _FollowersFollowingScreenState extends State<FollowersFollowingScreen>
    with SingleTickerProviderStateMixin {
  final _followService = FollowService();

  late final bool _isOwner =
      FirebaseAuth.instance.currentUser?.uid == widget.uid;
  late final TabController _tabController = TabController(
    length: _isOwner ? 3 : 2,
    vsync: this,
    initialIndex: widget.initialTab,
  );

  bool _isLoading = true;
  List<Map<String, dynamic>> _followers = [];
  List<Map<String, dynamic>> _following = [];
  List<Map<String, dynamic>> _pending = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _followService.getFollowers(widget.uid),
      _followService.getFollowing(widget.uid),
      if (_isOwner) _followService.getPendingRequests(widget.uid),
    ]);

    if (!mounted) return;
    setState(() {
      _followers = results[0];
      _following = results[1];
      _pending = _isOwner ? results[2] : [];
      _isLoading = false;
    });
  }

  Future<void> _accept(String requesterUid) async {
    await _followService.acceptRequest(followerUid: requesterUid, followingUid: widget.uid);
    _load();
  }

  Future<void> _decline(String requesterUid) async {
    await _followService.removeFollow(followerUid: requesterUid, followingUid: widget.uid);
    _load();
  }

  void _openProfile(String uid) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => UserProfileScreen(uid: uid)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.arrow_back_rounded,
                          color: AppColors.onSurface, size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.onSurfaceVariant,
              indicatorColor: AppColors.primary,
              labelStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: [
                Tab(text: 'FOLLOWERS (${_followers.length})'),
                Tab(text: 'FOLLOWING (${_following.length})'),
                if (_isOwner) Tab(text: 'REQUESTS (${_pending.length})'),
              ],
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 1.5),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildUserList(_followers, emptyText: 'No followers yet.'),
                        _buildUserList(_following, emptyText: 'Not following anyone yet.'),
                        if (_isOwner) _buildRequestsList(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserList(List<Map<String, dynamic>> users, {required String emptyText}) {
    if (users.isEmpty) {
      return Center(
        child: Text(emptyText, style: GoogleFonts.manrope(fontSize: 13, color: AppColors.onSurfaceVariant)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final profile = users[index];
        final uid = profile['uid'] as String;
        return UserListTile(
          profile: profile,
          onTap: () => _openProfile(uid),
          trailing: FollowButton(targetUid: uid),
        );
      },
    );
  }

  Widget _buildRequestsList() {
    if (_pending.isEmpty) {
      return Center(
        child: Text('No pending requests.',
            style: GoogleFonts.manrope(fontSize: 13, color: AppColors.onSurfaceVariant)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      itemCount: _pending.length,
      itemBuilder: (context, index) {
        final profile = _pending[index];
        final uid = profile['uid'] as String;
        return UserListTile(
          profile: profile,
          onTap: () => _openProfile(uid),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => _accept(uid),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, color: AppColors.onPrimary, size: 18),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _decline(uid),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.outlineVariant),
                  ),
                  child: const Icon(Icons.close_rounded, color: AppColors.onSurfaceVariant, size: 18),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
