import 'dart:math' as math;

import '../../workout/data/exercise_data.dart';
import '../../workout/services/adapt_service.dart';

/// Pure calculations behind the Coach tab's Stats report. Everything here
/// works on data already in memory — workout logs (newest first, as
/// WorkoutLogService.getRecentLogs returns them), each log's exerciseLogs,
/// and the active plan's days — so the report can switch range or
/// exercise without touching Firestore again.

enum StatsRange { week, month, quarter }

/// Muscle groups in the order the report lists them.
const List<String> kStatsMuscleGroups = [
  MuscleGroups.chest,
  MuscleGroups.back,
  MuscleGroups.shoulders,
  MuscleGroups.arms,
  MuscleGroups.legs,
  MuscleGroups.glutes,
  MuscleGroups.core,
];

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// [d] plus [days] calendar days (DST-safe — built from fields, not
/// Duration arithmetic).
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

/// Monday of [d]'s week.
DateTime weekStart(DateTime d) => addDays(dateOnly(d), 1 - d.weekday);

DateTime? logDate(Map<String, dynamic> log) {
  final at = DateTime.tryParse(log['completedAt'] as String? ?? '');
  return at == null ? null : dateOnly(at);
}

/// Logs that count as a finished workout.
bool isCompletedLog(Map<String, dynamic> log) => log['isCompleted'] != false;

/// A run of whole days: [start] inclusive to [end] exclusive.
class StatsWindow {
  final DateTime start;
  final DateTime end;

  const StatsWindow(this.start, this.end);

  int get days => DateTime.utc(end.year, end.month, end.day)
      .difference(DateTime.utc(start.year, start.month, start.day))
      .inDays;

  bool contains(DateTime date) => !date.isBefore(start) && date.isBefore(end);

  StatsWindow shift(int days) => StatsWindow(addDays(start, days), addDays(end, days));
}

/// The period a range covers, up to and including [today]: this week so
/// far (from Monday), the last 30 days, or the last 13 weeks (from a
/// Monday).
StatsWindow statsWindow(StatsRange range, DateTime today) {
  final end = addDays(dateOnly(today), 1);
  switch (range) {
    case StatsRange.week:
      return StatsWindow(weekStart(today), end);
    case StatsRange.month:
      return StatsWindow(addDays(end, -30), end);
    case StatsRange.quarter:
      return StatsWindow(addDays(weekStart(today), -7 * 12), end);
  }
}

/// The same span one period earlier — last week's Monday to the same
/// weekday, the 30 days before, or the 13 weeks before — so "vs previous"
/// compares like with like.
StatsWindow previousWindow(StatsRange range, DateTime today) =>
    statsWindow(range, today).shift(switch (range) {
      StatsRange.week => -7,
      StatsRange.month => -30,
      StatsRange.quarter => -91,
    });

/// Plan workout days keyed by weekday (1 = Monday).
Map<int, Map<String, dynamic>> workoutDaysByWeekday(List<Map<String, dynamic>> planDays) => {
      for (final day in planDays)
        if (day['dayType'] == 'workout') day['dayNumber'] as int: day,
    };

class PeriodSummary {
  final int workouts;
  final int minutes;
  final double volume;

  /// Workouts the plan scheduled in the period, up to today.
  final int scheduled;

  const PeriodSummary({
    required this.workouts,
    required this.minutes,
    required this.volume,
    required this.scheduled,
  });

  /// Completed vs scheduled so far (capped at 1), or null with no plan.
  double? get adherence =>
      scheduled == 0 ? null : (workouts / scheduled).clamp(0.0, 1.0).toDouble();
}

PeriodSummary summarize(
  List<Map<String, dynamic>> logs,
  List<Map<String, dynamic>> planDays,
  StatsWindow window,
) {
  var workouts = 0, minutes = 0;
  var volume = 0.0;
  for (final log in logs) {
    final date = logDate(log);
    if (date == null || !isCompletedLog(log) || !window.contains(date)) continue;
    workouts++;
    minutes += (log['totalDurationMins'] as num?)?.toInt() ?? 0;
    volume += (log['totalVolume'] as num?)?.toDouble() ?? 0;
  }

  final byWeekday = workoutDaysByWeekday(planDays);
  var scheduled = 0;
  for (var d = window.start; d.isBefore(window.end); d = addDays(d, 1)) {
    if (byWeekday.containsKey(d.weekday)) scheduled++;
  }

  return PeriodSummary(
    workouts: workouts,
    minutes: minutes,
    volume: volume,
    scheduled: scheduled,
  );
}

/// One bar of the trend chart: a day (week/month ranges) or a week
/// (3-month range).
class TrendBucket {
  final DateTime start;
  int workouts = 0;
  double volume = 0;
  int minutes = 0;

  TrendBucket(this.start);
}

/// Buckets for the trend chart. The week range shows Monday–Sunday in full
/// (days still to come stay empty), so the bars line up with the weekdays.
List<TrendBucket> trendBuckets(
  List<Map<String, dynamic>> logs,
  StatsRange range,
  DateTime today,
) {
  final window = statsWindow(range, today);
  final weekly = range == StatsRange.quarter;
  final count = switch (range) {
    StatsRange.week => 7,
    StatsRange.month => 30,
    StatsRange.quarter => 13,
  };
  final buckets = List.generate(
    count,
    (i) => TrendBucket(addDays(window.start, weekly ? i * 7 : i)),
  );

  for (final log in logs) {
    final date = logDate(log);
    if (date == null || !isCompletedLog(log) || date.isBefore(window.start)) continue;
    final offset = StatsWindow(window.start, date).days;
    final index = weekly ? offset ~/ 7 : offset;
    if (index < 0 || index >= count) continue;
    buckets[index]
      ..workouts += 1
      ..volume += (log['totalVolume'] as num?)?.toDouble() ?? 0
      ..minutes += (log['totalDurationMins'] as num?)?.toInt() ?? 0;
  }
  return buckets;
}

/// A muscle group's training in a period, against what the plan scheduled.
class MuscleBalance {
  final String group;
  final int sets;

  /// Sets the plan scheduled for this group in the period, up to today.
  final int targetSets;
  final double volume;
  final int exercises;
  final int sessions;

  const MuscleBalance({
    required this.group,
    required this.sets,
    required this.targetSets,
    required this.volume,
    required this.exercises,
    required this.sessions,
  });

  /// Done vs target, or null when the plan has nothing for this group.
  double? get progress => targetSets == 0 ? null : sets / targetSets;
}

String? _groupOf(Map<String, dynamic> exercise) {
  final group = exercise['muscleGroup'] as String?;
  if (group != null && kStatsMuscleGroups.contains(group)) return group;
  return findExerciseByName(exercise['exerciseName'] as String? ?? '')?.muscleGroup;
}

List<Map<String, dynamic>> completedSetsOf(Map<String, dynamic> exerciseLog) =>
    ((exerciseLog['setDetails'] as List?)?.cast<Map<String, dynamic>>() ?? const [])
        .where((s) => s['completed'] == true)
        .toList();

/// Completed sets per muscle group in [window] vs the plan's scheduled sets
/// for the same days. Volume uses the same per-set rule as
/// WorkoutLogService.updateMuscleRecovery: reps × kg, or reps alone for
/// bodyweight sets.
List<MuscleBalance> muscleBalance(
  List<Map<String, dynamic>> logs,
  Map<String, List<Map<String, dynamic>>> exerciseLogsByLog,
  List<Map<String, dynamic>> planDays,
  StatsWindow window,
) {
  final sets = <String, int>{}, sessions = <String, Set<String>>{};
  final volume = <String, double>{};
  final exercises = <String, Set<String>>{};

  for (final log in logs) {
    final date = logDate(log);
    final logId = log['logId'] as String?;
    if (date == null || logId == null || !window.contains(date)) continue;
    for (final ex in exerciseLogsByLog[logId] ?? const <Map<String, dynamic>>[]) {
      final group = _groupOf(ex);
      final done = completedSetsOf(ex);
      if (group == null || done.isEmpty) continue;
      sets[group] = (sets[group] ?? 0) + done.length;
      volume[group] = (volume[group] ?? 0) +
          done.fold<double>(0, (sum, s) {
            final reps = (s['reps'] as num?)?.toDouble() ?? 0;
            final kg = (s['weightKg'] as num?)?.toDouble() ?? 0;
            return sum + (kg > 0 ? reps * kg : reps);
          });
      (exercises[group] ??= {}).add(ex['exerciseName'] as String? ?? '');
      (sessions[group] ??= {}).add(logId);
    }
  }

  final targets = <String, int>{};
  final byWeekday = workoutDaysByWeekday(planDays);
  for (var d = window.start; d.isBefore(window.end); d = addDays(d, 1)) {
    final day = byWeekday[d.weekday];
    if (day == null) continue;
    for (final ex in (day['exercises'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      final group = _groupOf(ex);
      if (group == null) continue;
      targets[group] = (targets[group] ?? 0) + ((ex['sets'] as num?)?.toInt() ?? 0);
    }
  }

  return [
    for (final group in kStatsMuscleGroups)
      MuscleBalance(
        group: group,
        sets: sets[group] ?? 0,
        targetSets: targets[group] ?? 0,
        volume: volume[group] ?? 0,
        exercises: exercises[group]?.length ?? 0,
        sessions: sessions[group]?.length ?? 0,
      ),
  ];
}

/// One plain sentence about the balance: the group furthest behind plan,
/// or that everything's on track. Descriptive only — no health claims.
String muscleBalanceInsight(List<MuscleBalance> rows) {
  final planned = rows.where((r) => r.targetSets > 0).toList();
  if (planned.isNotEmpty) {
    planned.sort((a, b) => a.progress!.compareTo(b.progress!));
    final behind = planned.first;
    if (behind.progress! < 0.75) {
      return '${behind.group} is behind plan — ${behind.sets} of '
          '${behind.targetSets} scheduled sets so far.';
    }
    return 'Every muscle group is on track with your plan.';
  }
  final trained = rows.where((r) => r.sets > 0).toList()
    ..sort((a, b) => b.sets.compareTo(a.sets));
  if (trained.isEmpty) return '';
  return '${trained.first.group} got the most work this period '
      '(${trained.first.sets} sets).';
}

/// Workouts per scheduled week the plan expects (at least 1).
int weeklyTarget(List<Map<String, dynamic>> planDays) =>
    workoutDaysByWeekday(planDays).length.clamp(1, 7);

/// Weeks in a row the user hit their plan's weekly workout count, counting
/// back from last week — plus this week once it's already hit (an
/// unfinished week doesn't break the run).
int weekStreak(
  List<Map<String, dynamic>> logs,
  List<Map<String, dynamic>> planDays,
  DateTime today,
) {
  final target = weeklyTarget(planDays);
  final perWeek = <DateTime, int>{};
  for (final log in logs) {
    final date = logDate(log);
    if (date == null || !isCompletedLog(log)) continue;
    final week = weekStart(date);
    perWeek[week] = (perWeek[week] ?? 0) + 1;
  }

  final thisWeek = weekStart(today);
  var streak = (perWeek[thisWeek] ?? 0) >= target ? 1 : 0;
  for (var week = addDays(thisWeek, -7); (perWeek[week] ?? 0) >= target; week = addDays(week, -7)) {
    streak++;
  }
  return streak;
}

/// One session of an exercise, for the progression chart.
class ProgressPoint {
  final DateTime date;
  final double maxWeight;
  final int maxReps;

  const ProgressPoint(this.date, this.maxWeight, this.maxReps);
}

/// Exercises the user has logged, most-logged first.
List<String> loggedExercises(Map<String, List<Map<String, dynamic>>> exerciseLogsByLog) {
  final counts = <String, int>{};
  for (final exLogs in exerciseLogsByLog.values) {
    for (final ex in exLogs) {
      final name = ex['exerciseName'] as String?;
      if (name == null || name.isEmpty || completedSetsOf(ex).isEmpty) continue;
      counts[name] = (counts[name] ?? 0) + 1;
    }
  }
  return counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!) != 0
        ? counts[b]!.compareTo(counts[a]!)
        : a.compareTo(b));
}

/// Sessions of [exerciseName] since [since] (all if null), oldest first —
/// heaviest completed set and most reps in a completed set per session.
List<ProgressPoint> progression(
  List<Map<String, dynamic>> logs,
  Map<String, List<Map<String, dynamic>>> exerciseLogsByLog,
  String exerciseName, {
  DateTime? since,
}) {
  final points = <ProgressPoint>[];
  for (final log in logs) {
    final date = logDate(log);
    final logId = log['logId'] as String?;
    if (date == null || logId == null) continue;
    if (since != null && date.isBefore(since)) continue;
    for (final ex in exerciseLogsByLog[logId] ?? const <Map<String, dynamic>>[]) {
      if (ex['exerciseName'] != exerciseName) continue;
      final done = completedSetsOf(ex);
      if (done.isEmpty) continue;
      var maxWeight = 0.0, maxReps = 0;
      for (final s in done) {
        maxWeight = math.max(maxWeight, (s['weightKg'] as num?)?.toDouble() ?? 0);
        maxReps = math.max(maxReps, (s['reps'] as num?)?.toInt() ?? 0);
      }
      points.add(ProgressPoint(date, maxWeight, maxReps));
      break; // one point per session
    }
  }
  points.sort((a, b) => a.date.compareTo(b.date));
  return points;
}

/// Same rule as the workout flow's plateau check: the last 5 session max
/// weights from the 30 most recent workouts, through
/// AdaptService.detectPlateau.
bool isPlateaued(
  List<Map<String, dynamic>> logs,
  Map<String, List<Map<String, dynamic>>> exerciseLogsByLog,
  String exerciseName,
) {
  final maxesNewestFirst = <double>[];
  for (final log in logs.take(30)) {
    for (final ex in exerciseLogsByLog[log['logId']] ?? const <Map<String, dynamic>>[]) {
      if (ex['exerciseName'] != exerciseName) continue;
      final sets = (ex['setDetails'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final max = sets.fold<double>(
          0, (m, s) => math.max(m, (s['weightKg'] as num?)?.toDouble() ?? 0));
      if (max > 0) maxesNewestFirst.add(max);
      break;
    }
  }
  final oldestFirst = maxesNewestFirst.reversed.toList();
  return AdaptService.detectPlateau(
    sessionMaxWeights:
        oldestFirst.length <= 5 ? oldestFirst : oldestFirst.sublist(oldestFirst.length - 5),
  );
}
