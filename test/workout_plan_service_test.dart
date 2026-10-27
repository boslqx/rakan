import 'package:flutter_test/flutter_test.dart';
import 'package:rakan/features/workout/services/workout_plan_service.dart';

void main() {
  group('estimateDurationMinutes', () {
    test('matches the backend generator (45s per set + rest, +10 min warm-up)', () {
      // backend: round(3 × (60 + 45) × 5 / 60) + 10 = round(26.25) + 10
      final exercises = List.generate(
        5,
        (_) => {'sets': 3, 'reps': 10, 'restSeconds': 60},
      );
      expect(WorkoutPlanService.estimateDurationMinutes(exercises), 36);
    });

    test('follows sets and rest, not reps', () {
      final base = [
        {'sets': 3, 'reps': 10, 'restSeconds': 60},
      ];
      final moreReps = [
        {'sets': 3, 'reps': 20, 'restSeconds': 60},
      ];
      final moreSets = [
        {'sets': 5, 'reps': 10, 'restSeconds': 60},
      ];
      expect(WorkoutPlanService.estimateDurationMinutes(moreReps),
          WorkoutPlanService.estimateDurationMinutes(base));
      expect(WorkoutPlanService.estimateDurationMinutes(moreSets),
          greaterThan(WorkoutPlanService.estimateDurationMinutes(base)));
    });

    test('an empty day is 0 minutes', () {
      expect(WorkoutPlanService.estimateDurationMinutes([]), 0);
    });
  });

  group('dayVersion', () {
    test("keeps a plan day's content but not its bookkeeping, and remembers "
        'which plan day it came from', () {
      final version = WorkoutPlanService.dayVersion('2024-01-11', {
        'id': 'thu',
        'dayNumber': 4,
        'dayName': 'Thursday',
        'reminderEnabled': true,
        'dayType': 'workout',
        'workoutName': 'Push',
        'focusDescription': 'Chest, Shoulders',
        'exercises': [
          {'docId': 'x1', 'order': 0, 'exerciseName': 'Push-Up', 'sets': 3, 'restSeconds': 60},
          {'exerciseName': 'Dips', 'sets': 3, 'restSeconds': 60, 'justThisTime': true},
        ],
      });

      expect(version['date'], '2024-01-11');
      expect(version['planDayId'], 'thu');
      expect(version['workoutName'], 'Push');
      expect(version.containsKey('dayNumber'), isFalse);
      expect(version.containsKey('reminderEnabled'), isFalse);
      final exercises = (version['exercises'] as List).cast<Map<String, dynamic>>();
      expect(exercises.first.containsKey('docId'), isFalse);
      expect(exercises.first.containsKey('order'), isFalse);
      expect(exercises.last['justThisTime'], isTrue);
      expect(version['durationMinutes'], WorkoutPlanService.estimateDurationMinutes(exercises));
    });

    test('a rest day becomes an empty rest version with no plan day', () {
      final version = WorkoutPlanService.dayVersion('2024-01-11', {
        'id': 'fri',
        'dayType': 'rest',
        'workoutName': 'Rest Day',
        'exercises': [],
      });

      expect(version['dayType'], 'rest');
      expect(version['exercises'], isEmpty);
      expect(version.containsKey('planDayId'), isFalse);
    });

    test('carries the missed dates of a rescheduled session it replaces', () {
      final version = WorkoutPlanService.dayVersion('2024-01-12', {
        'date': '2024-01-11',
        'dayType': 'workout',
        'workoutName': 'Chest (Rescheduled)',
        'sourceMissedDate': '2024-01-08',
        'exercises': [],
      });

      expect(version['date'], '2024-01-12');
      expect(version['sourceMissedDates'], ['2024-01-08']);
    });
  });
}
