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
  /// into a single synthetic day. An override represents content moved
  /// onto this calendar date via the Phase 25 reschedule flow — it does
  /// not touch the recurring weekly template. Several muscle groups from
  /// the same missed day can each be rescheduled independently and land
  /// on the same date (see WorkoutPlanService.addScheduleOverride), so
  /// this merges every matching override's exercises rather than
  /// returning just one and silently dropping the rest.
  static Map<String, dynamic>? overrideForDate(
    List<Map<String, dynamic>> overrides,
    DateTime date,
  ) {
    final key = dateKey(date);
    final matches = overrides.where((o) => o['date'] == key).toList();
    if (matches.isEmpty) return null;
    if (matches.length == 1) return matches.first;

    final exercises = <Map<String, dynamic>>[];
    final muscleGroups = <String>[];
    for (final override in matches) {
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
    };
  }

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
