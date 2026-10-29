import 'package:flutter_test/flutter_test.dart';
import 'package:rakan/features/workout/screens/workout_screen.dart';

void main() {
  group('equipmentMatches', () {
    const equipmentTagToEnum = <String, String>{
      'bodyweight': 'noEquipment',
      'dumbbell': 'dumbbell',
      'dumbbells': 'dumbbell',
      'barbell': 'barbell',
      'bench': 'bench',
      'cable machine': 'machines',
      'machine': 'machines',
      'resistance band': 'resistanceBand',
      'pull-up bar': 'pullUpBar',
      'kettlebell': 'kettlebell',
    };

    test('treats commas as AND requirements', () {
      expect(
        equipmentMatches('dumbbell, bench', ['dumbbell'], equipmentTagToEnum),
        isFalse,
      );
      expect(
        equipmentMatches('dumbbell, bench', ['dumbbell', 'bench'], equipmentTagToEnum),
        isTrue,
      );
    });

    test('treats slash as OR alternatives', () {
      expect(
        equipmentMatches('dumbbell/bench', ['dumbbell'], equipmentTagToEnum),
        isTrue,
      );
      expect(
        equipmentMatches('dumbbell/bench', ['bench'], equipmentTagToEnum),
        isTrue,
      );
      expect(
        equipmentMatches('dumbbell/bench', ['barbell'], equipmentTagToEnum),
        isFalse,
      );
    });
  });

  // V-26 / D-22: the "Use Template" dialog promises 3–4 exercises.
  group('buildTemplateExercises', () {
    test('tops up a short Back pool for dumbbells + bench', () {
      final exercises = buildTemplateExercises(
        muscleGroup: 'Back',
        userEquipment: ['dumbbell', 'bench'],
        userExperience: 'intermediate',
      );
      expect(exercises.length, greaterThanOrEqualTo(3));
      expect(exercises.map((e) => e.name),
          containsAll(['Dumbbell Row', 'Chest-Supported Dumbbell Row']));
      for (final ex in exercises) {
        expect(ex.muscleGroup, 'Back');
        expect(equipmentMatches(ex.equipment, ['dumbbell', 'bench']), isTrue,
            reason: '${ex.name} needs ${ex.equipment}');
      }
      expect(exercises.map((e) => e.name).toSet().length, exercises.length);
    });

    test('a pool with enough matches is unchanged and capped at 4', () {
      final exercises = buildTemplateExercises(
        muscleGroup: 'Core',
        userEquipment: ['noEquipment'],
        userExperience: 'beginner',
      );
      expect(exercises.length, 4);
    });
  });
}
