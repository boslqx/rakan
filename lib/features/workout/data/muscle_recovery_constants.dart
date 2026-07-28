import 'exercise_data.dart';

/// Maps the granular secondary-muscle tags used in `ExerciseData.secondaryMuscles`
/// down to the app's existing 7 broad `MuscleGroups` categories.
const Map<String, String> kGranularToBroadMuscleGroup = {
  // Chest
  'Chest': MuscleGroups.chest,
  'Inner Chest': MuscleGroups.chest,
  'Upper Chest': MuscleGroups.chest,

  // Back
  'Lats': MuscleGroups.back,
  'Upper Back': MuscleGroups.back,
  'Lower Back': MuscleGroups.back,
  'Trapezius': MuscleGroups.back,
  'Serratus Anterior': MuscleGroups.back,

  // Shoulders
  'Shoulders': MuscleGroups.shoulders,
  'Anterior Deltoids': MuscleGroups.shoulders,
  'Front Deltoids': MuscleGroups.shoulders,
  'Rear Deltoids': MuscleGroups.shoulders,
  'Rotator Cuff': MuscleGroups.shoulders,

  // Arms
  'Biceps': MuscleGroups.arms,
  'Triceps': MuscleGroups.arms,
  'Brachialis': MuscleGroups.arms,
  'Forearms': MuscleGroups.arms,
  'Wrists': MuscleGroups.arms,

  // Legs
  'Legs': MuscleGroups.legs,
  'Quads': MuscleGroups.legs,
  'Hamstrings': MuscleGroups.legs,
  'Calves': MuscleGroups.legs,
  'Hip Flexors': MuscleGroups.legs,

  // Glutes
  'Glutes': MuscleGroups.glutes,
  'Hip Abductors': MuscleGroups.glutes,

  // Core
  'Core': MuscleGroups.core,
  'Obliques': MuscleGroups.core,
};

/// Weekly Maximum Recoverable Volume (working sets/week) per broad muscle
const Map<String, int> kWeeklyMRVByMuscleGroup = {
  // Large muscle groups
  MuscleGroups.back: 20,
  MuscleGroups.chest: 20,
  MuscleGroups.legs: 20,
  MuscleGroups.glutes: 20,

  // Medium muscle groups
  MuscleGroups.shoulders: 16,
  MuscleGroups.arms: 16,

  // Small muscle groups
  MuscleGroups.core: 12,
};

/// Fallback MRV used only if a muscle group somehow isn't in the table
const int kFallbackWeeklyMRV = 16;

/// A secondary mover's set contributes this fraction of a full set's fatigue
const double kSecondaryMuscleWeight = 0.5;

/// fatigue score
const double kRestDayFatigueThreshold = 0.5;
const int kDefaultRestDays = 2;
const int kElevatedRestDays = 3;