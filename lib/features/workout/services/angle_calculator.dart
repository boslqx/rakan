import 'dart:math' as math;

// A landmark is a point in 3D space from MediaPipe
// x, y are normalized (0.0 to 1.0) relative to image dimensions
class Landmark {
  final double x;
  final double y;
  final double z;
  final double visibility;

  const Landmark({
    required this.x,
    required this.y,
    required this.z,
    required this.visibility,
  });

  factory Landmark.fromMap(Map<String, dynamic> map) {
    return Landmark(
      x: (map['x'] as num).toDouble(),
      y: (map['y'] as num).toDouble(),
      z: (map['z'] as num).toDouble(),
      visibility: (map['visibility'] as num).toDouble(),
    );
  }
}

// MediaPipe Pose landmark indices (all 33 landmarks)
class PoseLandmarkIndex {
  static const int nose = 0;
  static const int leftShoulder = 11;
  static const int rightShoulder = 12;
  static const int leftElbow = 13;
  static const int rightElbow = 14;
  static const int leftWrist = 15;
  static const int rightWrist = 16;
  static const int leftHip = 23;
  static const int rightHip = 24;
  static const int leftKnee = 25;
  static const int rightKnee = 26;
  static const int leftAnkle = 27;
  static const int rightAnkle = 28;
}

class AngleCalculator {
  // Calculate the angle at point B, formed by points A-B-C
  // The angle between two vectors = arccos(dot(BA, BC) / (|BA| * |BC|))
  static double calculateAngle(Landmark a, Landmark b, Landmark c) {
    // Vector from B to A
    final baX = a.x - b.x;
    final baY = a.y - b.y;

    // Vector from B to C
    final bcX = c.x - b.x;
    final bcY = c.y - b.y;

    // Dot product
    final dotProduct = (baX * bcX) + (baY * bcY);

    // Magnitudes
    final magnitudeBA = math.sqrt(baX * baX + baY * baY);
    final magnitudeBC = math.sqrt(bcX * bcX + bcY * bcY);

    // Avoid division by zero
    if (magnitudeBA == 0 || magnitudeBC == 0) return 0;

    // Clamp to [-1, 1] to avoid NaN from floating point errors
    final cosAngle = (dotProduct / (magnitudeBA * magnitudeBC)).clamp(-1.0, 1.0);

    // Convert radians to degrees
    return math.acos(cosAngle) * 180 / math.pi;
  }
}

// Exercise Analysis Results
class PostureResult {
  final bool isCorrect;
  final String feedback;       
  final String phase;         
  final double? keyAngle;      
  final bool countRep;         

  const PostureResult({
    required this.isCorrect,
    required this.feedback,
    required this.phase,
    this.keyAngle,
    this.countRep = false,
  });
}

// Squat Analyser
class SquatAnalyser {
  // 80°-100° at the bottom of a squat for safe, effective depth.
  static const double _bottomAngleMin = 80.0;
  static const double _bottomAngleMax = 100.0;
  static const double _standingAngleMin = 160.0; // nearly straight leg = standing

  // Rep counting state machine
  String _phase = 'standing';
  int repCount = 0;

  PostureResult analyse(List<Landmark> landmarks) {
    if (landmarks.length < 29) {
      return const PostureResult(
        isCorrect: false,
        feedback: 'Position yourself so your full body is visible',
        phase: 'unknown',
      );
    }

    final leftHip = landmarks[PoseLandmarkIndex.leftHip];
    final leftKnee = landmarks[PoseLandmarkIndex.leftKnee];
    final leftAnkle = landmarks[PoseLandmarkIndex.leftAnkle];
    final rightHip = landmarks[PoseLandmarkIndex.rightHip];
    final rightKnee = landmarks[PoseLandmarkIndex.rightKnee];
    final rightAnkle = landmarks[PoseLandmarkIndex.rightAnkle];

    // Use average of both knees for robustness
    final leftKneeAngle = AngleCalculator.calculateAngle(leftHip, leftKnee, leftAnkle);
    final rightKneeAngle = AngleCalculator.calculateAngle(rightHip, rightKnee, rightAnkle);
    final kneeAngle = (leftKneeAngle + rightKneeAngle) / 2;

    // Check visibility — if knee landmarks not visible, can't analyse
    if (leftKnee.visibility < 0.5 || rightKnee.visibility < 0.5) {
      return PostureResult(
        isCorrect: false,
        feedback: 'Step back — full legs must be visible',
        phase: _phase,
        keyAngle: kneeAngle,
      );
    }

    bool countRep = false;

    // State machine transitions
    if (kneeAngle > _standingAngleMin) {
      if (_phase == 'coming_up') {
        // Completed a full squat cycle
        repCount++;
        countRep = true;
      }
      _phase = 'standing';
    } else if (kneeAngle < _bottomAngleMax + 20 && _phase == 'standing') {
      _phase = 'going_down';
    } else if (kneeAngle <= _bottomAngleMax && _phase == 'going_down') {
      _phase = 'bottom';
    } else if (kneeAngle > _bottomAngleMax && _phase == 'bottom') {
      _phase = 'coming_up';
    }

    // Generate feedback based on current phase and angle
    String feedback;
    bool isCorrect;

    if (_phase == 'standing') {
      feedback = countRep
          ? 'Rep ${repCount} complete! Lower down slowly'
          : 'Stand straight, feet shoulder-width apart';
      isCorrect = true;
    } else if (_phase == 'going_down') {
      feedback = 'Keep going down — chest up, knees over toes';
      isCorrect = true;
    } else if (_phase == 'bottom') {
      if (kneeAngle < _bottomAngleMin) {
        feedback = 'Too deep — come up slightly (${kneeAngle.toStringAsFixed(0)}°)';
        isCorrect = false;
      } else {
        feedback = 'Good depth! Push through heels to stand';
        isCorrect = true;
      }
    } else {
      // coming_up
      feedback = 'Drive up — keep your core tight';
      isCorrect = true;
    }

    return PostureResult(
      isCorrect: isCorrect,
      feedback: feedback,
      phase: _phase,
      keyAngle: kneeAngle,
      countRep: countRep,
    );
  }

  void reset() {
    _phase = 'standing';
    repCount = 0;
  }
}

// Push-up Analyser
class PushUpAnalyser {
  // ensures full range of motion and pectoral activation.
  static const double _bottomAngleMax = 100.0;  
  static const double _topAngleMin = 150.0;     

  String _phase = 'up';
  int repCount = 0;

  PostureResult analyse(List<Landmark> landmarks) {
    if (landmarks.length < 17) {
      return const PostureResult(
        isCorrect: false,
        feedback: 'Position yourself so your upper body is visible',
        phase: 'unknown',
      );
    }

    final leftShoulder = landmarks[PoseLandmarkIndex.leftShoulder];
    final leftElbow = landmarks[PoseLandmarkIndex.leftElbow];
    final leftWrist = landmarks[PoseLandmarkIndex.leftWrist];
    final rightShoulder = landmarks[PoseLandmarkIndex.rightShoulder];
    final rightElbow = landmarks[PoseLandmarkIndex.rightElbow];
    final rightWrist = landmarks[PoseLandmarkIndex.rightWrist];

    final leftElbowAngle = AngleCalculator.calculateAngle(leftShoulder, leftElbow, leftWrist);
    final rightElbowAngle = AngleCalculator.calculateAngle(rightShoulder, rightElbow, rightWrist);
    final elbowAngle = (leftElbowAngle + rightElbowAngle) / 2;

    if (leftElbow.visibility < 0.5 || rightElbow.visibility < 0.5) {
      return PostureResult(
        isCorrect: false,
        feedback: 'Arms not visible — face the camera sideways',
        phase: _phase,
        keyAngle: elbowAngle,
      );
    }

    bool countRep = false;

    if (elbowAngle > _topAngleMin) {
      if (_phase == 'coming_up') {
        repCount++;
        countRep = true;
      }
      _phase = 'up';
    } else if (elbowAngle <= _topAngleMin && elbowAngle > _bottomAngleMax && _phase == 'up') {
      _phase = 'going_down';
    } else if (elbowAngle <= _bottomAngleMax && _phase == 'going_down') {
      _phase = 'bottom';
    } else if (elbowAngle > _bottomAngleMax && _phase == 'bottom') {
      _phase = 'coming_up';
    }

    String feedback;
    bool isCorrect;

    if (_phase == 'up') {
      feedback = countRep
          ? 'Rep $repCount complete! Lower slowly'
          : 'Arms extended — lower your chest to the ground';
      isCorrect = true;
    } else if (_phase == 'going_down') {
      feedback = 'Good — keep your body straight like a plank';
      isCorrect = true;
    } else if (_phase == 'bottom') {
      if (elbowAngle > _bottomAngleMax) {
        feedback = 'Lower more — chest should nearly touch ground';
        isCorrect = false;
      } else {
        feedback = 'Good depth! Push back up explosively';
        isCorrect = true;
      }
    } else {
      feedback = 'Push up — lock out your elbows at the top';
      isCorrect = true;
    }

    return PostureResult(
      isCorrect: isCorrect,
      feedback: feedback,
      phase: _phase,
      keyAngle: elbowAngle,
      countRep: countRep,
    );
  }

  void reset() {
    _phase = 'up';
    repCount = 0;
  }
}

// Shoulder Press Analyser
class ShoulderPressAnalyser {
  static const double _bottomAngleMax = 100.0;  // start position
  static const double _topAngleMin = 160.0;      // arms extended overhead

  String _phase = 'bottom';
  int repCount = 0;

  PostureResult analyse(List<Landmark> landmarks) {
    if (landmarks.length < 17) {
      return const PostureResult(
        isCorrect: false,
        feedback: 'Position yourself so your upper body is visible',
        phase: 'unknown',
      );
    }

    final leftShoulder = landmarks[PoseLandmarkIndex.leftShoulder];
    final leftElbow = landmarks[PoseLandmarkIndex.leftElbow];
    final leftWrist = landmarks[PoseLandmarkIndex.leftWrist];
    final rightShoulder = landmarks[PoseLandmarkIndex.rightShoulder];
    final rightElbow = landmarks[PoseLandmarkIndex.rightElbow];
    final rightWrist = landmarks[PoseLandmarkIndex.rightWrist];

    final leftElbowAngle = AngleCalculator.calculateAngle(leftShoulder, leftElbow, leftWrist);
    final rightElbowAngle = AngleCalculator.calculateAngle(rightShoulder, rightElbow, rightWrist);
    final elbowAngle = (leftElbowAngle + rightElbowAngle) / 2;

    bool countRep = false;

    if (elbowAngle >= _topAngleMin) {
      if (_phase == 'pressing') {
        _phase = 'top';
      }
    } else if (elbowAngle < _topAngleMin && _phase == 'top') {
      _phase = 'lowering';
    } else if (elbowAngle <= _bottomAngleMax && _phase == 'lowering') {
      repCount++;
      countRep = true;
      _phase = 'bottom';
    } else if (elbowAngle > _bottomAngleMax && _phase == 'bottom') {
      _phase = 'pressing';
    }

    String feedback;
    bool isCorrect;

    if (_phase == 'bottom') {
      feedback = countRep
          ? 'Rep $repCount complete! Press again'
          : 'Elbows at shoulder height — press overhead';
      isCorrect = true;
    } else if (_phase == 'pressing') {
      feedback = 'Press overhead — fully extend your arms';
      isCorrect = true;
    } else if (_phase == 'top') {
      if (elbowAngle < _topAngleMin) {
        feedback = 'Extend fully — lock out at the top';
        isCorrect = false;
      } else {
        feedback = 'Full extension! Lower back with control';
        isCorrect = true;
      }
    } else {
      feedback = 'Lower slowly — control the weight down';
      isCorrect = true;
    }

    return PostureResult(
      isCorrect: isCorrect,
      feedback: feedback,
      phase: _phase,
      keyAngle: elbowAngle,
      countRep: countRep,
    );
  }

  void reset() {
    _phase = 'bottom';
    repCount = 0;
  }
}

// Exercise Analyser Factory 
class ExerciseAnalyserFactory {
  static dynamic getAnalyser(String exerciseName) {
    final name = exerciseName.toLowerCase();
    if (name.contains('squat')) return SquatAnalyser();
    if (name.contains('push') || name.contains('pushup')) return PushUpAnalyser();
    if (name.contains('press') || name.contains('shoulder')) return ShoulderPressAnalyser();
    // Default to squat for unknown exercises
    return SquatAnalyser();
  }

  // Returns the expected rep target based on exercise name
  static String getInstructions(String exerciseName) {
    final name = exerciseName.toLowerCase();
    if (name.contains('squat')) {
      return 'Stand with feet shoulder-width apart. Face sideways to the camera for best detection.';
    }
    if (name.contains('push')) {
      return 'Get into push-up position. Face sideways to the camera.';
    }
    if (name.contains('press')) {
      return 'Sit or stand upright. Face the camera directly.';
    }
    return 'Position yourself so your full body is visible to the camera.';
  }
}