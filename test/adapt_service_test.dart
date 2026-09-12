import 'package:flutter_test/flutter_test.dart';
import 'package:rakan/features/workout/services/adapt_service.dart';

void main() {
  group('AdaptService.buildSessionProposals', () {
    test('creates a pending proposal for a known exercise and skips unknowns', () {
      final proposals = AdaptService.buildSessionProposals(
        sessionExercises: [
          LoggedExerciseInfo(exerciseName: 'Push-Up'),
          LoggedExerciseInfo(exerciseName: 'Mystery Move'),
        ],
        fatigueScore: 0.82,
        sourceLogId: 'log-1',
      );

      expect(proposals, hasLength(1));
      expect(proposals.first['muscleGroup'], 'Chest');
      expect(proposals.first['sessionFatigueScore'], 0.82);
      expect(proposals.first['status'], 'pending');
      expect(proposals.first['sourceLogId'], 'log-1');
      expect(proposals.first['trigger'], 'session');
      // The old per-exercise shape is gone — proposals are keyed by muscle
      // group only, never by individual exercise name.
      expect(proposals.first.containsKey('exerciseName'), isFalse);
    });

    test('deduplicates multiple exercises sharing the same primary muscle group', () {
      final proposals = AdaptService.buildSessionProposals(
        sessionExercises: [
          LoggedExerciseInfo(exerciseName: 'Push-Up'),
          LoggedExerciseInfo(exerciseName: 'Barbell Bench Press'),
        ],
        fatigueScore: 0.5,
        sourceLogId: 'log-2',
      );

      // Both exercises are Chest — only one proposal should be produced.
      expect(proposals, hasLength(1));
      expect(proposals.first['muscleGroup'], 'Chest');
    });

    test('creates one proposal per distinct muscle group, in first-seen order', () {
      final proposals = AdaptService.buildSessionProposals(
        sessionExercises: [
          LoggedExerciseInfo(exerciseName: 'Push-Up'), // Chest
          LoggedExerciseInfo(exerciseName: 'Bodyweight Squat'), // Legs
        ],
        fatigueScore: 0.3,
        sourceLogId: 'log-3',
      );

      expect(proposals, hasLength(2));
      expect(proposals.map((p) => p['muscleGroup']), ['Chest', 'Legs']);
    });

    test('returns an empty list when no exercises resolve', () {
      final proposals = AdaptService.buildSessionProposals(
        sessionExercises: [LoggedExerciseInfo(exerciseName: 'Not A Real Exercise')],
        fatigueScore: 0.9,
        sourceLogId: 'log-4',
      );

      expect(proposals, isEmpty);
    });
  });

  group('AdaptService.buildReturnFromBreakProposal', () {
    test('creates a skip-triggered proposal with no session fatigue score, '
        'carrying the prior last-trained date but no resolved gap yet', () {
      final priorDate = DateTime(2024, 1, 1);
      final proposal = AdaptService.buildReturnFromBreakProposal(
        muscleGroup: 'Chest',
        sourceLogId: 'skip-log-1',
        priorLastTrainedDate: priorDate,
      );

      expect(proposal['muscleGroup'], 'Chest');
      expect(proposal['trigger'], 'skip');
      expect(proposal['sessionFatigueScore'], isNull);
      expect(proposal['status'], 'pending');
      expect(proposal['sourceLogId'], 'skip-log-1');
      expect(proposal['priorLastTrainedDate'], '2024-01-01');
      // Not known yet — only resolved once the user actually returns to
      // train this muscle group (AdaptService.predictAndAdapt).
      expect(proposal['daysSinceLastTrained'], isNull);
    });

    test('carries a null prior date when the muscle group has no training '
        'history at all', () {
      final proposal = AdaptService.buildReturnFromBreakProposal(
        muscleGroup: 'Chest',
        sourceLogId: 'skip-log-2',
        priorLastTrainedDate: null,
      );

      expect(proposal['priorLastTrainedDate'], isNull);
    });
  });

  // NOTE: Phase 24's `AdaptService.computeReturnFromBreakGroups` (trailing
  // occurrence-streak detection) and `AdaptService.combineProposals`
  // (streak-vs-session suppression) are DELETED, not adapted — Phase 25
  // replaces streak-counting entirely with the user's explicit "Skip
  // entirely" choice (see `computeMissedDays` below and
  // `resolvePendingSkipForSession` for the new suppression rule). Their
  // old tests are replaced by the groups below rather than migrated,
  // since the mechanism they exercised no longer exists.
  group('AdaptService.computeMissedDays', () {
    // "today" is arbitrary — every offset used below is relative to it, so
    // the fixture doesn't depend on which real weekday today happens to be.
    final today = DateTime(2024, 1, 2);
    DateTime daysAgo(int n) =>
        DateTime(today.year, today.month, today.day).subtract(Duration(days: n));

    test('flags every unresolved missed occurrence, not just a trailing streak', () {
      final chestDayNumber = daysAgo(1).weekday;

      final planDays = [
        {
          'dayNumber': chestDayNumber,
          'dayType': 'workout',
          'exercises': [
            {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
          ],
        },
      ];

      // Missed at offset 1 and offset 8 (same weekday, one week apart);
      // no log for either.
      final result = AdaptService.computeMissedDays(
        planDays: planDays,
        logs: const [],
        resolvedKeys: const {},
        today: today,
        scanLimitDays: 10,
      );

      expect(result, hasLength(2));
      expect(result.every((m) => m.muscleGroup == 'Chest'), isTrue);
      expect(result.map((m) => m.date), containsAll([daysAgo(1), daysAgo(8)]));
    });

    test('excludes a missed occurrence already resolved (present in resolvedKeys)', () {
      final chestDayNumber = daysAgo(1).weekday;
      final planDays = [
        {
          'dayNumber': chestDayNumber,
          'dayType': 'workout',
          'exercises': [
            {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
          ],
        },
      ];

      final result = AdaptService.computeMissedDays(
        planDays: planDays,
        logs: const [],
        resolvedKeys: {'Chest|${_dateKey(daysAgo(1))}'},
        today: today,
        scanLimitDays: 1,
      );

      expect(result, isEmpty);
    });

    test('a completed day is not missed', () {
      final chestDayNumber = daysAgo(1).weekday;
      final planDays = [
        {
          'dayNumber': chestDayNumber,
          'dayType': 'workout',
          'exercises': [
            {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
          ],
        },
      ];
      final logs = [
        {'completedAt': daysAgo(1).toIso8601String()},
      ];

      final result = AdaptService.computeMissedDays(
        planDays: planDays,
        logs: logs,
        resolvedKeys: const {},
        today: today,
        scanLimitDays: 1,
      );

      expect(result, isEmpty);
    });

    test('rest days and days with no scheduled plan carry no muscle groups', () {
      final planDays = [
        {'dayNumber': daysAgo(1).weekday, 'dayType': 'rest', 'exercises': []},
      ];

      final result = AdaptService.computeMissedDays(
        planDays: planDays,
        logs: const [],
        resolvedKeys: const {},
        today: today,
        scanLimitDays: 1,
      );

      expect(result, isEmpty);
    });
  });

  group('AdaptService.computeValidRescheduleDays', () {
    final today = DateTime(2024, 1, 10); // a Wednesday
    final missedDate = DateTime(2024, 1, 8); // the Monday just passed

    List<Map<String, dynamic>> planWithWeeklyOccurrence(int weekday) => [
          {
            'dayNumber': weekday,
            'dayType': 'workout',
            'exercises': [
              {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
            ],
          },
        ];

    test('(a) returns every empty day before the next occurrence, in order', () {
      // Chest trains every Monday; missed Jan 8, next occurrence Jan 15.
      // Every day in between (Tue-Sun) has no plan at all -> all empty.
      final planDays = planWithWeeklyOccurrence(missedDate.weekday);

      final result = AdaptService.computeValidRescheduleDays(
        planDays: planDays,
        overrides: const [],
        muscleGroup: 'Chest',
        missedDate: missedDate,
        lastTrainedDate: null,
        today: today,
      );

      // Candidate window starts the day after today (Jan 11, since today
      // Jan 10 is later than missedDate+1 Jan 9) and runs up to but not
      // including the next occurrence (Jan 15) — Jan 11-14, all empty.
      expect(result, [
        DateTime(2024, 1, 11),
        DateTime(2024, 1, 12),
        DateTime(2024, 1, 13),
        DateTime(2024, 1, 14),
      ]);
    });

    test('(b) returns an empty list when no empty day exists before the next occurrence', () {
      final planDays = [
        {
          'dayNumber': missedDate.weekday,
          'dayType': 'workout',
          'exercises': [
            {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
          ],
        },
        // Every other weekday also has a (non-Chest) workout scheduled,
        // so there's no empty day anywhere in the window.
        for (final weekday in [1, 2, 3, 4, 5, 6, 7])
          if (weekday != missedDate.weekday)
            {
              'dayNumber': weekday,
              'dayType': 'workout',
              'exercises': [
                {'exerciseName': 'Overhead Press', 'muscleGroup': 'Shoulders'},
              ],
            },
      ];

      final result = AdaptService.computeValidRescheduleDays(
        planDays: planDays,
        overrides: const [],
        muscleGroup: 'Chest',
        missedDate: missedDate,
        lastTrainedDate: null,
        today: today,
      );

      expect(result, isEmpty);
    });

    test('(c) returns an empty list when the 48-hour floor pushes at/past the next occurrence', () {
      // Chest trains twice weekly: Monday (missed) and Thursday, three
      // days later — a close-enough next occurrence for a recent session's
      // 48-hour floor to actually reach it.
      final thursday = missedDate.add(const Duration(days: 3));
      final planDays = [
        {
          'dayNumber': missedDate.weekday,
          'dayType': 'workout',
          'exercises': [
            {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
          ],
        },
        {
          'dayNumber': thursday.weekday,
          'dayType': 'workout',
          'exercises': [
            {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
          ],
        },
      ];

      // Trained Chest the day after the missed Monday (Jan 9) — the
      // 48-hour floor lands exactly on Thursday, the next occurrence.
      final result = AdaptService.computeValidRescheduleDays(
        planDays: planDays,
        overrides: const [],
        muscleGroup: 'Chest',
        missedDate: missedDate,
        lastTrainedDate: missedDate.add(const Duration(days: 1)),
        today: today,
      );

      expect(result, isEmpty);
    });

    test('(d) zero-width window when the missed day is the day before an '
        'already-scheduled occurrence', () {
      // Chest trains Tue/Wed back-to-back. Missed Tuesday; detected the
      // same day. The very next day (Wednesday) is already the next
      // occurrence, leaving no room at all.
      final tuesday = DateTime(2024, 1, 9);
      final wednesday = tuesday.add(const Duration(days: 1));
      final planDays = [
        {
          'dayNumber': tuesday.weekday,
          'dayType': 'workout',
          'exercises': [
            {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
          ],
        },
        {
          'dayNumber': wednesday.weekday,
          'dayType': 'workout',
          'exercises': [
            {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
          ],
        },
      ];

      final result = AdaptService.computeValidRescheduleDays(
        planDays: planDays,
        overrides: const [],
        muscleGroup: 'Chest',
        missedDate: tuesday,
        lastTrainedDate: null,
        today: tuesday,
      );

      // Earliest candidate is Wednesday, which is also the next
      // occurrence — zero-width window, not even a same-day squeeze.
      expect(result, isEmpty);
    });

    test('an override already occupying a candidate day excludes just that day', () {
      final planDays = planWithWeeklyOccurrence(missedDate.weekday);
      final overrides = [
        {'date': '2024-01-11', 'dayType': 'workout', 'exercises': []},
      ];

      final result = AdaptService.computeValidRescheduleDays(
        planDays: planDays,
        overrides: overrides,
        muscleGroup: 'Chest',
        missedDate: missedDate,
        lastTrainedDate: null,
        today: today,
      );

      // Jan 11 is occupied by the override; Jan 12-14 remain empty.
      expect(result, [
        DateTime(2024, 1, 12),
        DateTime(2024, 1, 13),
        DateTime(2024, 1, 14),
      ]);
    });
  });

  group('AdaptService.partitionMissedDaysByExpiry', () {
    final today = DateTime(2024, 1, 15);

    test('a missed day exactly 7 days old is still actionable', () {
      final missed = MissedDay(muscleGroup: 'Chest', date: DateTime(2024, 1, 8));

      final result = AdaptService.partitionMissedDaysByExpiry(
        missedDays: [missed],
        today: today,
      );

      expect(result.actionable, [missed]);
      expect(result.expired, isEmpty);
    });

    test('a missed day 8 days old has expired', () {
      final missed = MissedDay(muscleGroup: 'Chest', date: DateTime(2024, 1, 7));

      final result = AdaptService.partitionMissedDaysByExpiry(
        missedDays: [missed],
        today: today,
      );

      expect(result.actionable, isEmpty);
      expect(result.expired, [missed]);
    });

    test('several old misses collapse into one expired batch, not several', () {
      final missedDays = [
        MissedDay(muscleGroup: 'Chest', date: DateTime(2024, 1, 1)),
        MissedDay(muscleGroup: 'Shoulders', date: DateTime(2023, 12, 25)),
        MissedDay(muscleGroup: 'Legs', date: DateTime(2023, 12, 18)),
      ];

      final result = AdaptService.partitionMissedDaysByExpiry(
        missedDays: missedDays,
        today: today,
      );

      expect(result.actionable, isEmpty);
      expect(result.expired, hasLength(3));
      expect(result.expired.map((m) => m.muscleGroup),
          containsAll(['Chest', 'Shoulders', 'Legs']));
    });

    test('actionable and expired misses are correctly separated when mixed', () {
      final recent = MissedDay(muscleGroup: 'Chest', date: DateTime(2024, 1, 12));
      final old = MissedDay(muscleGroup: 'Back', date: DateTime(2023, 12, 20));

      final result = AdaptService.partitionMissedDaysByExpiry(
        missedDays: [recent, old],
        today: today,
      );

      expect(result.actionable, [recent]);
      expect(result.expired, [old]);
    });
  });

  group('AdaptService.resolvePendingSkipForSession (suppression + daysSinceLastTrained)', () {
    test('no pending skip proposal -> session proposal is not suppressed', () {
      final decision = AdaptService.resolvePendingSkipForSession(
        pendingSkipProposalData: null,
        sessionDate: DateTime(2024, 2, 1),
      );

      expect(decision.suppressSessionProposal, isFalse);
      expect(decision.daysSinceLastTrained, isNull);
    });

    test('a pending skip proposal suppresses the session proposal and computes the gap', () {
      final decision = AdaptService.resolvePendingSkipForSession(
        pendingSkipProposalData: {'priorLastTrainedDate': '2024-01-01'},
        sessionDate: DateTime(2024, 1, 29),
      );

      expect(decision.suppressSessionProposal, isTrue);
      expect(decision.daysSinceLastTrained, 28);
    });

    test('at exactly 28 days the gap is computed as 28 (short-term boundary)', () {
      final decision = AdaptService.resolvePendingSkipForSession(
        pendingSkipProposalData: {'priorLastTrainedDate': '2024-01-01'},
        sessionDate: DateTime(2024, 1, 29),
      );

      expect(decision.daysSinceLastTrained, 28);
    });

    test('at 29 days the gap is computed as 29 (long-term boundary)', () {
      final decision = AdaptService.resolvePendingSkipForSession(
        pendingSkipProposalData: {'priorLastTrainedDate': '2024-01-01'},
        sessionDate: DateTime(2024, 1, 30),
      );

      expect(decision.daysSinceLastTrained, 29);
    });

    test('still suppresses but leaves daysSinceLastTrained null when there is '
        'no prior training history to measure the gap from', () {
      final decision = AdaptService.resolvePendingSkipForSession(
        pendingSkipProposalData: {'priorLastTrainedDate': null},
        sessionDate: DateTime(2024, 1, 29),
      );

      expect(decision.suppressSessionProposal, isTrue);
      expect(decision.daysSinceLastTrained, isNull);
    });
  });
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
