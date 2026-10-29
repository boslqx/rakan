import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'workout_plan_service.dart';

/// Handles scheduling of local workout reminder notifications, plus the
/// one-time injury recovery check-ins (IDs 1000+).
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
  bool _timezoneReady = false;
  bool _pluginReady = false;
  bool _launchTapHandled = false;

  // Notification IDs 101-107 reserved for the 7 days of the week
  // (Monday=101 ... Sunday=107). Fixed IDs let us cancel/replace
  // a specific day's reminder without touching others.
  static const int _baseNotificationId = 100;

  // Where Settings keeps the weekly-reminder choice (on this device).
  static const String kRemindersEnabledKey = 'reminders_enabled';
  static const String kReminderHourKey = 'reminder_hour';
  static const String kReminderMinuteKey = 'reminder_minute';

  // Notification IDs 201-207 reserved for per-day "start workout at X"
  // reminders set directly on a workout day card (Schedule tab). Kept in
  // a separate ID range from the 101-107 blanket weekly reminders so the
  // two features can't cancel/overwrite each other.
  static const int _dayReminderBaseId = 200;

  // Every ID from 1000 up is a one-time injury recovery check-in. Each
  // injury gets its own ID hashed from its Firestore doc ID (see
  // injuryReminderId), so it can be cancelled on its own and can never
  // collide with the 101-107 / 201-207 weekly ranges or the 999 test ping.
  static const int _injuryReminderBaseId = 1000;
  static const int _injuryReminderIdSpan = 1000000000;

  /// Payload prefix on injury check-ins; tapping one opens Recovery Map.
  static const String _injuryPayloadPrefix = 'injury:';

  /// Bumped whenever the user taps an injury check-in. MainShell and
  /// CoachScreen listen to it to jump to Coach → Recovery Map.
  final ValueNotifier<int> recoveryMapRequests = ValueNotifier(0);

  /// Must be called once before scheduling — sets up timezone data
  /// and platform-specific notification channels.
  Future<void> init() async {
    if (_initialized) return;

    await _initTimezone();
    await _initPlugin();

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

  Future<void> _initTimezone() async {
    if (_timezoneReady) return;
    // latest_all (not latest) is required here: Android reports the device
    // zone as "Asia/Kuala_Lumpur", which IANA tzdata defines as an alias of
    // the canonical "Asia/Singapore" zone. package:timezone's "latest"
    // dataset only ships canonical zone names and throws on alias lookups
    // ("Location ... doesn't exist") — "latest_all" includes the aliases.
    tzdata.initializeTimeZones();
    await _setLocalTimezone();
    _timezoneReady = true;
  }

  /// Plugin setup only — no permission prompts, so it is safe to run when
  /// a screen loads (tap handling, injury reminder backfill).
  Future<void> _initPlugin() async {
    if (_pluginReady) return;
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // v22 uses named parameter 'settings' instead of positional
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: (response) =>
          _handleTap(response.payload),
    );
    _pluginReady = true;
  }

  void _handleTap(String? payload) {
    if (payload != null && payload.startsWith(_injuryPayloadPrefix)) {
      recoveryMapRequests.value++;
    }
  }

  /// Called by MainShell on start. Registers the tap handler for this run
  /// of the app, and — once per launch — routes to Recovery Map if the app
  /// was opened by tapping an injury check-in.
  Future<void> handleNotificationTaps() async {
    await _initPlugin();
    if (_launchTapHandled) return;
    _launchTapHandled = true;
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      _handleTap(details!.notificationResponse?.payload);
    }
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

  /// The weekly reminders a plan gets: one per workout day (weekday 1–7 =
  /// Mon–Sun). Rest days get none (V-20).
  static List<({int weekday, String title, String body})> weeklyReminderContent(
    List<Map<String, dynamic>> days,
  ) =>
      [
        for (final day in days)
          if (day['dayType'] == 'workout')
            (
              weekday: day['dayNumber'] as int? ?? 1,
              title: 'Time to train 💪',
              body: "Today's session: ${day['workoutName'] as String? ?? 'Workout'}. "
                  "Let's get it done.",
            ),
      ];

  /// Schedules weekly reminders for each workout day in the user's plan.
  /// [hour] and [minute] define the reminder time (e.g. 8, 0 = 8:00 AM).
  ///
  /// Returns the soonest scheduled fire time (null if there are no workout
  /// days), so the caller can tell the user exactly when the next reminder
  /// arrives.
  Future<tz.TZDateTime?> scheduleWeeklyReminders({
    required List<Map<String, dynamic>> days,
    required int hour,
    required int minute,
  }) async {
    await init();
    // Cancel existing reminders before rescheduling to avoid duplicates
    // (this also clears a day that has become a rest day).
    await cancelAllReminders();

    tz.TZDateTime? soonest;

    for (final reminder in weeklyReminderContent(days)) {
      final at = await _scheduleWeekly(
        id: _baseNotificationId + reminder.weekday,
        title: reminder.title,
        body: reminder.body,
        weekday: reminder.weekday,
        hour: hour,
        minute: minute,
      );
      if (soonest == null || at.isBefore(soonest)) soonest = at;
    }
    await _logPending();
    return soonest;
  }

  /// V-20: re-schedules the weekly reminders from the current plan when
  /// they're turned on, so they follow plan changes (generation, reset,
  /// injury rebuilds, swaps, cancellations, rest-day conversions). Called
  /// when the app opens and whenever the schedule changes. Never throws.
  Future<void> refreshWeeklyReminders(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(kRemindersEnabledKey) ?? false)) return;
      final plan = await WorkoutPlanService().getActivePlan(uid);
      if (plan == null) return;
      await scheduleWeeklyReminders(
        days: (plan['days'] as List).cast<Map<String, dynamic>>(),
        hour: prefs.getInt(kReminderHourKey) ?? 8,
        minute: prefs.getInt(kReminderMinuteKey) ?? 0,
      );
    } catch (e) {
      debugPrint('[Notif] refreshWeeklyReminders failed: $e');
    }
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

  /// Stable notification ID for an injury's recovery check-in, derived from
  /// its Firestore doc ID (FNV-1a — String.hashCode isn't guaranteed to be
  /// stable across app versions). Always in [1000, 1000000999].
  static int injuryReminderId(String injuryId) {
    var hash = 0x811c9dc5;
    for (final unit in injuryId.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return _injuryReminderBaseId + hash % _injuryReminderIdSpan;
  }

  /// 9:00 AM local time on the expected recovery date (logged date +
  /// [estimatedRecoveryDays]), or null when there's no estimate.
  static DateTime? injuryReminderTime(
    DateTime? loggedAt,
    int? estimatedRecoveryDays,
  ) {
    if (loggedAt == null || estimatedRecoveryDays == null) return null;
    return DateTime(
      loggedAt.year,
      loggedAt.month,
      loggedAt.day + estimatedRecoveryDays,
      9,
    );
  }

  static String injuryReminderBody(String label, {bool affectsPlan = true}) =>
      affectsPlan
          ? 'Is your $label better? Mark it recovered in Recovery Map so it returns to your plan.'
          : 'Is your $label better? Mark it recovered in Recovery Map.';

  /// "leftKnee" -> "Left Knee"
  static String _regionLabel(String region) => region
      .replaceAllMapped(RegExp(r'[A-Z]'), (m) => ' ${m[0]}')
      .trim()
      .split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');

  /// Schedules a one-time recovery check-in for an injury at [fireAt]
  /// (device-local time). Doesn't ask for permission — callers check
  /// [hasPermission] first. Returns the notification ID to store on the
  /// injury doc, or null if [fireAt] has already passed.
  Future<int?> scheduleInjuryReminder({
    required String injuryId,
    required String label,
    required String region,
    required DateTime fireAt,
    bool affectsPlan = true,
  }) async {
    await _initTimezone();
    await _initPlugin();

    final scheduledDate = tz.TZDateTime(
      tz.local,
      fireAt.year,
      fireAt.month,
      fireAt.day,
      fireAt.hour,
      fireAt.minute,
    );
    if (!scheduledDate.isAfter(tz.TZDateTime.now(tz.local))) return null;

    // Exact like the weekly reminders when allowed. Android 14 denies exact
    // alarms by default, and an exact request then throws — a check-in that
    // lands a few minutes late is fine, so fall back to inexact.
    final canExact = await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.canScheduleExactNotifications() ??
        true;

    final id = injuryReminderId(injuryId);
    final regionLabel = _regionLabel(region);
    await _plugin.zonedSchedule(
      id: id,
      title: regionLabel.isEmpty
          ? 'Recovery check-in'
          : 'Recovery check-in · $regionLabel',
      body: injuryReminderBody(label, affectsPlan: affectsPlan),
      payload: '$_injuryPayloadPrefix$injuryId',
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'injury_reminders',
          'Injury Check-ins',
          channelDescription:
              'Asks whether an injury has recovered on its expected date',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
    );
    debugPrint('[Notif] injury id=$id -> $scheduledDate');
    await _logPending();
    return id;
  }

  /// Cancels one injury's check-in. Pass the stored reminderNotificationId
  /// when there is one; otherwise it's re-derived from [injuryId].
  Future<void> cancelInjuryReminder(
    String injuryId, {
    int? notificationId,
  }) async {
    await _plugin.cancel(id: notificationId ?? injuryReminderId(injuryId));
  }

  /// Cancels every pending injury check-in (all IDs from 1000 up).
  Future<void> cancelAllInjuryReminders() async {
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if (p.id >= _injuryReminderBaseId) await _plugin.cancel(id: p.id);
    }
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
