/// Matching logic for resolving a plan's scheduled days against logged
/// workouts. Shared by HomeScreen (calendar rendering) and AdaptService
/// (skip-streak detection) so both walk the same definition of "was this
/// day logged" — kept in one place instead of two possibly-divergent copies.
class ScheduleMatcher {
  /// Finds the plan day scheduled for [weekday] (1=Monday..7=Sunday).
  static Map<String, dynamic>? planDayForWeekday(
    List<Map<String, dynamic>> planDays,
    int weekday,
  ) {
    for (final day in planDays) {
      if (day['dayNumber'] == weekday) return day;
    }
    return null;
  }

  /// Finds a completed workout log whose completedAt falls on [date].
  static Map<String, dynamic>? logForDate(
    List<Map<String, dynamic>> logs,
    DateTime date,
  ) {
    for (final log in logs) {
      final completedAt = log['completedAt'] as String?;
      if (completedAt == null) continue;
      try {
        final logDate = DateTime.parse(completedAt);
        if (logDate.year == date.year &&
            logDate.month == date.month &&
            logDate.day == date.day) {
          return log;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// Canonical 'YYYY-MM-DD' key used for schedule-override doc IDs and
  /// missed-day-resolution lookups, so every part of Phase 25 formats
  /// dates identically.
  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Finds the one-time schedule override(s) for [date], if any, merged
  /// into a single synthetic day. An override is content for this one
  /// calendar date that leaves the recurring weekly template alone: a
  /// missed session moved here (Phase 25 reschedule), or the date's own
  /// one-time version (an exercise added "just this time", a swap for this
  /// week only — see WorkoutPlanService.setDaysForDates). A missed session
  /// now moves whole, as one version; older data can still hold several
  /// per-muscle-group moves on one date, so this merges every matching
  /// override's exercises rather than returning just one and silently
  /// dropping the rest.
  ///
  /// A one-time version that's a rest day (a workout swapped away for the
  /// week) leaves the date empty, so a missed session can be rescheduled
  /// onto it later — when that happens, the moved session wins.
  static Map<String, dynamic>? overrideForDate(
    List<Map<String, dynamic>> overrides,
    DateTime date,
  ) {
    final key = dateKey(date);
    final matches = overrides.where((o) => o['date'] == key).toList();
    if (matches.isEmpty) return null;
    final workouts = matches.where((o) => o['dayType'] != 'rest').toList();
    if (workouts.isEmpty) return matches.first;
    if (workouts.length == 1) return workouts.first;

    final exercises = <Map<String, dynamic>>[];
    final muscleGroups = <String>[];
    for (final override in workouts) {
      exercises.addAll(
          (override['exercises'] as List?)?.cast<Map<String, dynamic>>() ?? []);
      final group = override['muscleGroup'] as String?;
      if (group != null) muscleGroups.add(group);
    }

    return {
      'date': key,
      'dayType': 'workout',
      'workoutName': '${muscleGroups.join(' + ')} (Rescheduled)',
      'muscleGroup': muscleGroups.join(', '),
      'exercises': exercises,
      'sourceMissedDates': [for (final o in workouts) ...sourceMissedDates(o)],
    };
  }

  /// The recurring plan day behind [day]: itself for a plan day, the day
  /// whose workout a one-time version holds ('planDayId'), or null when
  /// there's none (e.g. a rescheduled session).
  static Map<String, dynamic>? planDayOf(
    List<Map<String, dynamic>> planDays,
    Map<String, dynamic> day,
  ) {
    if (day['id'] is String) return day;
    final id = day['planDayId'];
    if (id == null) return null;
    for (final planDay in planDays) {
      if (planDay['id'] == id) return planDay;
    }
    return null;
  }

  /// The missed dates whose sessions an override carries — one for a
  /// rescheduled session ('sourceMissedDate'), any number for a merged day
  /// or a one-time version built from one ('sourceMissedDates').
  static List<String> sourceMissedDates(Map<String, dynamic> override) => [
        ?override['sourceMissedDate'] as String?,
        ...(override['sourceMissedDates'] as List?)?.cast<String>() ?? const [],
      ];

  /// Resolves the plan day that actually applies on [date]: a one-time
  /// override when one exists, otherwise the recurring weekday template.
  /// Every place that needs "what's scheduled on this date" (the
  /// calendar, "start today's workout", and reschedule-day-finding) must
  /// go through this single lookup so a rescheduled day reads the same
  /// everywhere.
  static Map<String, dynamic>? resolvedDayForDate(
    List<Map<String, dynamic>> planDays,
    List<Map<String, dynamic>> overrides,
    DateTime date,
  ) {
    final override = overrideForDate(overrides, date);
    if (override != null) return override;
    return planDayForWeekday(planDays, date.weekday);
  }
}
