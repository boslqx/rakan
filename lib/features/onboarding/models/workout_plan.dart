// This represents the complete 7-day workout plan
// Structure is designed to match what FastAPI will return later
enum DayType { workout, rest }

class WorkoutExercise {
  final String name;
  final int sets;
  final int reps;
  final String? equipment;

  const WorkoutExercise({
    required this.name,
    required this.sets,
    required this.reps,
    this.equipment,
  });
}

class WorkoutDay {
  final int dayNumber;           // 1-7
  final String dayName;          
  final DayType type;            // workout or rest
  final String? workoutName;     // PUSH DAY, PULL DAY etc
  final String? focusDescription;// Chest, Shoulders & Triceps focus
  final int? durationMinutes;    // 90
  final List<String> muscleGroups; // ['Chest', 'Triceps', 'Shoulders']
  final List<WorkoutExercise> exercises;

  const WorkoutDay({
    required this.dayNumber,
    required this.dayName,
    required this.type,
    this.workoutName,
    this.focusDescription,
    this.durationMinutes,
    this.muscleGroups = const [],
    this.exercises = const [],
  });
}

class WorkoutPlan {
  final String planName;
  final String planDescription;
  final List<WorkoutDay> days;

  const WorkoutPlan({
    required this.planName,
    required this.planDescription,
    required this.days,
  });
}

// Fake plan generator
// Generates a realistic fake plan based on onboarding data
WorkoutPlan generateFakePlan({
  required String userName,
  required String goal,
  required String experience,
  required Set<int> workoutDays,
}) {
  // Map day numbers to names
  const dayNames = {
    1: 'MONDAY',
    2: 'TUESDAY',
    3: 'WEDNESDAY',
    4: 'THURSDAY',
    5: 'FRIDAY',
    6: 'SATURDAY',
    7: 'SUNDAY',
  };

  // Predefined workout templates
  const workoutTemplates = [
    {
      'name': 'PUSH DAY',
      'focus': 'Chest, Shoulders & Triceps focus',
      'muscles': ['Chest', 'Shoulders', 'Triceps'],
      'duration': 75,
      'exercises': [
        {'name': 'Bench Press', 'sets': 4, 'reps': 8},
        {'name': 'Overhead Press', 'sets': 3, 'reps': 10},
        {'name': 'Incline Dumbbell Press', 'sets': 3, 'reps': 12},
        {'name': 'Lateral Raises', 'sets': 3, 'reps': 15},
        {'name': 'Tricep Pushdown', 'sets': 3, 'reps': 12},
        {'name': 'Dips', 'sets': 3, 'reps': 10},
      ],
    },
    {
      'name': 'PULL DAY',
      'focus': 'Back & Biceps specialization',
      'muscles': ['Back', 'Biceps', 'Forearms'],
      'duration': 70,
      'exercises': [
        {'name': 'Deadlift', 'sets': 4, 'reps': 6},
        {'name': 'Pull Ups', 'sets': 4, 'reps': 8},
        {'name': 'Barbell Row', 'sets': 3, 'reps': 10},
        {'name': 'Cable Row', 'sets': 3, 'reps': 12},
        {'name': 'Bicep Curls', 'sets': 3, 'reps': 12},
        {'name': 'Hammer Curls', 'sets': 3, 'reps': 12},
      ],
    },
    {
      'name': 'LEGS & CORE',
      'focus': 'Posterior chain & abdominal stability',
      'muscles': ['Quads', 'Hamstrings', 'Glutes', 'Core'],
      'duration': 90,
      'exercises': [
        {'name': 'Squat', 'sets': 4, 'reps': 8},
        {'name': 'Romanian Deadlift', 'sets': 3, 'reps': 10},
        {'name': 'Leg Press', 'sets': 3, 'reps': 12},
        {'name': 'Leg Curl', 'sets': 3, 'reps': 12},
        {'name': 'Calf Raises', 'sets': 4, 'reps': 15},
        {'name': 'Plank', 'sets': 3, 'reps': 60},
      ],
    },
    {
      'name': 'UPPER BODY',
      'focus': 'High volume saturation work',
      'muscles': ['Chest', 'Back', 'Shoulders', 'Arms'],
      'duration': 80,
      'exercises': [
        {'name': 'Incline Press', 'sets': 4, 'reps': 10},
        {'name': 'Cable Flyes', 'sets': 3, 'reps': 12},
        {'name': 'Lat Pulldown', 'sets': 4, 'reps': 10},
        {'name': 'Face Pulls', 'sets': 3, 'reps': 15},
        {'name': 'Skull Crushers', 'sets': 3, 'reps': 12},
        {'name': 'Preacher Curls', 'sets': 3, 'reps': 12},
      ],
    },
    {
      'name': 'LOWER BODY POWER',
      'focus': 'Explosive squat & deadlift variations',
      'muscles': ['Quads', 'Glutes', 'Hamstrings', 'Calves'],
      'duration': 85,
      'exercises': [
        {'name': 'Front Squat', 'sets': 4, 'reps': 6},
        {'name': 'Hip Thrust', 'sets': 4, 'reps': 10},
        {'name': 'Bulgarian Split Squat', 'sets': 3, 'reps': 10},
        {'name': 'Leg Extension', 'sets': 3, 'reps': 15},
        {'name': 'Nordic Curl', 'sets': 3, 'reps': 8},
        {'name': 'Standing Calf Raise', 'sets': 4, 'reps': 15},
      ],
    },
  ];

  final List<WorkoutDay> days = [];
  int templateIndex = 0;

  for (int i = 1; i <= 7; i++) {
    final dayName = dayNames[i]!;
    final isWorkoutDay = workoutDays.contains(i);

    if (isWorkoutDay && templateIndex < workoutTemplates.length) {
      final template = workoutTemplates[templateIndex];
      templateIndex++;

      days.add(WorkoutDay(
        dayNumber: i,
        dayName: dayName,
        type: DayType.workout,
        workoutName: template['name'] as String,
        focusDescription: template['focus'] as String,
        durationMinutes: template['duration'] as int,
        muscleGroups: List<String>.from(
          template['muscles'] as List,
        ),
        exercises: (template['exercises'] as List)
            .map((e) => WorkoutExercise(
                  name: e['name'] as String,
                  sets: e['sets'] as int,
                  reps: e['reps'] as int,
                ))
            .toList(),
      ));
    } else {
      days.add(WorkoutDay(
        dayNumber: i,
        dayName: dayName,
        type: DayType.rest,
        workoutName: 'SYSTEM RESET',
        focusDescription: 'Full physiological rest period',
        durationMinutes: null,
        muscleGroups: [],
        exercises: [],
      ));
    }
  }

  return WorkoutPlan(
    planName: '7-DAY EVOLUTION PLAN',
    planDescription:
        'Your performance metrics have been synthesized. '
        'This protocol is optimized for explosive hypertrophy '
        'and metabolic efficiency.',
    days: days,
  );
}