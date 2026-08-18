/// One exercise's current personal record 
class WorkoutPrRecord {
  final String exerciseName;
  final double weightKg;
  final int reps;
  final DateTime achievedAt;

  const WorkoutPrRecord({
    required this.exerciseName,
    required this.weightKg,
    required this.reps,
    required this.achievedAt,
  });
}