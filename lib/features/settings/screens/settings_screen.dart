import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/services/auth_service.dart';
import '../../auth/screens/login_screen.dart';
import '../../onboarding/services/user_profile_service.dart';
import '../../social/screens/followers_following_screen.dart';
import '../../social/services/follow_service.dart';
import '../../social/services/public_profile_service.dart';
import '../../workout/services/workout_plan_service.dart';
import '../../workout/services/notification_service.dart';
import '../../coach/services/plan_reset_flow.dart';
import '../services/account_deletion_service.dart';
import 'change_password_dialog.dart';
import 'edit_profile_screen.dart';
import 'edit_equipment_screen.dart';
import 'edit_stats_screen.dart';
import '../../../shared/widgets/pressable.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _profileService = UserProfileService();
  final _publicProfileService = PublicProfileService();
  final _followService = FollowService();

  // Profile picture — loaded from Firestore, not Firebase Auth's
  // photoURL, since the photo is stored as base64 (see
  // ProfilePictureService for why Storage isn't used).
  String? _photoBase64;

  // Reminder state
  bool _remindersEnabled = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 8, minute: 0);
  bool _isUpdatingReminders = false;

  String _appVersion = '';

  // Social stats
  int _followerCount = 0;
  int _followingCount = 0;
  int _totalSessions = 0;
  bool _isPrivate = false;
  bool _isUpdatingPrivacy = false;

  // SharedPreferences keys
  static const _kRemindersEnabled = 'reminders_enabled';
  static const _kReminderHour = 'reminder_hour';
  static const _kReminderMinute = 'reminder_minute';

  @override
  void initState() {
    super.initState();
    _loadReminderPrefs();
    _loadProfilePicture();
    _loadAppVersion();
    _loadSocialStats();
  }

  Future<void> _loadSocialStats() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final results = await Future.wait([
      _followService.getFollowerCount(uid),
      _followService.getFollowingCount(uid),
      FirebaseFirestore.instance.collection('users').doc(uid).get(),
    ]);

    if (!mounted) return;
    final publicDoc = (results[2] as DocumentSnapshot<Map<String, dynamic>>).data();
    setState(() {
      _followerCount = results[0] as int;
      _followingCount = results[1] as int;
      _totalSessions = publicDoc?['totalSessionsLogged'] as int? ?? 0;
      _isPrivate = publicDoc?['isPrivate'] as bool? ?? false;
    });
  }

  Future<void> _togglePrivate(bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isUpdatingPrivacy = true);
    try {
      await _publicProfileService.setPrivate(uid, value);
      if (!mounted) return;
      setState(() {
        _isPrivate = value;
        _isUpdatingPrivacy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUpdatingPrivacy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update privacy setting',
              style: GoogleFonts.manrope(color: AppColors.onSurface)),
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
    }
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _appVersion = '${info.version}+${info.buildNumber}');
  }

  Future<void> _loadProfilePicture() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final profile = await _profileService.getUserProfile(uid);
    if (!mounted) return;
    setState(() {
      _photoBase64 = profile?['profilePictureBase64'] as String?;
    });
  }

  Future<void> _loadReminderPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _remindersEnabled = prefs.getBool(_kRemindersEnabled) ?? false;
      _reminderTime = TimeOfDay(
        hour: prefs.getInt(_kReminderHour) ?? 8,
        minute: prefs.getInt(_kReminderMinute) ?? 0,
      );
    });
  }

  Future<void> _saveReminderPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRemindersEnabled, _remindersEnabled);
    await prefs.setInt(_kReminderHour, _reminderTime.hour);
    await prefs.setInt(_kReminderMinute, _reminderTime.minute);
  }

  /// Toggles reminders on/off.
  Future<void> _toggleReminders(bool value) async {
    setState(() => _isUpdatingReminders = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    DateTime? nextAt;

    try {
      if (value) {
        await NotificationService().init();

        final hasPermission = await NotificationService().hasPermission();
        if (!hasPermission) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Please enable notifications for Rakan in system settings',
                  style: GoogleFonts.manrope(color: AppColors.onSurface),
                ),
                backgroundColor: AppColors.surfaceContainerHigh,
              ),
            );
          }
          setState(() => _isUpdatingReminders = false);
          return;
        }

        if (uid != null) {
          final plan = await WorkoutPlanService().getActivePlan(uid);
          if (plan != null) {
            final days = (plan['days'] as List).cast<Map<String, dynamic>>();
            nextAt = await NotificationService().scheduleWeeklyReminders(
              days: days,
              hour: _reminderTime.hour,
              minute: _reminderTime.minute,
            );
          }
        }
      } else {
        await NotificationService().cancelAllReminders();
      }

      setState(() {
        _remindersEnabled = value;
        _isUpdatingReminders = false;
      });
      await _saveReminderPrefs();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !value
                  ? 'Workout reminders disabled'
                  : nextAt != null
                      ? 'Reminders on. Next: ${NotificationService.describe(nextAt)}'
                      : 'Workout reminders enabled',
              style: GoogleFonts.manrope(color: AppColors.onSurface),
            ),
            backgroundColor: AppColors.surfaceContainerHigh,
          ),
        );
      }
    } catch (e) {
      setState(() => _isUpdatingReminders = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update reminders',
                style: GoogleFonts.manrope(color: AppColors.onSurface)),
            backgroundColor: AppColors.surfaceContainerHigh,
          ),
        );
      }
    }
  }

  /// Opens a time picker, and if reminders are already enabled,
  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.primary,
              surface: AppColors.surfaceContainerLow,
              onSurface: AppColors.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    setState(() => _reminderTime = picked);
    await _saveReminderPrefs();

    // If reminders are active, reschedule with the new time
    if (_remindersEnabled) {
      // Previously unguarded: if scheduling threw (e.g. timezone lookup
      // failure), the user saw nothing at all — no reminder, no error.
      DateTime? nextAt;
      bool failed = false;
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          final plan = await WorkoutPlanService().getActivePlan(uid);
          if (plan != null) {
            final days = (plan['days'] as List).cast<Map<String, dynamic>>();
            nextAt = await NotificationService().scheduleWeeklyReminders(
              days: days,
              hour: _reminderTime.hour,
              minute: _reminderTime.minute,
            );
          }
        }
      } catch (e, stack) {
        debugPrint('_pickReminderTime failed: $e\n$stack');
        failed = true;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                failed
                    ? 'Could not update reminders'
                    : nextAt != null
                        ? 'Reminder time updated. Next: ${NotificationService.describe(nextAt)}'
                        : 'Reminder time updated',
                style: GoogleFonts.manrope(color: AppColors.onSurface)),
            backgroundColor: AppColors.surfaceContainerHigh,
          ),
        );
      }
    }
  }

  Future<void> _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Log Out',
          style: GoogleFonts.spaceGrotesk(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Are you sure you want to log out?',
          style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Log Out',
              style: GoogleFonts.manrope(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await AuthService().signOut();

    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  /// Permanently deletes the account and all its data after the user
  /// confirms and re-verifies their identity (see AccountDeletionService).
  Future<void> _deleteAccount(BuildContext context) async {
    final service = AccountDeletionService();
    final needsPassword = service.usesPassword;
    final passwordController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete account?',
          style: GoogleFonts.spaceGrotesk(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This permanently deletes your profile, plans, workout history, '
              'photos and followers. It cannot be undone.',
              style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
            ),
            if (needsPassword) ...[
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                style: GoogleFonts.manrope(color: AppColors.onSurface),
                decoration: const InputDecoration(
                  labelText: 'Password',
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Text(
                "You'll be asked to sign in with Google again to confirm.",
                style: GoogleFonts.manrope(
                    fontSize: 12, color: AppColors.onSurfaceVariant),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Delete',
              style: GoogleFonts.manrope(
                color: AppColors.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // Blocking progress indicator while everything is deleted
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      ),
    );

    String? error;
    try {
      final verified =
          await service.reauthenticate(password: passwordController.text);
      if (verified) {
        await service.deleteAccount();
      } else {
        error = 'Account deletion cancelled.';
      }
    } catch (e) {
      error = e is String ? e : "Couldn't delete your account. Please try again.";
      debugPrint('Account deletion failed: $e');
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // progress dialog

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error,
              style: GoogleFonts.manrope(color: AppColors.onSurface)),
          backgroundColor: AppColors.surfaceContainerHigh,
        ),
      );
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'About Rakan',
          style: GoogleFonts.spaceGrotesk(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rakan — Adaptive AI Fitness Coach',
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _appVersion.isNotEmpty ? 'Version $_appVersion' : 'Version —',
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'A Final Year Project exploring adaptive workout planning, real-time posture correction with MediaPipe, and fatigue-aware machine learning.',
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'CLOSE',
              style: GoogleFonts.spaceGrotesk(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
          children: [
            Text(
              'SETTINGS',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
                letterSpacing: 2,
              ),
            ),

            const SizedBox(height: 32),

            // User info card
            Pressable(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                ).then((_) {
                  // Refresh in case displayName or photo changed
                  setState(() {});
                  _loadProfilePicture();
                  _loadSocialStats();
                });
              },
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    UserAvatar(
                      photoBase64: _photoBase64,
                      initialsSource: user?.displayName?.isNotEmpty == true
                          ? user!.displayName!
                          : (user?.email ?? 'R'),
                      size: 52,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.displayName?.isNotEmpty == true
                                ? user!.displayName!
                                : 'Rakan Athlete',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user?.email ?? '',
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.onSurfaceVariant,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Social stats row
            _buildSocialStatsRow(),

            const SizedBox(height: 24),

            // Settings items
            _SettingsTile(
              icon: Icons.lock_outline_rounded,
              label: 'Change Password',
              onTap: () => ChangePasswordDialog.show(context),
            ),

            _SettingsTile(
              icon: Icons.monitor_weight_outlined,
              label: 'Personal Stats',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditStatsScreen()),
                );
              },
            ),

            _SettingsTile(
              icon: Icons.fitness_center_rounded,
              label: 'Edit Equipment',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditEquipmentScreen()),
                );
              },
            ),

            _SettingsTile(
              icon: Icons.track_changes_rounded,
              label: 'Update Fitness Goals',
              onTap: () => PlanResetFlow.start(context),
            ),

            // Reminders card (custom — has toggle + time) ────────
            _buildRemindersCard(),

            // Privacy card (custom — has toggle) ────────
            _buildPrivacyCard(),

            _SettingsTile(
              icon: Icons.info_outline_rounded,
              label: 'About Rakan',
              onTap: () => _showAboutDialog(context),
            ),

            const SizedBox(height: 24),

            // Logout button
            Pressable(
              onTap: () => _logout(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(48),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Center(
                  child: Text(
                    'LOG OUT',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => _deleteAccount(context),
                child: Text(
                  'Delete account',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    color: AppColors.onSurfaceVariant,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Reminders card
  Widget _buildRemindersCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            // Toggle row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.notifications_outlined,
                      color: AppColors.onSurfaceVariant, size: 20),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Workout Reminders',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                  _isUpdatingReminders
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : Switch(
                          value: _remindersEnabled,
                          onChanged: _toggleReminders,
                          activeColor: AppColors.primary,
                        ),
                ],
              ),
            ),

            // Time picker row 
            if (_remindersEnabled) ...[
              Divider(
                color: AppColors.outlineVariant.withValues(alpha: 0.15),
                height: 1,
              ),
              Pressable(
                onTap: _pickReminderTime,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      const SizedBox(width: 36), // align with icon above
                      Expanded(
                        child: Text(
                          'Reminder Time',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        _reminderTime.format(context),
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.onSurfaceVariant,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Debug-only: fire a notification immediately. Separates
            // "can this phone show notifications at all?" from "did the
            // scheduled alarm fire?". Compiled out of release builds.
            if (kDebugMode && _remindersEnabled) ...[
              Divider(
                color: AppColors.outlineVariant.withValues(alpha: 0.15),
                height: 1,
              ),
              Pressable(
                onTap: () => NotificationService().showTestNotification(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      const SizedBox(width: 36),
                      Expanded(
                        child: Text(
                          'Send test notification (debug)',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_outline_rounded,
                color: AppColors.onSurfaceVariant, size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Private Account',
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.onSurface,
                    ),
                  ),
                  Text(
                    'Approve new followers before they can see your activity.',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            _isUpdatingPrivacy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  )
                : Switch(
                    value: _isPrivate,
                    onChanged: _togglePrivate,
                    activeColor: AppColors.primary,
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialStatsRow() {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SocialStat(
              label: 'FOLLOWERS',
              value: '$_followerCount',
              onTap: uid == null
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              FollowersFollowingScreen(uid: uid, initialTab: 0),
                        ),
                      ).then((_) => _loadSocialStats()),
            ),
          ),
          Container(width: 1, height: 32, color: AppColors.outlineVariant.withValues(alpha: 0.3)),
          Expanded(
            child: _SocialStat(
              label: 'FOLLOWING',
              value: '$_followingCount',
              onTap: uid == null
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              FollowersFollowingScreen(uid: uid, initialTab: 1),
                        ),
                      ).then((_) => _loadSocialStats()),
            ),
          ),
          Container(width: 1, height: 32, color: AppColors.outlineVariant.withValues(alpha: 0.3)),
          Expanded(
            child: _SocialStat(label: 'SESSIONS', value: '$_totalSessions'),
          ),
        ],
      ),
    );
  }
}

class _SocialStat extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _SocialStat({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
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

// Reusable settings row tile
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.onSurfaceVariant, size: 20),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onSurface,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}