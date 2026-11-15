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

    test('a version kept for this week is marked as such, not as a change', () {
      final kept = WorkoutPlanService.dayVersion(
        '2024-01-11',
        {'id': 'thu', 'dayType': 'workout', 'workoutName': 'Pull', 'exercises': []},
        keptForThisWeek: true,
      );
      final changed = WorkoutPlanService.dayVersion(
        '2024-01-11',
        {'id': 'thu', 'dayType': 'workout', 'workoutName': 'Pull', 'exercises': []},
      );

      expect(kept['kind'], 'kept');
      expect(changed['kind'], 'version');
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

  group('planDayFrom', () {
    // A rest day just converted from a template: the day document holds no
    // exercises (they're a subcollection), so the map the detail screen opens
    // with must bring them along — it was opening with an empty list.
    test('a converted rest day carries its template exercises, in order, '
        'with the doc IDs edits need', () {
      final day = WorkoutPlanService.planDayFrom(
        'sat',
        {
          'dayNumber': 6,
          'dayName': 'Saturday',
          'dayType': 'workout',
          'workoutName': 'Chest Day',
          'durationMinutes': 26,
        },
        [
          {'docId': 'b', 'exerciseName': 'Incline Press', 'sets': 3, 'order': 1},
          {'docId': 'a', 'exerciseName': 'Bench Press', 'sets': 3, 'order': 0},
          {'docId': 'c', 'exerciseName': 'Chest Fly', 'sets': 3, 'order': 2},
        ],
      );

      expect(day['id'], 'sat');
      expect(day['workoutName'], 'Chest Day');
      expect(day['durationMinutes'], 26);
      final exercises = (day['exercises'] as List).cast<Map<String, dynamic>>();
      expect([for (final e in exercises) e['exerciseName']],
          ['Bench Press', 'Incline Press', 'Chest Fly']);
      expect([for (final e in exercises) e['docId']], ['a', 'b', 'c']);
    });

    test('exercises saved before ordering existed come after ordered ones', () {
      final day = WorkoutPlanService.planDayFrom('mon', {'dayType': 'workout'}, [
        {'docId': 'old', 'exerciseName': 'Squat'},
        {'docId': 'new', 'exerciseName': 'Lunge', 'order': 0},
      ]);

      expect([for (final e in day['exercises'] as List) e['docId']], ['new', 'old']);
    });

    test('an empty workout still has an exercise list', () {
      final day = WorkoutPlanService.planDayFrom('sat', {'dayType': 'workout'}, []);

      expect(day['exercises'], isEmpty);
    });
  });
}
