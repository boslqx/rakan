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
        planStartDate: null,
        scanLimitDays: 10,
      );

      expect(result, hasLength(2));
      expect(result.every((m) => m.muscleGroups.contains('Chest')), isTrue);
      expect(result.map((m) => m.date), containsAll([daysAgo(1), daysAgo(8)]));
    });

    test('one missed session per date, carrying every muscle group it trains', () {
      final planDays = [
        {
          'dayNumber': daysAgo(1).weekday,
          'dayType': 'workout',
          'workoutName': 'Push',
          'exercises': [
            {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
            {'exerciseName': 'Overhead Press', 'muscleGroup': 'Shoulders'},
          ],
        },
      ];

      final result = AdaptService.computeMissedDays(
        planDays: planDays,
        logs: const [],
        resolvedKeys: const {},
        today: today,
        planStartDate: null,
        scanLimitDays: 1,
      );

      expect(result, hasLength(1));
      expect(result.single.workoutName, 'Push');
      expect(result.single.muscleGroups, ['Chest', 'Shoulders']);
      expect(result.single.key, _dateKey(daysAgo(1)));
    });

    test('a date resolved as a whole session is not flagged again', () {
      final planDays = [
        {
          'dayNumber': daysAgo(1).weekday,
          'dayType': 'workout',
          'exercises': [
            {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
          ],
        },
      ];

      final result = AdaptService.computeMissedDays(
        planDays: planDays,
        logs: const [],
        resolvedKeys: {_dateKey(daysAgo(1))},
        today: today,
        planStartDate: null,
        scanLimitDays: 1,
      );

      expect(result, isEmpty);
    });

    test('never looks again at dates an earlier check settled — a rest day '
        'later swapped into a workout is not a phantom miss', () {
      // Every day is a workout now, but everything up to 3 days ago was
      // already checked (it may well have been a rest day back then).
      final planDays = [
        for (final weekday in [1, 2, 3, 4, 5, 6, 7])
          {
            'dayNumber': weekday,
            'dayType': 'workout',
            'exercises': [
              {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
            ],
          },
      ];

      final result = AdaptService.computeMissedDays(
        planDays: planDays,
        logs: const [],
        resolvedKeys: const {},
        today: today,
        planStartDate: null,
        checkedThrough: daysAgo(3),
        scanLimitDays: 10,
      );

      expect(result.map((m) => m.date), [daysAgo(1), daysAgo(2)]);
    });

    test('an older per-muscle-group resolution still settles its date', () {
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
        planStartDate: null,
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
        planStartDate: null,
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
        planStartDate: null,
        scanLimitDays: 1,
      );

      expect(result, isEmpty);
    });

    test('a workout swapped away for that week is not flagged on its old day', () {
      final planDays = [
        {
          'dayNumber': daysAgo(1).weekday,
          'dayType': 'workout',
          'exercises': [
            {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
          ],
        },
      ];

      final result = AdaptService.computeMissedDays(
        planDays: planDays,
        logs: const [],
        resolvedKeys: const {},
        today: today,
        planStartDate: null,
        overrides: [
          {'date': _dateKey(daysAgo(1)), 'kind': 'version', 'dayType': 'rest', 'exercises': []},
        ],
        scanLimitDays: 1,
      );

      expect(result, isEmpty);
    });

    test('a workout swapped onto a rest day for that week is flagged there '
        'if skipped', () {
      final planDays = [
        {'dayNumber': daysAgo(1).weekday, 'dayType': 'rest', 'exercises': []},
      ];

      final result = AdaptService.computeMissedDays(
        planDays: planDays,
        logs: const [],
        resolvedKeys: const {},
        today: today,
        planStartDate: null,
        overrides: [
          {
            'date': _dateKey(daysAgo(1)),
            'kind': 'version',
            'dayType': 'workout',
            'exercises': [
              {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
            ],
          },
        ],
        scanLimitDays: 1,
      );

      expect(result, hasLength(1));
      expect(result.single.muscleGroups, ['Chest']);
      expect(result.single.date, daysAgo(1));
    });

    test('never flags a date before the plan was generated, even if the '
        'weekday recurs within the scan window (regression: brand-new user, '
        'plan just generated, must not show phantom missed days from before '
        'the plan existed)', () {
      // Plan trains Chest every day of the week, generated 3 days ago.
      // Naively scanning the full window would flag every day before that
      // too, purely because the weekday recurs.
      final planStartDate = daysAgo(3);
      final planDays = [
        for (final weekday in [1, 2, 3, 4, 5, 6, 7])
          {
            'dayNumber': weekday,
            'dayType': 'workout',
            'exercises': [
              {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
            ],
          },
      ];

      final result = AdaptService.computeMissedDays(
        planDays: planDays,
        logs: const [],
        resolvedKeys: const {},
        today: today,
        planStartDate: planStartDate,
        scanLimitDays: 10,
      );

      // Only the days since the plan existed (offsets 1-3) can be missed —
      // nothing from before generation, even though offsets 4-10 also
      // match a scheduled weekday.
      expect(result, hasLength(3));
      expect(
        result.map((m) => m.date),
        containsAll([daysAgo(1), daysAgo(2), daysAgo(3)]),
      );
    });

    test('a plan generated exactly on the scanned date still counts that '
        'date (the boundary itself is not excluded)', () {
      final planStartDate = daysAgo(1);
      final planDays = [
        {
          'dayNumber': daysAgo(1).weekday,
          'dayType': 'workout',
          'exercises': [
            {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
          ],
        },
      ];

      final result = AdaptService.computeMissedDays(
        planDays: planDays,
        logs: const [],
        resolvedKeys: const {},
        today: today,
        planStartDate: planStartDate,
        scanLimitDays: 10,
      );

      expect(result, hasLength(1));
      expect(result.first.date, daysAgo(1));
    });

    test('a null planStartDate leaves the scan unbounded (old plans written '
        'before generatedAt existed)', () {
      // Same weekday as daysAgo(1), one week further back — with no
      // planStartDate bound, both occurrences are still flagged.
      final chestDayNumber = daysAgo(8).weekday;
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
        resolvedKeys: const {},
        today: today,
        planStartDate: null,
        scanLimitDays: 10,
      );

      expect(result, hasLength(2));
      expect(result.map((m) => m.date), containsAll([daysAgo(1), daysAgo(8)]));
    });
  });

  group('AdaptService.computeRescheduleDays', () {
    final today = DateTime(2024, 1, 10); // a Wednesday
    final missedDate = DateTime(2024, 1, 8); // the Monday just passed

    Map<String, dynamic> monday() => {
          'id': 'mon',
          'dayNumber': DateTime.monday,
          'dayType': 'workout',
          'exercises': [
            {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
          ],
        };

    test('offers rest days from today until that workout comes round again', () {
      final result = AdaptService.computeRescheduleDays(
        planDays: [monday()],
        overrides: const [],
        logs: const [],
        missedDate: missedDate,
        today: today,
      );

      // Today (Jan 10) through Sunday Jan 14 — Monday Jan 15 is its next
      // session, so the window ends before it.
      expect(result, [
        DateTime(2024, 1, 10),
        DateTime(2024, 1, 11),
        DateTime(2024, 1, 12),
        DateTime(2024, 1, 13),
        DateTime(2024, 1, 14),
      ]);
    });

    test('leaves out days with another workout, and days already trained', () {
      final result = AdaptService.computeRescheduleDays(
        planDays: [
          monday(),
          {
            'id': 'thu',
            'dayNumber': DateTime.thursday,
            'dayType': 'workout',
            'exercises': [
              {'exerciseName': 'Dumbbell Row', 'muscleGroup': 'Back'},
            ],
          },
        ],
        overrides: const [],
        logs: [
          {'completedAt': today.toIso8601String()},
        ],
        missedDate: missedDate,
        today: today,
      );

      expect(result, [
        DateTime(2024, 1, 12),
        DateTime(2024, 1, 13),
        DateTime(2024, 1, 14),
      ]);
    });

    test("that workout swapped onto a nearer day ends the window there", () {
      final result = AdaptService.computeRescheduleDays(
        planDays: [monday()],
        overrides: [
          {
            'date': '2024-01-12',
            'kind': 'version',
            'dayType': 'workout',
            'planDayId': 'mon',
            'exercises': [
              {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
            ],
          },
        ],
        logs: const [],
        missedDate: missedDate,
        today: today,
      );

      expect(result, [DateTime(2024, 1, 10), DateTime(2024, 1, 11)]);
    });

    test('a workout swapped away for the week leaves a rest day free', () {
      final result = AdaptService.computeRescheduleDays(
        planDays: [
          monday(),
          {
            'id': 'thu',
            'dayNumber': DateTime.thursday,
            'dayType': 'workout',
            'exercises': [
              {'exerciseName': 'Dumbbell Row', 'muscleGroup': 'Back'},
            ],
          },
        ],
        overrides: [
          {'date': '2024-01-11', 'kind': 'version', 'dayType': 'rest', 'exercises': []},
        ],
        logs: const [],
        missedDate: missedDate,
        today: today,
      );

      expect(result, contains(DateTime(2024, 1, 11)));
    });

    test('a session with no plan day of its own is capped at 7 days ahead', () {
      // The missed session was itself moved onto Monday — no plan day, so
      // nothing marks when it comes round again.
      final result = AdaptService.computeRescheduleDays(
        planDays: const [],
        overrides: [
          {
            'date': '2024-01-08',
            'dayType': 'workout',
            'sourceMissedDates': ['2024-01-05'],
            'exercises': [
              {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
            ],
          },
        ],
        logs: const [],
        missedDate: missedDate,
        today: today,
      );

      expect(result.first, today);
      expect(result.last, DateTime(2024, 1, 17));
      expect(result, hasLength(8));
    });
  });

  group('AdaptService.partitionMissedDaysByExpiry', () {
    final today = DateTime(2024, 1, 15);

    test('a missed day exactly 7 days old is still actionable', () {
      final missed = _missed(DateTime(2024, 1, 8));

      final result = AdaptService.partitionMissedDaysByExpiry(
        missedDays: [missed],
        today: today,
      );

      expect(result.actionable, [missed]);
      expect(result.expired, isEmpty);
    });

    test('a missed day 8 days old has expired', () {
      final missed = _missed(DateTime(2024, 1, 7));

      final result = AdaptService.partitionMissedDaysByExpiry(
        missedDays: [missed],
        today: today,
      );

      expect(result.actionable, isEmpty);
      expect(result.expired, [missed]);
    });

    test('several old misses collapse into one expired batch, not several', () {
      final missedDays = [
        _missed(DateTime(2024, 1, 1), 'Push'),
        _missed(DateTime(2023, 12, 25), 'Pull'),
        _missed(DateTime(2023, 12, 18), 'Legs'),
      ];

      final result = AdaptService.partitionMissedDaysByExpiry(
        missedDays: missedDays,
        today: today,
      );

      expect(result.actionable, isEmpty);
      expect(result.expired, hasLength(3));
      expect(result.expired.map((m) => m.workoutName),
          containsAll(['Push', 'Pull', 'Legs']));
    });

    test('actionable and expired misses are correctly separated when mixed', () {
      final recent = _missed(DateTime(2024, 1, 12));
      final old = _missed(DateTime(2023, 12, 20));

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

  group('AdaptService.detectPlateau', () {
    test('fewer than 5 sessions is insufficient history, not a plateau', () {
      // n=4 transitions need n+1=5 raw session values.
      final result = AdaptService.detectPlateau(
        sessionMaxWeights: [100, 100, 100, 100], // only 4 — one short
      );

      expect(result, isFalse);
    });

    test('exactly 5 sessions with no qualifying increase is a plateau '
        '(boundary: minimum history needed for detection to first fire)', () {
      final result = AdaptService.detectPlateau(
        sessionMaxWeights: [100, 100, 100, 100, 100],
      );

      expect(result, isTrue);
    });

    test('a genuine plateau: weight flat/declining across all 4 transitions', () {
      final result = AdaptService.detectPlateau(
        sessionMaxWeights: [100, 100, 99, 100, 98],
      );

      expect(result, isTrue);
    });

    test('one qualifying >=2% increase among the 4 transitions clears the plateau', () {
      // 100 -> 100 -> 103 (+3%, clears it) -> 103 -> 103
      final result = AdaptService.detectPlateau(
        sessionMaxWeights: [100, 100, 103, 103, 103],
      );

      expect(result, isFalse);
    });

    test('an increase below the 2% threshold does not clear the plateau', () {
      // 100 -> 101 is +1%, under the 2% threshold — every transition here
      // is either flat or under-threshold, so it still counts as a plateau.
      final result = AdaptService.detectPlateau(
        sessionMaxWeights: [100, 101, 101, 100, 100],
      );

      expect(result, isTrue);
    });

    test('an increase of exactly 2% clears the plateau (inclusive threshold)', () {
      final result = AdaptService.detectPlateau(
        sessionMaxWeights: [100, 100, 100, 100, 102],
      );

      expect(result, isFalse);
    });

    test('only the most recent n+1 sessions are considered — an old increase '
        'outside the window does not clear a current plateau', () {
      // The leading 103 (a +3% jump from a hypothetical earlier session) is
      // outside the last-5 window and must not count.
      final result = AdaptService.detectPlateau(
        sessionMaxWeights: [80, 103, 103, 103, 103, 103],
      );

      expect(result, isTrue);
    });

    test('an empty history is insufficient, not a plateau', () {
      final result = AdaptService.detectPlateau(sessionMaxWeights: []);

      expect(result, isFalse);
    });

    test('a zero-weight prior session is skipped rather than producing a '
        'divide-by-zero false positive', () {
      // 0 -> 50 has no defined % change and is skipped; the remaining
      // transitions (50->50, 50->50, 50->50) are all flat, so this still
      // reads as a plateau rather than throwing or crashing.
      final result = AdaptService.detectPlateau(
        sessionMaxWeights: [0, 50, 50, 50, 50],
      );

      expect(result, isTrue);
    });

    test('custom n and thresholdPct are honored', () {
      // n=2 needs 3 values; a 5% threshold means the +3% jump no longer clears it.
      final result = AdaptService.detectPlateau(
        sessionMaxWeights: [100, 103, 103],
        n: 2,
        thresholdPct: 0.05,
      );

      expect(result, isTrue);
    });
  });
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

MissedDay _missed(DateTime date, [String workoutName = 'Push']) =>
    MissedDay(date: date, workoutName: workoutName, muscleGroups: const ['Chest']);
