import 'package:flutter_test/flutter_test.dart';
import 'package:rakan/features/workout/services/angle_calculator.dart';

void main() {
  group('ExerciseAnalyserFactory', () {
    test('routes deadlift, lunge and curl names to their dedicated analysers', () {
      expect(
        ExerciseAnalyserFactory.getAnalyser('Barbell Deadlift'),
        isA<DeadliftAnalyser>(),
      );
      expect(
        ExerciseAnalyserFactory.getAnalyser('Reverse Lunge'),
        isA<LungeAnalyser>(),
      );
      expect(
        ExerciseAnalyserFactory.getAnalyser('Dumbbell Bicep Curl'),
        isA<BicepCurlAnalyser>(),
      );
    });
  });
}
