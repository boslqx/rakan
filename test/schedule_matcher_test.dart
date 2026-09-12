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
