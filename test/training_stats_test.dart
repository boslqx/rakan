import 'package:flutter_test/flutter_test.dart';
import 'package:rakan/features/coach/services/training_stats.dart';

Map<String, dynamic> log(String id, DateTime day,
        {int mins = 45, double volume = 1000, bool completed = true}) =>
    {
      'logId': id,
      'completedAt': DateTime(day.year, day.month, day.day, 18).toIso8601String(),
      'totalDurationMins': mins,
      'totalVolume': volume,
      'isCompleted': completed,
    };

Map<String, dynamic> exLog(String name, String group, List<List<num>> sets,
        {int skipped = 0}) =>
    {
      'exerciseName': name,
      'muscleGroup': group,
      'setDetails': [
        for (final s in sets) {'reps': s[0], 'weightKg': s[1], 'completed': true},
        for (int i = 0; i < skipped; i++) {'reps': 10, 'weightKg': 50, 'completed': false},
      ],
    };

/// Mon/Wed/Fri plan: Mon chest 6 sets, Wed legs 9 sets, Fri chest 3 + back 6.
final plan = [
  {
    'dayNumber': 1,
    'dayType': 'workout',
    'exercises': [
      {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest', 'sets': 3},
      {'exerciseName': 'Dumbbell Bench Press', 'muscleGroup': 'Chest', 'sets': 3},
    ],
  },
  {'dayNumber': 2, 'dayType': 'rest', 'exercises': []},
  {
    'dayNumber': 3,
    'dayType': 'workout',
    'exercises': [
      {'exerciseName': 'Bodyweight Squat', 'muscleGroup': 'Legs', 'sets': 9},
    ],
  },
  {
    'dayNumber': 5,
    'dayType': 'workout',
    'exercises': [
      {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest', 'sets': 3},
      {'exerciseName': 'Dumbbell Row', 'muscleGroup': 'Back', 'sets': 6},
    ],
  },
];

void main() {
  // Thursday 8 Oct 2026; that week's Monday is 5 Oct.
  final thu = DateTime(2026, 10, 8);
  final mon = DateTime(2026, 10, 5);

  group('statsWindow', () {
    test('week runs from Monday through today', () {
      final w = statsWindow(StatsRange.week, thu);
      expect(w.start, mon);
      expect(w.days, 4);
      // Compared with last Monday–Thursday, not the days just before.
      final prev = previousWindow(StatsRange.week, thu);
      expect(prev.start, DateTime(2026, 9, 28));
      expect(prev.end, DateTime(2026, 10, 2));
    });

    test('month is the last 30 days, quarter 13 Monday-aligned weeks', () {
      expect(statsWindow(StatsRange.month, thu).days, 30);
      final q = statsWindow(StatsRange.quarter, thu);
      expect(q.start.weekday, DateTime.monday);
      expect(q.days, 7 * 12 + 4);
    });
  });

  group('summarize', () {
    test('counts completed workouts and only the sessions scheduled so far', () {
      final logs = [
        log('a', mon, mins: 50, volume: 1200),
        log('b', DateTime(2026, 10, 7), mins: 40, volume: 800),
        log('x', DateTime(2026, 10, 6), completed: false),
        log('old', DateTime(2026, 9, 30)),
      ];
      final s = summarize(logs, plan, statsWindow(StatsRange.week, thu));
      expect(s.workouts, 2);
      expect(s.minutes, 90);
      expect(s.volume, 2000);
      // Mon + Wed have passed; Fri hasn't — so 2 scheduled, not 3.
      expect(s.scheduled, 2);
      expect(s.adherence, 1.0);
    });

    test('no plan → no adherence', () {
      final s = summarize([log('a', mon)], [], statsWindow(StatsRange.week, thu));
      expect(s.scheduled, 0);
      expect(s.adherence, isNull);
    });
  });

  test('trendBuckets: week shows Mon–Sun, quarter buckets by week', () {
    final logs = [log('a', mon), log('b', mon), log('c', DateTime(2026, 10, 7))];
    final week = trendBuckets(logs, StatsRange.week, thu);
    expect(week.length, 7);
    expect(week[0].workouts, 2);
    expect(week[2].workouts, 1);
    expect(week[6].workouts, 0); // Sunday, still to come

    final quarter = trendBuckets(logs, StatsRange.quarter, thu);
    expect(quarter.length, 13);
    expect(quarter.last.workouts, 3);
  });

  group('muscleBalance', () {
    test('compares completed sets with the sets scheduled so far', () {
      final logs = [log('a', mon), log('b', DateTime(2026, 10, 7))];
      final exLogs = {
        'a': [exLog('Push-Up', 'Chest', [[12, 0], [10, 0], [10, 0]], skipped: 1)],
        'b': [exLog('Bodyweight Squat', 'Legs', [[15, 0], [15, 0]])],
      };
      final rows = muscleBalance(logs, exLogs, plan, statsWindow(StatsRange.week, thu));
      final chest = rows.firstWhere((r) => r.group == 'Chest');
      final legs = rows.firstWhere((r) => r.group == 'Legs');
      final back = rows.firstWhere((r) => r.group == 'Back');

      expect(chest.sets, 3); // the skipped set doesn't count
      expect(chest.targetSets, 6); // Monday only — Friday's not here yet
      expect(chest.volume, 32); // bodyweight sets count reps
      expect(legs.sets, 2);
      expect(legs.targetSets, 9);
      expect(back.targetSets, 0);
      expect(back.progress, isNull);

      expect(muscleBalanceInsight(rows), contains('Legs is behind plan'));
    });
  });

  group('weekStreak', () {
    test('counts back from last week; this week joins once its target is hit', () {
      // Target is 3 a week. Last two weeks hit it; the one before didn't.
      final logs = [
        for (final d in [28, 30])
          log('w1-$d', DateTime(2026, 9, d)),
        log('w1-x', DateTime(2026, 10, 2)),
        for (final d in [21, 23, 25]) log('w2-$d', DateTime(2026, 9, d)),
        log('w3', DateTime(2026, 9, 14)),
      ];
      expect(weekStreak(logs, plan, thu), 2);

      final hitThisWeek = [
        ...logs,
        log('t1', mon),
        log('t2', DateTime(2026, 10, 6)),
        log('t3', DateTime(2026, 10, 7)),
      ];
      expect(weekStreak(hitThisWeek, plan, thu), 3);
    });
  });

  group('progression', () {
    final logs = [
      log('c', DateTime(2026, 10, 7)),
      log('b', DateTime(2026, 10, 1)),
      log('a', DateTime(2026, 9, 24)),
    ]; // newest first, as getRecentLogs returns them
    final exLogs = {
      'a': [exLog('Dumbbell Bench Press', 'Chest', [[10, 20], [8, 22.5]])],
      'b': [exLog('Dumbbell Bench Press', 'Chest', [[10, 22.5], [8, 25]])],
      'c': [exLog('Push-Up', 'Chest', [[20, 0]])],
    };

    test('one point per session, oldest first, heaviest completed set', () {
      final points = progression(logs, exLogs, 'Dumbbell Bench Press');
      expect(points.map((p) => p.maxWeight), [22.5, 25]);
      expect(points.first.maxReps, 10);
      expect(progression(logs, exLogs, 'Dumbbell Bench Press', since: DateTime(2026, 9, 30)).length, 1);
    });

    test('loggedExercises sorts by how often they were done', () {
      expect(loggedExercises(exLogs), ['Dumbbell Bench Press', 'Push-Up']);
    });

    test('plateau needs five flat sessions', () {
      final flat = {
        for (int i = 0; i < 5; i++) 'p$i': [exLog('Barbell Curl', 'Arms', [[8, 30]])],
      };
      final flatLogs = [for (int i = 0; i < 5; i++) log('p$i', DateTime(2026, 9, 1 + i))];
      expect(isPlateaued(flatLogs, flat, 'Barbell Curl'), isTrue);
      expect(isPlateaued(flatLogs.take(3).toList(), flat, 'Barbell Curl'), isFalse);
    });
  });
}
