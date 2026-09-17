import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../services/profile_picture_service.dart';
import '../../onboarding/services/user_profile_service.dart';
import '../../social/services/public_profile_service.dart';

enum _UsernameStatus { idle, checking, available, taken, invalid, unchanged }

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _pictureService = ProfilePictureService();
  final _profileService = UserProfileService();
  final _publicProfileService = PublicProfileService();

  Map<String, dynamic>? _profileData;
  String? _photoBase64;
  String? _existingUsername;
  _UsernameStatus _usernameStatus = _UsernameStatus.idle;
  Timer? _usernameDebounce;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUpdatingPhoto = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _usernameDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _nameController.text = user.displayName ?? '';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('profile')
          .doc('data')
          .get();

      final username = await _publicProfileService.getUsername(user.uid);

      if (mounted) {
        setState(() {
          _profileData = doc.data();
          _photoBase64 = doc.data()?['profilePictureBase64'] as String?;
          _existingUsername = username;
          _usernameController.text = username ?? '';
          _usernameStatus =
              username != null ? _UsernameStatus.unchanged : _UsernameStatus.idle;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onUsernameChanged(String value) {
    _usernameDebounce?.cancel();

    if (_existingUsername != null && value == _existingUsername) {
      setState(() => _usernameStatus = _UsernameStatus.unchanged);
      return;
    }

    final formatError = PublicProfileService.validateUsernameFormat(value);
    if (formatError != null) {
      setState(() => _usernameStatus = _UsernameStatus.invalid);
      return;
    }

    setState(() => _usernameStatus = _UsernameStatus.checking);
    _usernameDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final available = await _publicProfileService.isUsernameAvailable(value);
        if (!mounted || _usernameController.text != value) return;
        setState(() =>
            _usernameStatus = available ? _UsernameStatus.available : _UsernameStatus.taken);
      } catch (e) {
        debugPrint('EditProfileScreen: availability check failed: $e');
        if (!mounted || _usernameController.text != value) return;
        setState(() => _usernameStatus = _UsernameStatus.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not check availability: $e', style: GoogleFonts.manrope()),
            backgroundColor: AppColors.surfaceContainerHigh,
          ),
        );
      }
    });
  }

  Future<void> _saveName() async {
    final newName = _nameController.text.trim();
    final newUsername = _usernameController.text.trim();

    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Name cannot be empty',
              style: GoogleFonts.manrope(color: AppColors.onSurface)),
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
      return;
    }

    final usernameUnchanged =
        _existingUsername != null && newUsername == _existingUsername;
    if (!usernameUnchanged) {
      final formatError = PublicProfileService.validateUsernameFormat(newUsername);
      if (formatError != null || _usernameStatus == _UsernameStatus.taken) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(formatError ?? 'That username is taken',
                style: GoogleFonts.manrope(color: AppColors.onSurface)),
            backgroundColor: AppColors.surfaceContainerHigh,
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      await user?.updateDisplayName(newName);

      // Keep Firestore profile in sync
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .collection('profile')
          .doc('data')
          .set({'name': newName}, SetOptions(merge: true));

      if (!usernameUnchanged) {
        await _publicProfileService.claimUsername(uid: user.uid, username: newUsername);
        _existingUsername = newUsername;
      }
      await _publicProfileService.syncPublicProfile(uid: user.uid, displayName: newName);

      if (mounted) {
        setState(() {
          _isSaving = false;
          _usernameStatus = _UsernameStatus.unchanged;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profile updated',
                style: GoogleFonts.manrope(color: AppColors.onSurface)),
            backgroundColor: AppColors.surfaceContainerHigh,
          ),
        );
      }
    } catch (e) {
      debugPrint('EditProfileScreen: save failed: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                e is StateError
                    ? 'That username is taken'
                    : 'Failed to update profile: $e',
                style: GoogleFonts.manrope(color: AppColors.onSurface)),
            backgroundColor: AppColors.surfaceContainerHigh,
          ),
        );
      }
    }
  }

  Future<void> _changePhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final bytes = await _pictureService.pickCropAndCompress();
    if (bytes == null) return; // user cancelled — no-op, not an error

    setState(() => _isUpdatingPhoto = true);
    try {
      final base64Image = _pictureService.encodeToBase64(bytes);
      await _profileService.updateProfilePicture(
        uid: user.uid,
        base64Image: base64Image,
      );
      await _publicProfileService.syncPublicProfile(uid: user.uid, photoBase64: base64Image);

      if (!mounted) return;
      setState(() {
        _photoBase64 = base64Image;
        _isUpdatingPhoto = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profile picture updated',
              style: GoogleFonts.manrope(color: AppColors.onSurface)),
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUpdatingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update profile picture',
              style: GoogleFonts.manrope(color: AppColors.onSurface)),
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
    }
  }

  Future<void> _removePhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isUpdatingPhoto = true);
    try {
      await _profileService.removeProfilePicture(user.uid);
      await _publicProfileService.clearPhoto(user.uid);

      if (!mounted) return;
      setState(() {
        _photoBase64 = null;
        _isUpdatingPhoto = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUpdatingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not remove profile picture',
              style: GoogleFonts.manrope(color: AppColors.onSurface)),
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
    }
  }

  void _showPhotoOptions() {
    final hasPhoto = _photoBase64 != null && _photoBase64!.isNotEmpty;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.onSurface),
              title: Text(
                hasPhoto ? 'Change Photo' : 'Upload Photo',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _changePhoto();
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.error),
                title: Text(
                  'Remove Photo',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w600,
                    color: AppColors.error,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _removePhoto();
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 1.5,
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                children: [
                  // Back button + title
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
                        'EDIT PROFILE',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Avatar — tap to change/remove photo
                  Center(
                    child: GestureDetector(
                      onTap: _isUpdatingPhoto ? null : _showPhotoOptions,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Opacity(
                            opacity: _isUpdatingPhoto ? 0.4 : 1.0,
                            child: UserAvatar(
                              photoBase64: _photoBase64,
                              initialsSource: user?.displayName?.isNotEmpty ==
                                      true
                                  ? user!.displayName!
                                  : (user?.email ?? 'R'),
                              size: 96,
                            ),
                          ),
                          if (_isUpdatingPhoto)
                            const Positioned.fill(
                              child: Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.surface,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.edit_rounded,
                                size: 14,
                                color: AppColors.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Editable: Display Name
                  _buildSectionTitle('DISPLAY NAME'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _nameController,
                    style: GoogleFonts.manrope(
                        fontSize: 15, color: AppColors.onSurface),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Editable: Username
                  _buildSectionTitle('USERNAME'),
                  const SizedBox(height: 10),
                  _buildUsernameField(),
                  const SizedBox(height: 6),
                  _buildUsernameHint(),

                  const SizedBox(height: 12),

                  // Read-only: Email
                  _buildSectionTitle('EMAIL'),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      user?.email ?? '—',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveName,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onPrimary,
                            ),
                          )
                        : Text(
                            'SAVE CHANGES',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                          ),
                  ),

                  const SizedBox(height: 36),

                  // Read-only: Onboarding profile summary
                  _buildSectionTitle('FITNESS PROFILE'),
                  const SizedBox(height: 4),
                  Text(
                    'These values were set during onboarding and shape your workout plan. To change them, contact support or reset your plan from the Coach tab.',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: AppColors.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildProfileInfoCard(),
                ],
              ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.manrope(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }

  Widget _buildUsernameField() {
    Widget? suffixIcon;
    switch (_usernameStatus) {
      case _UsernameStatus.checking:
        suffixIcon = const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case _UsernameStatus.available:
      case _UsernameStatus.unchanged:
        suffixIcon = const Icon(Icons.check_circle_rounded, color: AppColors.primary);
      case _UsernameStatus.taken:
      case _UsernameStatus.invalid:
        suffixIcon = const Icon(Icons.error_rounded, color: AppColors.error);
      case _UsernameStatus.idle:
        suffixIcon = null;
    }

    return TextField(
      controller: _usernameController,
      onChanged: _onUsernameChanged,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
        LengthLimitingTextInputFormatter(20),
      ],
      style: GoogleFonts.manrope(fontSize: 15, color: AppColors.onSurface),
      decoration: InputDecoration(
        filled: true,
        fillColor: AppColors.surfaceContainerLow,
        prefixText: '@',
        prefixStyle: GoogleFonts.manrope(fontSize: 15, color: AppColors.onSurfaceVariant),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildUsernameHint() {
    final (text, color) = switch (_usernameStatus) {
      _UsernameStatus.taken => ('That username is already taken', AppColors.error),
      _UsernameStatus.invalid => (
          '3-20 characters: letters, numbers, underscore only',
          AppColors.error
        ),
      _UsernameStatus.available => ('Available', AppColors.primary),
      _ => ('Used for other people to find and follow you.', AppColors.onSurfaceVariant),
    };

    return Text(text, style: GoogleFonts.manrope(fontSize: 12, color: color));
  }

  Widget _buildProfileInfoCard() {
    if (_profileData == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          'No fitness profile data found.',
          style: GoogleFonts.manrope(
              fontSize: 13, color: AppColors.onSurfaceVariant),
        ),
      );
    }

    final data = _profileData!;

    // Format enum-style strings
    String formatEnum(dynamic value) {
      if (value == null) return '—';
      final str = value.toString();
      final spaced = str.replaceAllMapped(
        RegExp(r'([A-Z])'),
        (m) => ' ${m.group(0)}',
      );
      return spaced[0].toUpperCase() + spaced.substring(1);
    }

    String formatList(dynamic value) {
      if (value == null || (value as List).isEmpty) return '—';
      return value.map((e) => formatEnum(e)).join(', ');
    }

    final age = data['age'];
    final heightCm = data['heightCm'];
    final weightKg = data['weightKg'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildInfoRow('Goal', formatEnum(data['fitnessGoal'])),
          _buildInfoRow('Experience', formatEnum(data['experienceLevel'])),
          _buildInfoRow('Activity Level', formatEnum(data['activityLevel'])),
          _buildInfoRow('Equipment', formatList(data['equipment'])),
          _buildInfoRow('Focus Areas', formatList(data['focusAreas'])),
          _buildInfoRow(
            'Age',
            age != null ? '$age years' : '—',
          ),
          _buildInfoRow(
            'Height',
            heightCm != null
                ? '${(heightCm as num).toStringAsFixed(0)} cm'
                : '—',
          ),
          _buildInfoRow(
            'Weight',
            weightKg != null
                ? '${(weightKg as num).toStringAsFixed(1)} kg'
                : '—',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: GoogleFonts.manrope(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}