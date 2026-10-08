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
}
