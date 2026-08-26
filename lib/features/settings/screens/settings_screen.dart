import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/services/auth_service.dart';
import '../../auth/screens/login_screen.dart';
import '../../workout/services/workout_plan_service.dart';
import '../../workout/services/notification_service.dart';
import 'change_password_dialog.dart';
import 'edit_profile_screen.dart';
import 'edit_equipment_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Reminder state 
  bool _remindersEnabled = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 8, minute: 0);
  bool _isUpdatingReminders = false;

  // SharedPreferences keys
  static const _kRemindersEnabled = 'reminders_enabled';
  static const _kReminderHour = 'reminder_hour';
  static const _kReminderMinute = 'reminder_minute';

  @override
  void initState() {
    super.initState();
    _loadReminderPrefs();
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
            await NotificationService().scheduleWeeklyReminders(
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
              value ? 'Workout reminders enabled' : 'Workout reminders disabled',
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
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final plan = await WorkoutPlanService().getActivePlan(uid);
        if (plan != null) {
          final days = (plan['days'] as List).cast<Map<String, dynamic>>();
          await NotificationService().scheduleWeeklyReminders(
            days: days,
            hour: _reminderTime.hour,
            minute: _reminderTime.minute,
          );
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reminder time updated',
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
              'Version 1.0.0',
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
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                ).then((_) {
                  // Refresh in case displayName changed
                  setState(() {});
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
                    Container(
                      width: 52,
                      height: 52,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surfaceContainerHigh,
                      ),
                      child: Center(
                        child: Text(
                          (user?.displayName?.isNotEmpty == true
                                  ? user!.displayName!
                                  : (user?.email ?? 'R'))[0]
                              .toUpperCase(),
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
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

            const SizedBox(height: 24),

            // Settings items
            _SettingsTile(
              icon: Icons.lock_outline_rounded,
              label: 'Change Password',
              onTap: () => ChangePasswordDialog.show(context),
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

            // Reminders card (custom — has toggle + time)
            _buildRemindersCard(),

            _SettingsTile(
              icon: Icons.info_outline_rounded,
              label: 'About Rakan',
              onTap: () => _showAboutDialog(context),
            ),

            const SizedBox(height: 24),

            // Logout button
            GestureDetector(
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
              GestureDetector(
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
          ],
        ),
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
    return GestureDetector(
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