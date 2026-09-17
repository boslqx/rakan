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
  String? username; // unique @handle, claimed separately (see PublicProfileService)
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
    this.username,
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
      username != null &&
      username!.trim().isNotEmpty &&
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

  /// Parses a list of enum-name strings (as stored by toMap()) back into a Set of EquipmentType enums
  static Set<EquipmentType> equipmentFromNames(List<dynamic>? raw) {
    if (raw == null) return {};
    final result = <EquipmentType>{};
    for (final name in raw) {
      for (final type in EquipmentType.values) {
        if (type.name == name) {
          result.add(type);
          break;
        }
      }
    }
    return result;
  }

  /// Rebuilds an OnboardingData from the profile map toMap() produces (as
  /// stored at users/{uid}/profile/data) — the inverse of toMap(). Used to
  /// pre-fill a regeneration flow (e.g. Reset Plan) with what the user
  /// already answered, instead of starting from a blank OnboardingData.
  factory OnboardingData.fromMap(Map<String, dynamic> map) {
    return OnboardingData(
      name: map['name'] as String?,
      gender: _enumFromName(Gender.values, map['gender']),
      age: (map['age'] as num?)?.toInt(),
      heightCm: (map['heightCm'] as num?)?.toDouble(),
      weightKg: (map['weightKg'] as num?)?.toDouble(),
      isMetric: map['isMetric'] as bool? ?? true,
      activityLevel: _enumFromName(ActivityLevel.values, map['activityLevel']),
      fitnessGoal: _enumFromName(FitnessGoal.values, map['fitnessGoal']),
      experienceLevel:
          _enumFromName(ExperienceLevel.values, map['experienceLevel']),
      sessionDuration:
          _enumFromName(SessionDuration.values, map['sessionDuration']),
      motivation: _enumFromName(Motivation.values, map['motivation']),
      workoutDays: (map['workoutDays'] as List<dynamic>?)
              ?.map((d) => (d as num).toInt())
              .toSet() ??
          {},
      equipment: equipmentFromNames(map['equipment'] as List<dynamic>?),
      focusAreas: _focusAreasFromNames(map['focusAreas'] as List<dynamic>?),
      injuries: _injuriesFromList(map['injuries'] as List<dynamic>?),
    );
  }

  /// Generic "find the enum value whose .name matches this stored string"
  /// lookup — every enum field here is persisted the same way (toMap()
  /// writes `field?.name`), so one helper covers all of them.
  static T? _enumFromName<T extends Enum>(List<T> values, dynamic name) {
    if (name == null) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static Set<FocusArea> _focusAreasFromNames(List<dynamic>? raw) {
    if (raw == null) return {};
    final result = <FocusArea>{};
    for (final name in raw) {
      final match = _enumFromName(FocusArea.values, name);
      if (match != null) result.add(match);
    }
    return result;
  }

  static List<InjuryEntry> _injuriesFromList(List<dynamic>? raw) {
    if (raw == null) return [];
    final result = <InjuryEntry>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final region = _enumFromName(BodyRegion.values, item['region']);
      final label = item['label'] as String?;
      if (region == null || label == null) continue;
      result.add(InjuryEntry(
        region: region,
        label: label,
        isCustom: item['isCustom'] as bool? ?? false,
      ));
    }
    return result;
  }
}