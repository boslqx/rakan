import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;

/// Handles scheduling of local workout reminder notifications.
///
/// WHY LOCAL NOTIFICATIONS (not push/FCM):
/// The 7-day workout plan is already known to the device once fetched
/// from Firestore. Scheduling reminders locally means zero backend cost,
/// zero server-side cron jobs, and notifications still fire even if the
/// app has no internet connection. This matches the "keep cost at zero"
/// constraint of the FYP.
///
/// NOTE: This service uses flutter_local_notifications v22+ which
/// changed all method signatures to named parameters.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // Notification IDs 101-107 reserved for the 7 days of the week
  // (Monday=101 ... Sunday=107). Fixed IDs let us cancel/replace
  // a specific day's reminder without touching others.
  static const int _baseNotificationId = 100;

  /// Must be called once before scheduling — sets up timezone data
  /// and platform-specific notification channels.
  Future<void> init() async {
    if (_initialized) return;

    tzdata.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // v22 uses named parameter 'settings' instead of positional
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidSettings),
    );

    // Android 13+ requires runtime notification permission
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // Android 12+ requires exact alarm permission for precise scheduling
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();

    _initialized = true;
  }

  /// Schedules weekly reminders for each day in the user's 7-day plan.
  /// [hour] and [minute] define the reminder time (e.g. 8, 0 = 8:00 AM).
  /// dayNumber 1–7 maps directly to weekday 1–7 (Mon–Sun).
  Future<void> scheduleWeeklyReminders({
    required List<Map<String, dynamic>> days,
    required int hour,
    required int minute,
  }) async {
    await init();
    // Cancel existing reminders before rescheduling to avoid duplicates
    await cancelAllReminders();

    for (final day in days) {
      final dayNumber = day['dayNumber'] as int? ?? 1;
      final dayType = day['dayType'] as String? ?? 'rest';
      final workoutName = day['workoutName'] as String? ?? 'Workout';

      final String title;
      final String body;

      if (dayType == 'workout') {
        title = 'Time to train 💪';
        body = "Today's session: $workoutName. Let's get it done.";
      } else {
        title = 'Rest Day 🧘';
        body = 'Recovery is part of the plan — take it easy today.';
      }

      await _scheduleWeekly(
        id: _baseNotificationId + dayNumber,
        title: title,
        body: body,
        weekday: dayNumber, // dayNumber 1-7 = Mon-Sun
        hour: hour,
        minute: minute,
      );
    }
  }

  /// Schedules a single notification that repeats every week on
  /// [weekday] (1=Monday … 7=Sunday) at [hour]:[minute].
  Future<void> _scheduleWeekly({
    required int id,
    required String title,
    required String body,
    required int weekday,
    required int hour,
    required int minute,
  }) async {
    final scheduledDate = _nextInstanceOfWeekdayTime(weekday, hour, minute);

    // v22: all parameters are named
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'workout_reminders',
          'Workout Reminders',
          channelDescription: 'Reminders for your weekly workout schedule',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  /// Returns the next future occurrence of [weekday] at [hour]:[minute]
  /// in the device's local timezone.
  tz.TZDateTime _nextInstanceOfWeekdayTime(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local, now.year, now.month, now.day, hour, minute,
    );
    // Walk forward until we reach the target weekday in the future
    while (scheduled.weekday != weekday || scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Cancels all scheduled workout reminders (IDs 101–107).
  Future<void> cancelAllReminders() async {
    for (int weekday = 1; weekday <= 7; weekday++) {
      // v22: cancel takes named parameter id
      await _plugin.cancel(id: _baseNotificationId + weekday);
    }
  }

  /// Returns true if notification permission has been granted.
  Future<bool> hasPermission() async {
    final granted = await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.areNotificationsEnabled();
    return granted ?? false;
  }
}