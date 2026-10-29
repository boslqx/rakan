import 'package:flutter_test/flutter_test.dart';
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
