import 'package:flutter_test/flutter_test.dart';
import 'package:rakan/features/workout/services/adapt_service.dart';

void main() {
  group('AdaptService proposal generation', () {
    test('creates pending proposals for known exercises and skips unknowns', () {
      final proposals = AdaptService.buildProposalPayloads(
        sessionExercises: [
          LoggedExerciseInfo(exerciseName: 'Push-Up'),
          LoggedExerciseInfo(exerciseName: 'Mystery Move'),
        ],
        fatigueScore: 0.82,
        sourceLogId: 'log-1',
      );

      expect(proposals, hasLength(1));
      expect(proposals.first['exerciseName'], 'Push-Up');
      expect(proposals.first['muscleGroup'], 'Chest');
      expect(proposals.first['sessionFatigueScore'], 0.82);
      expect(proposals.first['status'], 'pending');
      expect(proposals.first['sourceLogId'], 'log-1');
    });
  });
}
