import 'exercise_data.dart';

/// Template exercises offered when a rest day is turned into a workout
/// ("Start with a template?"). Kept out of the screen so the selection can
/// be unit-tested.

const Map<String, int> _kDifficultyRank = {
  'Beginner': 0,
  'Intermediate': 1,
  'Advanced': 2,
};

/// The template dialog promises at least this many exercises.
const int kMinTemplateExercises = 3;

/// Absolute distance between exercise difficulty and user experience level.
int _difficultyDistance(String exerciseDifficulty, String userExperience) {
  final exRank = _kDifficultyRank[exerciseDifficulty] ?? 1;
  final normalized = userExperience.isEmpty
      ? 'beginner'
      : userExperience[0].toUpperCase() +
            userExperience.substring(1).toLowerCase();
  final userRank = _kDifficultyRank[normalized] ?? 0;
  return (exRank - userRank).abs();
}

/// Template exercise pools per muscle group (exercise names from kExercises).
/// Note: some exercise `equipment` strings in exercise_data.dart use '/'
/// to mean "OR" between alternative setups (e.g. 'Bodyweight / Dumbbells, Bench').
/// See equipmentMatches() for how this is parsed.
const Map<String, List<String>> _kMuscleGroupTemplatePools = {
  'Chest': [
    'Push-Up',
    'Dumbbell Bench Press',
    'Dumbbell Flye',
    'Incline Push-Up',
    'Incline Dumbbell Press',
    'Machine Chest Press',
    'Pec Deck Flye',
    'Resistance Band Chest Press',
    'Resistance Band Chest Flye',
    'Dumbbell Floor Press',
  ],
  'Back': [
    'Inverted Row',
    'Dumbbell Row',
    'Lat Pulldown',
    'Seated Cable Row',
    'Pull-Up',
    'Chin-Up',
    'Resistance Band Row',
    'Resistance Band Lat Pulldown',
    'Chest-Supported Dumbbell Row',
    'Single-Arm Cable Row',
  ],
  'Shoulders': [
    'Pike Push-Up',
    'Dumbbell Shoulder Press',
    'Dumbbell Lateral Raise',
    'Dumbbell Front Raise',
    'Dumbbell Rear Delt Flye',
    'Arnold Press',
    'Seated Dumbbell Shoulder Press',
    'Machine Shoulder Press',
    'Resistance Band Lateral Raise',
    'Resistance Band Face Pull',
  ],
  'Arms': [
    'Dumbbell Bicep Curl',
    'Dumbbell Hammer Curl',
    'Dumbbell Tricep Overhead Extension',
    'Tricep Dip',
    'Resistance Band Bicep Curl',
    'Resistance Band Tricep Pushdown',
    'Bench Dip',
    'Dumbbell Concentration Curl',
    'Incline Dumbbell Curl',
    'Dumbbell Skull Crusher',
  ],
  'Legs': [
    'Bodyweight Squat',
    'Reverse Lunge',
    'Dumbbell Goblet Squat',
    'Dumbbell Romanian Deadlift',
    'Split Squat',
    'Bulgarian Split Squat',
    'Step-Up',
    'Wall Sit',
    'Leg Press',
    'Leg Curl',
  ],
  'Glutes': [
    'Glute Bridge',
    'Hip Thrust',
    'Single-Leg Glute Bridge',
    'Frog Pump',
    'Fire Hydrant',
    'Donkey Kick',
    'Dumbbell Hip Thrust',
    'Dumbbell Step-Up',
    'Cable Glute Kickback',
    'Resistance Band Glute Bridge',
  ],
  'Core': [
    'Plank',
    'Crunch',
    'Leg Raise',
    'Mountain Climber',
    'Russian Twist',
    'Dead Bug',
    'Bird Dog',
    'Bicycle Crunch',
    'Flutter Kick',
    'Side Plank',
  ],
};

/// Builds a list of template exercises for the given muscle group,
/// filtered by user's equipment and sorted by difficulty proximity
/// to the user's experience level.
///
/// If fewer than [kMinTemplateExercises] pool exercises fit the user's
/// equipment, it tops up from the whole library (same muscle group,
/// equipment that matches, closest difficulty first), so the dialog's
/// "3–4 exercises" holds whenever the library allows it (D-22 / V-26).
List<ExerciseData> buildTemplateExercises({
  required String muscleGroup,
  required List<String> userEquipment,
  required String userExperience,
  int maxExercises = 4,
}) {
  final pool = _kMuscleGroupTemplatePools[muscleGroup] ?? [];

  int byDifficulty(ExerciseData a, ExerciseData b) =>
      _difficultyDistance(a.difficulty, userExperience)
          .compareTo(_difficultyDistance(b.difficulty, userExperience));

  final resolved = pool
      .map((name) => findExerciseByName(name))
      .whereType<ExerciseData>()
      .where((ex) => equipmentMatches(ex.equipment, userEquipment))
      .toList();

  resolved.sort(byDifficulty);

  if (resolved.length < kMinTemplateExercises) {
    final chosen = resolved.map((ex) => ex.name).toSet();
    final extra = kExercises
        .where((ex) =>
            ex.muscleGroup == muscleGroup &&
            !chosen.contains(ex.name) &&
            equipmentMatches(ex.equipment, userEquipment))
        .toList()
      ..sort(byDifficulty);
    resolved.addAll(extra.take(kMinTemplateExercises - resolved.length));
  }

  return resolved.take(maxExercises).toList();
}
