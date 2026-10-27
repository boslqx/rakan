import 'package:flutter_test/flutter_test.dart';
import 'package:rakan/features/workout/services/schedule_matcher.dart';

void main() {
  group('ScheduleMatcher.overrideForDate', () {
    final date = DateTime(2024, 1, 11);

    test('returns null when no override matches the date', () {
      expect(ScheduleMatcher.overrideForDate(const [], date), isNull);
    });

    test('returns the single override untouched when only one matches', () {
      final overrides = [
        {
          'date': '2024-01-11',
          'dayType': 'workout',
          'muscleGroup': 'Chest',
          'exercises': [
            {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
          ],
        },
      ];

      final result = ScheduleMatcher.overrideForDate(overrides, date);

      expect(result!['muscleGroup'], 'Chest');
      expect((result['exercises'] as List), hasLength(1));
    });

    test('merges two overrides for the same date instead of one clobbering '
        'the other — e.g. two muscle groups from a missed combined day both '
        'rescheduled onto the same empty day', () {
      final overrides = [
        {
          'date': '2024-01-11',
          'dayType': 'workout',
          'muscleGroup': 'Chest',
          'exercises': [
            {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
          ],
        },
        {
          'date': '2024-01-11',
          'dayType': 'workout',
          'muscleGroup': 'Shoulders',
          'exercises': [
            {'exerciseName': 'Overhead Press', 'muscleGroup': 'Shoulders'},
          ],
        },
      ];

      final result = ScheduleMatcher.overrideForDate(overrides, date);

      expect(result, isNotNull);
      expect(result!['dayType'], 'workout');
      final exercises = (result['exercises'] as List).cast<Map<String, dynamic>>();
      expect(exercises, hasLength(2));
      expect(
        exercises.map((e) => e['muscleGroup']),
        containsAll(['Chest', 'Shoulders']),
      );
    });
    test('a rest one-time version yields to a session rescheduled onto the '
        'same date afterwards', () {
      final overrides = [
        {'date': '2024-01-11', 'kind': 'version', 'dayType': 'rest', 'exercises': []},
        {
          'date': '2024-01-11',
          'dayType': 'workout',
          'muscleGroup': 'Chest',
          'sourceMissedDate': '2024-01-08',
          'exercises': [
            {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
          ],
        },
      ];

      final result = ScheduleMatcher.overrideForDate(overrides, date);

      expect(result!['dayType'], 'workout');
      expect(result['muscleGroup'], 'Chest');
    });

    test('a lone rest one-time version makes the date a rest day', () {
      final overrides = [
        {'date': '2024-01-11', 'kind': 'version', 'dayType': 'rest', 'exercises': []},
      ];

      expect(ScheduleMatcher.overrideForDate(overrides, date)!['dayType'], 'rest');
    });

    test('a merged day keeps every source missed date', () {
      final overrides = [
        {'date': '2024-01-11', 'dayType': 'workout', 'muscleGroup': 'Chest', 'sourceMissedDate': '2024-01-08', 'exercises': []},
        {'date': '2024-01-11', 'dayType': 'workout', 'muscleGroup': 'Back', 'sourceMissedDate': '2024-01-09', 'exercises': []},
      ];

      final result = ScheduleMatcher.overrideForDate(overrides, date)!;

      expect(ScheduleMatcher.sourceMissedDates(result), ['2024-01-08', '2024-01-09']);
    });
  });

  group('ScheduleMatcher.planDayOf', () {
    final planDays = [
      {'id': 'mon', 'dayNumber': 1, 'dayType': 'workout'},
      {'id': 'wed', 'dayNumber': 3, 'dayType': 'workout'},
    ];

    test('a plan day is its own plan day', () {
      expect(ScheduleMatcher.planDayOf(planDays, planDays[0]), same(planDays[0]));
    });

    test('a one-time version points at the plan day whose workout it holds', () {
      final version = {'date': '2024-01-12', 'kind': 'version', 'planDayId': 'wed'};
      expect(ScheduleMatcher.planDayOf(planDays, version)!['id'], 'wed');
    });

    test('a rescheduled session has no plan day', () {
      final moved = {'date': '2024-01-12', 'sourceMissedDate': '2024-01-08'};
      expect(ScheduleMatcher.planDayOf(planDays, moved), isNull);
    });
  });

  group('ScheduleMatcher.resolvedDayForDate', () {
    test('an override for the date takes precedence over the weekday template', () {
      final planDays = [
        {
          'dayNumber': DateTime(2024, 1, 11).weekday,
          'dayType': 'rest',
          'exercises': [],
        },
      ];
      final overrides = [
        {
          'date': '2024-01-11',
          'dayType': 'workout',
          'muscleGroup': 'Chest',
          'exercises': [
            {'exerciseName': 'Push-Up', 'muscleGroup': 'Chest'},
          ],
        },
      ];

      final result = ScheduleMatcher.resolvedDayForDate(
          planDays, overrides, DateTime(2024, 1, 11));

      expect(result!['dayType'], 'workout');
    });

    test('falls back to the weekday template when no override exists', () {
      final planDays = [
        {
          'dayNumber': DateTime(2024, 1, 11).weekday,
          'dayType': 'workout',
          'exercises': [],
        },
      ];

      final result = ScheduleMatcher.resolvedDayForDate(
          planDays, const [], DateTime(2024, 1, 11));

      expect(result, isNotNull);
      expect(result!['dayType'], 'workout');
    });
  });
}
