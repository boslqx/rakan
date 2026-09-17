import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
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

  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _isSearching = false;
  bool _hasSearched = false;

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
              const SizedBox(height: 16),
              Expanded(child: _buildResults()),
            ],
          ),
        ),
      ),
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
