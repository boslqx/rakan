import '../data/exercise_data.dart';

/// Automated-mode timer state machine, shared by the Manual list's inline
enum SetPhase { idle, working, resting }

class SetSessionState {
  int reps;
  double weightKg;

  SetSessionState({required this.reps, required this.weightKg});
}

/// Mutable state for a single exercise within the active workout session.
class ExerciseSessionState {
  final String exerciseId;
  final String exerciseName;
  final String muscleGroup;
  final int restSeconds;

  /// Resolved static metadata 
  final ExerciseData? data;

  final List<SetSessionState> sets;
  final Set<int> completedSets = {};
  int rpe = 5;
  bool weightManuallySet = false;

  // Guided-mode timer/camera state (used by AutoLogScreen)
  SetPhase phase = SetPhase.idle;
  int timerSecondsLeft = 0;

  ExerciseSessionState({
    required this.exerciseId,
    required this.exerciseName,
    required this.muscleGroup,
    required this.restSeconds,
    required this.sets,
    this.data,
  });

  bool get isFullyComplete => completedSets.length == sets.length;

  /// Whether this exercise has any added-load variant
  bool get tracksWeight => data?.tracksWeight ?? true;

  /// Index of the first not-yet-completed set. Equals sets.length once
  int get currentSetIndex {
    for (int i = 0; i < sets.length; i++) {
      if (!completedSets.contains(i)) return i;
    }
    return sets.length;
  }
}