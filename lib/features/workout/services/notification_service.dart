import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;

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

  // Notification IDs 201-207 reserved for per-day "start workout at X"
  // reminders set directly on a workout day card (Schedule tab). Kept in
  // a separate ID range from the 101-107 blanket weekly reminders so the
  // two features can't cancel/overwrite each other.
  static const int _dayReminderBaseId = 200;

  /// Must be called once before scheduling — sets up timezone data
  /// and platform-specific notification channels.
  Future<void> init() async {
    if (_initialized) return;

    // latest_all (not latest) is required here: Android reports the device
    // zone as "Asia/Kuala_Lumpur", which IANA tzdata defines as an alias of
    // the canonical "Asia/Singapore" zone. package:timezone's "latest"
    // dataset only ships canonical zone names and throws on alias lookups
    // ("Location ... doesn't exist") — "latest_all" includes the aliases.
    tzdata.initializeTimeZones();
    await _setLocalTimezone();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // v22 uses named parameter 'settings' instead of positional
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidSettings),
    );

    // Android 13+ requires runtime notification permission
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    // Android 12+ requires exact alarm permission for precise scheduling
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestExactAlarmsPermission();

    _initialized = true;
  }

  /// Points package:timezone's `tz.local` at the device's zone.
  ///
  /// WHY A FALLBACK: some older / regional Android ROMs report the zone as
  /// a non-IANA string (e.g. "GMT+08:00") instead of "Asia/Kuala_Lumpur".
  /// `tz.getLocation` throws on those, which previously aborted init()
  /// and silently stopped every reminder from being scheduled. If the name
  /// can't be resolved, we fall back to a fixed-offset "Etc/GMT" zone built
  /// from the phone's current UTC offset — correct for Malaysia, which has
  /// no daylight saving time.
  Future<void> _setLocalTimezone() async {
    String? reported;
    try {
      reported = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(reported));
      debugPrint('[Notif] timezone: $reported');
      return;
    } catch (e) {
      debugPrint('[Notif] could not resolve timezone "$reported": $e');
    }

    // Etc/GMT names use an inverted sign: UTC+8 is "Etc/GMT-8".
    final offsetHours = DateTime.now().timeZoneOffset.inHours;
    final etcName = offsetHours == 0
        ? 'Etc/UTC'
        : 'Etc/GMT${offsetHours > 0 ? '-' : '+'}${offsetHours.abs()}';
    try {
      tz.setLocalLocation(tz.getLocation(etcName));
      debugPrint('[Notif] timezone fallback: $etcName');
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
      debugPrint('[Notif] timezone fallback: UTC');
    }
  }

  /// Human-readable description of when a reminder will next fire,
  /// e.g. "Thu 8:37 PM" — shown to the user right after scheduling so a
  /// wrong AM/PM or wrong weekday is obvious immediately instead of
  /// looking like "the notification never came".
  static String describe(DateTime t) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final mm = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    final now = DateTime.now();
    final isToday =
        t.year == now.year && t.month == now.month && t.day == now.day;
    return '${isToday ? 'Today' : days[t.weekday - 1]} $h12:$mm $ampm';
  }

  /// Schedules weekly reminders for each day in the user's 7-day plan.
  /// [hour] and [minute] define the reminder time (e.g. 8, 0 = 8:00 AM).
  /// dayNumber 1–7 maps directly to weekday 1–7 (Mon–Sun).
  ///
  /// Returns the soonest scheduled fire time (null if [days] is empty), so
  /// the caller can tell the user exactly when the next reminder arrives.
  Future<tz.TZDateTime?> scheduleWeeklyReminders({
    required List<Map<String, dynamic>> days,
    required int hour,
    required int minute,
  }) async {
    await init();
    // Cancel existing reminders before rescheduling to avoid duplicates
    await cancelAllReminders();

    tz.TZDateTime? soonest;

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

      final at = await _scheduleWeekly(
        id: _baseNotificationId + dayNumber,
        title: title,
        body: body,
        weekday: dayNumber, // dayNumber 1-7 = Mon-Sun
        hour: hour,
        minute: minute,
      );
      if (soonest == null || at.isBefore(soonest)) soonest = at;
    }
    await _logPending();
    return soonest;
  }

  /// Schedules a single notification that repeats every week on
  /// [weekday] (1=Monday … 7=Sunday) at [hour]:[minute].
  Future<tz.TZDateTime> _scheduleWeekly({
    required int id,
    required String title,
    required String body,
    required int weekday,
    required int hour,
    required int minute,
  }) async {
    final scheduledDate = _nextInstanceOfWeekdayTime(weekday, hour, minute);
    debugPrint('[Notif] id=$id weekday=$weekday -> $scheduledDate '
        '(now ${tz.TZDateTime.now(tz.local)})');

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
    return scheduledDate;
  }

  /// Debug aid: prints every reminder the plugin currently has queued, so
  /// "did it actually get scheduled?" can be answered from the VS Code
  /// debug console instead of guessed at.
  Future<void> _logPending() async {
    if (!kDebugMode) return;
    final pending = await _plugin.pendingNotificationRequests();
    debugPrint('[Notif] ${pending.length} pending: '
        '${pending.map((p) => p.id).join(', ')}');
  }

  /// Fires a notification immediately. Used to separate "can this phone
  /// show Rakan notifications at all?" from "did the alarm fire on time?".
  Future<void> showTestNotification() async {
    await init();
    await _plugin.show(
      id: 999,
      title: 'Rakan test notification',
      body: 'If you can see this, notifications work on this phone.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'workout_reminders',
          'Workout Reminders',
          channelDescription: 'Reminders for your weekly workout schedule',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }

  /// Returns the next future occurrence of [weekday] at [hour]:[minute]
  /// in the device's local timezone.
  tz.TZDateTime _nextInstanceOfWeekdayTime(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
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

  /// Schedules a "time to start" reminder for a single workout day
  /// (Schedule tab), repeating weekly on [dayNumber] (1=Monday…7=Sunday)
  /// at [hour]:[minute].
  ///
  /// Returns the next fire time so the caller can show it to the user.
  Future<tz.TZDateTime> scheduleDayReminder({
    required int dayNumber,
    required String workoutName,
    required int hour,
    required int minute,
  }) async {
    await init();
    final at = await _scheduleWeekly(
      id: _dayReminderBaseId + dayNumber,
      title: 'Time to train 💪',
      body: "$workoutName starts now. Let's get it done.",
      weekday: dayNumber,
      hour: hour,
      minute: minute,
    );
    await _logPending();
    return at;
  }

  /// Cancels a single day's "time to start" reminder.
  Future<void> cancelDayReminder(int dayNumber) async {
    await _plugin.cancel(id: _dayReminderBaseId + dayNumber);
  }

  /// Returns true if notification permission has been granted.
  Future<bool> hasPermission() async {
    final granted = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.areNotificationsEnabled();
    return granted ?? false;
  }
}
