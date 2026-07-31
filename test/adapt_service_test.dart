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
}