// This file defines one objects that travels trhough all 6 onboarding screens

enum Gender { male, female, nonBinary }
enum FitnessGoal { muscleGain, weightLoss, endurance, flexibility}
enum ExperienceLevel { beginner, intermediate, advanced }
enum EquipmentType {
  fullGym,       
  barbell,        
  dumbbell,       
  kettlebell,    
  resistanceBand, 
  pullUpBar,     
  bench,          
  machines,       
  noEquipment,    
}
enum BodyRegion {
  head,
  neck,
  leftShoulder,
  rightShoulder,
  chest,
  upperBack,
  leftArm,
  rightArm,
  core,
  lowerBack,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
}
enum ActivityLevel {
  sedentary,        
  lightlyActive,   
  moderatelyActive, 
  veryActive,       
  athlete, 
}        

enum SessionDuration {
  thirtyMin,        
  fortyFiveMin,    
  sixtyMin,        
  ninetyPlusMin,   
}

enum Motivation {
  lookBetter,
  buildStrength,
  improveHealth,
  boostEnergy,
  reduceStress,
  athleticPerformance,
}

enum FocusArea {
  chest,
  back,
  arms,
  shoulders,
  abs,
  legs,
  glutes,
  fullBody,
}

// Each injury has a body region + specific label and optional description
class InjuryEntry {
  final BodyRegion region;
  final String label;     
  final bool isCustom;     // true if user typed it themselves

  const InjuryEntry({
    required this.region,
    required this.label,
    this.isCustom = false,
  });
}

// The main data object, one instance created at splash, pass through all steps
class OnboardingData {
  // Step 1: Personal Bio
  String? name;
  Gender? gender;
  int? age;
  double? heightCm;
  double? weightKg;
  bool isMetric; // Track which measuring system user prefers
  ActivityLevel? activityLevel;

  // Step 2: Fitness Goals
  FitnessGoal? fitnessGoal;

  // Step 3: Experience
  ExperienceLevel? experienceLevel;

  // Step 4: Workout Preferences
  Set<int> workoutDays;
  SessionDuration? sessionDuration;

  // Step 5: Environment
  Set<EquipmentType> equipment;
  
  // Step 6: Motivation
  Motivation? motivation;

  // Step 7: Focus Areas
  Set<FocusArea> focusAreas;

  // Step 8: Injuries
  List<InjuryEntry> injuries;

  OnboardingData({
    this.name,
    this.gender,
    this.age,
    this.heightCm,
    this.weightKg,
    this.isMetric = true,   // default to metric
    this.fitnessGoal,
    this.experienceLevel,
    this.activityLevel,
    this.sessionDuration,
    this.motivation,
    Set<int>? workoutDays,
    Set<EquipmentType>? equipment,
    List<InjuryEntry>? injuries,
    Set<FocusArea>? focusAreas,
  })  : workoutDays = workoutDays ?? {},
        equipment = equipment ?? {},
        injuries = injuries ?? [],
        focusAreas = focusAreas ?? {};
      

  // Height conversion
  double? get heightInFeet =>
      heightCm != null ? heightCm! / 30.48 : null;

  double? get heightInInches =>
      heightCm != null ? (heightCm! / 2.54) % 12 : null;

  void setHeightFromImperial(int feet, double inches) {
    heightCm = (feet * 30.48) + (inches * 2.54);
  }

  // Weight conversion
  double? get weightInLbs =>
      weightKg != null ? weightKg! * 2.20462 : null;

  void setWeightFromLbs(double lbs) {
    weightKg = lbs / 2.20462;
  }

  // Step validation
  bool get isStep1Valid =>
      name != null &&
      name!.trim().isNotEmpty &&
      gender != null &&
      age != null &&
      heightCm != null &&
      weightKg != null &&
      activityLevel != null;

  bool get isStep2Valid => fitnessGoal != null;

  bool get isStep3Valid => experienceLevel != null;

  bool get isStep4Valid =>
    workoutDays.isNotEmpty &&
    sessionDuration != null; 

  bool get isStep5Valid => equipment.isNotEmpty;

  bool get isStep6Valid => motivation != null;
  bool get isStep7Valid => focusAreas.isNotEmpty;

  // Step 8 valid always true
  bool get isStep8Valid => true;

  // Debug helper
  @override
  String toString() {
    return '''
OnboardingData:
  name: $name
  gender: $gender
  age: $age
  heightCm: $heightCm
  weightKg: $weightKg
  isMetric: $isMetric
  fitnessGoal: $fitnessGoal
  experienceLevel: $experienceLevel
  workoutDays: $workoutDays
  equipment: $equipment
  activityLevel: $activityLevel
  sessionDuration: $sessionDuration
  motivation: $motivation
  focusAreas: $focusAreas
  injuries: ${injuries.map((i) => i.label).toList()}
''';
  }

  // Converts OnboardingData to a plain Map for Firestore storage
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'gender': gender?.name,               
      'age': age,
      'heightCm': heightCm,
      'weightKg': weightKg,
      'isMetric': isMetric,
      'activityLevel': activityLevel?.name, 
      'fitnessGoal': fitnessGoal?.name,
      'experienceLevel': experienceLevel?.name,
      'workoutDays': workoutDays.toList(),  
      'sessionDuration': sessionDuration?.name,
      'equipment': equipment.map((e) => e.name).toList(), 
      'motivation': motivation?.name,
      'focusAreas': focusAreas.map((f) => f.name).toList(),
      'injuries': injuries.map((i) => {                   
        'region': i.region.name,
        'label': i.label,
        'isCustom': i.isCustom,
      }).toList(),
      'onboardingCompleted': true, 
    };
  }
}