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
}
