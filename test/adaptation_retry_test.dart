import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rakan/features/workout/services/adapt_service.dart';
import 'package:rakan/features/workout/services/weekly_summary_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// V-12 / P1-7: failed adaptation calls are retried instead of lost.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Map<String, dynamic> entry(String logId, DateTime at) => {
        'avgRpe': 7.0,
        'maxRpe': 8.0,
        'sessionDuration': 45.0,
        'exercisesCount': 4,
        'completionRate': 1.0,
        'experienceLevel': 1,
        'sourceLogId': logId,
        'exerciseNames': ['Push-Up'],
        'sessionAt': at.toIso8601String(),
      };

  group('pending predictions', () {
    test('a failed session is queued once per workout, per account', () async {
      final at = DateTime(2026, 10, 28, 18);
      await AdaptService.queuePrediction('u1', entry('log-a', at));
      await AdaptService.queuePrediction('u1', entry('log-a', at)); // same workout
      await AdaptService.queuePrediction('u1', entry('log-b', at));

      final queued = await AdaptService.pendingPredictions('u1');
      expect(queued.map((e) => e['sourceLogId']), ['log-a', 'log-b']);
      expect(queued.first['exerciseNames'], ['Push-Up']);
      expect(await AdaptService.pendingPredictions('u2'), isEmpty);
    });

    test('sessions older than 14 days are no longer retried', () {
      final now = DateTime(2026, 10, 29, 12);
      final kept = AdaptService.unexpiredPredictions([
        entry('recent', now.subtract(const Duration(days: 3))),
        entry('edge', now.subtract(const Duration(days: 14))),
        entry('old', now.subtract(const Duration(days: 15))),
      ], now);
      expect(kept.map((e) => e['sourceLogId']), ['recent', 'edge']);
    });
  });

  // V-09: a scheduled deload is a one-week dip, not a permanent cut.
  group('deload and restore', () {
    Map<String, dynamic> apply(Map<String, dynamic> ex, Map<String, dynamic>? update) =>
        {
          ...ex,
          if (update != null)
            for (final e in update.entries)
              if (e.value is int) e.key: e.value,
        }..removeWhere((k, _) =>
            update != null && update.containsKey(k) && update[k] is! int);

    test('3 x 10 -> deload 2 x 6 -> next run back to 3 x 10 (+ its adjustment)', () {
      final start = {'sets': 3, 'reps': 10};

      final deload = WeeklySummaryService.exerciseUpdate(
          exercise: start, adjustment: -0.425, tier: 'scheduled_deload');
      expect(deload, isNotNull);
      expect(deload!['sets'], 2);
      expect(deload['reps'], 6);
      expect(deload['preDeloadSets'], 3);
      expect(deload['preDeloadReps'], 10);
      final deloaded = apply(start, deload);

      // Week after, maintain (0): restored exactly, fields cleared.
      final restore = WeeklySummaryService.exerciseUpdate(
          exercise: deloaded, adjustment: 0, tier: 'weekly_priority');
      expect(restore!['sets'], 3);
      expect(restore['reps'], 10);
      expect(restore['preDeloadSets'], isA<FieldValue>());
      expect(apply(deloaded, restore), {'sets': 3, 'reps': 10});

      // Week after, +10%: from the restored values, not from 2 x 6.
      final progress = WeeklySummaryService.exerciseUpdate(
          exercise: deloaded, adjustment: 0.10, tier: 'session_priority');
      expect(progress!['sets'], 3);
      expect(progress['reps'], 11);
    });

    test('without the restore, +10% could never bring 2 sets back to 3', () {
      final update = WeeklySummaryService.exerciseUpdate(
          exercise: {'sets': 2, 'reps': 6}, adjustment: 0.10, tier: 'session_priority');
      expect(update!['sets'], 2);
    });

    test('an exercise with nothing to restore and no change is left alone', () {
      expect(
        WeeklySummaryService.exerciseUpdate(
            exercise: {'sets': 3, 'reps': 10}, adjustment: 0, tier: ''),
        isNull,
      );
    });

    test('a reactive (forced) deload is not undone', () {
      final update = WeeklySummaryService.exerciseUpdate(
          exercise: {'sets': 4, 'reps': 10}, adjustment: -0.175, tier: 'forced_deload');
      expect(update!.containsKey('preDeloadSets'), isFalse);
    });
  });

  // V-10: a run on any weekday changes the whole template; only this
  // week's days that are already over keep their session.
  group('which days keep this week\'s session', () {
    test('a Sunday run keeps Monday to Saturday and changes them from next week', () {
      for (var day = 1; day <= 6; day++) {
        expect(
          WeeklySummaryService.keepsThisWeeksDay(
              dayNumber: day, todayWeekday: 7, loggedToday: false),
          isTrue,
        );
      }
      // Sunday itself isn't trained yet: it gets the change today.
      expect(
        WeeklySummaryService.keepsThisWeeksDay(
            dayNumber: 7, todayWeekday: 7, loggedToday: false),
        isFalse,
      );
    });

    test('today is kept only once today\'s workout is logged; later days change now', () {
      expect(
        WeeklySummaryService.keepsThisWeeksDay(
            dayNumber: 3, todayWeekday: 3, loggedToday: true),
        isTrue,
      );
      expect(
        WeeklySummaryService.keepsThisWeeksDay(
            dayNumber: 5, todayWeekday: 3, loggedToday: true),
        isFalse,
      );
    });
  });

  group('weekly run', () {
    test('a failed commit with proposals is retried, not skipped', () {
      // Simulated 500 from /commit-adaptations: proposals stay pending and
      // the week number doesn't move.
      expect(
        WeeklySummaryService.mustRetryWeeklyRun(
            hadProposals: true, commitSucceeded: false),
        isTrue,
      );
    });

    test('runs with nothing to resolve, or a successful commit, go ahead', () {
      expect(
        WeeklySummaryService.mustRetryWeeklyRun(
            hadProposals: false, commitSucceeded: false),
        isFalse,
      );
      expect(
        WeeklySummaryService.mustRetryWeeklyRun(
            hadProposals: true, commitSucceeded: true),
        isFalse,
      );
    });
  });
}
