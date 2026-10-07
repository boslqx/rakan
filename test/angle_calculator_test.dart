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

  group('AngleCalculator.toPixelSpace', () {
    test('removes aspect-ratio distortion on a 640x480 frame', () {
      // A true 45-degree angle in pixels: B at the origin, A along +x,
      // C along the diagonal (100px, 100px).
      const w = 640, h = 480;
      Landmark norm(double px, double py) =>
          Landmark(x: px / w, y: py / h, z: 0, visibility: 1);
      final a = norm(300, 200);
      final b = norm(200, 200);
      final c = norm(300, 300);

      final skewed = AngleCalculator.calculateAngle(a, b, c);
      final fixed = AngleCalculator.toPixelSpace(
        [a, b, c],
        frameWidth: w,
        frameHeight: h,
      );
      final corrected =
          AngleCalculator.calculateAngle(fixed[0], fixed[1], fixed[2]);

      expect(corrected, closeTo(45.0, 0.001));
      // Normalized coordinates read ~53 degrees for the same pose.
      expect((skewed - 45.0).abs(), greaterThan(5));
    });

    test('leaves landmarks untouched for an invalid frame size', () {
      const l = Landmark(x: 0.5, y: 0.5, z: 0, visibility: 1);
      final out =
          AngleCalculator.toPixelSpace([l], frameWidth: 0, frameHeight: 480);
      expect(out.first.x, 0.5);
    });
  });

  group('SquatAnalyser side-on view', () {
    test('analyses using the one visible leg instead of refusing', () {
      final landmarks = List<Landmark>.generate(
        33,
        (_) => const Landmark(x: 0, y: 0, z: 0, visibility: 0.1),
      );
      // Left leg fully visible and straight (standing); right leg hidden.
      landmarks[PoseLandmarkIndex.leftHip] =
          const Landmark(x: 100, y: 100, z: 0, visibility: 0.9);
      landmarks[PoseLandmarkIndex.leftKnee] =
          const Landmark(x: 100, y: 200, z: 0, visibility: 0.9);
      landmarks[PoseLandmarkIndex.leftAnkle] =
          const Landmark(x: 100, y: 300, z: 0, visibility: 0.9);

      final result = SquatAnalyser().analyse(landmarks);

      expect(result.phase, 'standing');
      expect(result.keyAngle, closeTo(180.0, 0.001));
    });
  });
}
