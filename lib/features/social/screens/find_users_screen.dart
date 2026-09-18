import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_colors.dart';
import '../services/follow_service.dart';
import '../services/public_profile_service.dart';
import '../widgets/follow_button.dart';
import '../widgets/user_list_tile.dart';
import 'user_profile_screen.dart';

class FindUsersScreen extends StatefulWidget {
  const FindUsersScreen({super.key});

  @override
  State<FindUsersScreen> createState() => _FindUsersScreenState();
}

class _FindUsersScreenState extends State<FindUsersScreen> {
  final _controller = TextEditingController();
  final _service = PublicProfileService();
  final _followService = FollowService();

  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;

  List<Map<String, dynamic>> _pendingRequests = [];

  @override
  void initState() {
    super.initState();
    _loadPendingRequests();
  }

  Future<void> _loadPendingRequests() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final requests = await _followService.getPendingRequests(uid);
    if (!mounted) return;
    setState(() => _pendingRequests = requests);
  }

  Future<void> _accept(String requesterUid) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _followService.acceptRequest(followerUid: requesterUid, followingUid: uid);
    _loadPendingRequests();
  }

  Future<void> _decline(String requesterUid) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _followService.removeFollow(followerUid: requesterUid, followingUid: uid);
    _loadPendingRequests();
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
      return;
    }

    // Immediate rebuild so the pending-requests section (only shown when
    // the search box is empty) hides right away instead of waiting for
    // the debounced search below.
    setState(() {});

    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _isSearching = true);
      final results = await _service.searchUsers(value);
      if (!mounted) return;
      setState(() {
        _results = results;
        _isSearching = false;
        _hasSearched = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                  const SizedBox(width: 16),
                  Text(
                    'FIND USERS',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextField(
                  controller: _controller,
                  onChanged: _onChanged,
                  autofocus: true,
                  style: GoogleFonts.manrope(fontSize: 15, color: AppColors.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Search by username',
                    hintStyle: GoogleFonts.manrope(
                        fontSize: 15, color: AppColors.onSurfaceVariant),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: AppColors.onSurfaceVariant),
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              if (_pendingRequests.isNotEmpty && _controller.text.isEmpty) ...[
                const SizedBox(height: 20),
                _buildPendingRequests(),
              ],
              const SizedBox(height: 16),
              Expanded(child: _buildResults()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingRequests() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PENDING REQUESTS',
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        for (final profile in _pendingRequests) ...[
          UserListTile(
            profile: profile,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => UserProfileScreen(uid: profile['uid'] as String)),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => _accept(profile['uid'] as String),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, color: AppColors.onPrimary, size: 18),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _decline(profile['uid'] as String),
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
          ),
        ],
      ],
    );
  }

  Widget _buildResults() {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 1.5),
      );
    }

    if (!_hasSearched) {
      return Center(
        child: Text(
          'Search for other athletes by their @username.',
          textAlign: TextAlign.center,
          style: GoogleFonts.manrope(fontSize: 13, color: AppColors.onSurfaceVariant),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Text(
          'No users found.',
          style: GoogleFonts.manrope(fontSize: 13, color: AppColors.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final profile = _results[index];
        final uid = profile['uid'] as String;
        return UserListTile(
          profile: profile,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => UserProfileScreen(uid: uid)),
          ),
          trailing: FollowButton(targetUid: uid),
        );
      },
    );
  }
}
