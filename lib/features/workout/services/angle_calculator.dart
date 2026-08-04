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

// Shared interface implemented by every exercise analyser. Calling code
// (e.g. PoseDetectionScreen) programs against this interface instead of
// checking concrete types with `is`/`as` — adding a 7th, 8th... exercise
// analyser in future never requires touching the dispatch code again.
abstract class PostureAnalyser {
  PostureResult analyse(List<Landmark> landmarks);
  int get repCount;
  void reset();
}

// Squat Analyser
class SquatAnalyser implements PostureAnalyser {
  // 80°-100° at the bottom of a squat for safe, effective depth.
  static const double _bottomAngleMin = 80.0;
  static const double _bottomAngleMax = 100.0;
  static const double _standingAngleMin = 160.0; // nearly straight leg = standing

  // _phase drives feedback text only — NOT rep counting (see _hasReachedBottom below)
  String _phase = 'standing';

  // Hysteresis flag: true once the angle has crossed into "bottom" territory
  // since the last counted rep. Rep counting only cares whether this flag
  // was set before the angle returns to standing — it doesn't require every
  // intermediate phase to have been visited on its own frame.
  bool _hasReachedBottom = false;

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

    // --- Rep counting: hysteresis-based, order-independent ---
    if (kneeAngle <= _bottomAngleMax) {
      _hasReachedBottom = true;
    }
    if (kneeAngle > _standingAngleMin && _hasReachedBottom) {
      repCount++;
      countRep = true;
      _hasReachedBottom = false;
    }

    // --- Phase: used only for feedback text, not for counting ---
    if (kneeAngle > _standingAngleMin) {
      _phase = 'standing';
    } else if (kneeAngle <= _bottomAngleMax) {
      _phase = 'bottom';
    } else if (_hasReachedBottom) {
      _phase = 'coming_up';
    } else {
      _phase = 'going_down';
    }

    String feedback;
    bool isCorrect;

    if (_phase == 'standing') {
      feedback = countRep
          ? 'Rep $repCount complete! Lower down slowly'
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
    _hasReachedBottom = false;
    repCount = 0;
  }
}

// Push-up Analyser
class PushUpAnalyser implements PostureAnalyser {
  static const double _bottomAngleMax = 110.0;
  static const double _topAngleMin = 145.0;

  String _phase = 'up';
  bool _hasReachedBottom = false;
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

    if (elbowAngle <= _bottomAngleMax) {
      _hasReachedBottom = true;
    }
    if (elbowAngle > _topAngleMin && _hasReachedBottom) {
      repCount++;
      countRep = true;
      _hasReachedBottom = false;
    }

    if (elbowAngle > _topAngleMin) {
      _phase = 'up';
    } else if (elbowAngle <= _bottomAngleMax) {
      _phase = 'bottom';
    } else if (_hasReachedBottom) {
      _phase = 'coming_up';
    } else {
      _phase = 'going_down';
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
    _hasReachedBottom = false;
    repCount = 0;
  }
}

// Shoulder Press Analyser
class ShoulderPressAnalyser implements PostureAnalyser {
  static const double _bottomAngleMax = 100.0;
  static const double _topAngleMin = 160.0;

  String _phase = 'bottom';
  bool _hasReachedTop = false;
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
      _hasReachedTop = true;
    }
    if (elbowAngle <= _bottomAngleMax && _hasReachedTop) {
      repCount++;
      countRep = true;
      _hasReachedTop = false;
    }

    if (elbowAngle >= _topAngleMin) {
      _phase = 'top';
    } else if (elbowAngle <= _bottomAngleMax) {
      _phase = 'bottom';
    } else if (_hasReachedTop) {
      _phase = 'lowering';
    } else {
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
      feedback = 'Full extension! Lower back with control';
      isCorrect = true;
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
    _hasReachedTop = false;
    repCount = 0;
  }
}

// Deadlift Analyser
// Key joint: HIP angle (shoulder-hip-knee), not knee — a deadlift is a hip
// hinge movement, so hip extension/flexion is the primary diagnostic angle.
// Thresholds informed by MediaPipe-based deadlift posture-correction systems
// using Set-Up / Lifting / Lock-Out staging derived from trainer-validated
// video analysis.
class DeadliftAnalyser implements PostureAnalyser {
  static const double _bottomAngleMax = 100.0;   // hinged over, Set-Up position
  static const double _lockoutAngleMin = 165.0;  // fully standing, hips extended

  String _phase = 'lockout';
  bool _hasReachedBottom = false;
  int repCount = 0;

  PostureResult analyse(List<Landmark> landmarks) {
    if (landmarks.length < 29) {
      return const PostureResult(
        isCorrect: false,
        feedback: 'Position yourself so your full body is visible',
        phase: 'unknown',
      );
    }

    final leftShoulder = landmarks[PoseLandmarkIndex.leftShoulder];
    final leftHip = landmarks[PoseLandmarkIndex.leftHip];
    final leftKnee = landmarks[PoseLandmarkIndex.leftKnee];
    final rightShoulder = landmarks[PoseLandmarkIndex.rightShoulder];
    final rightHip = landmarks[PoseLandmarkIndex.rightHip];
    final rightKnee = landmarks[PoseLandmarkIndex.rightKnee];

    final leftHipAngle = AngleCalculator.calculateAngle(leftShoulder, leftHip, leftKnee);
    final rightHipAngle = AngleCalculator.calculateAngle(rightShoulder, rightHip, rightKnee);
    final hipAngle = (leftHipAngle + rightHipAngle) / 2;

    if (leftHip.visibility < 0.5 || rightHip.visibility < 0.5) {
      return PostureResult(
        isCorrect: false,
        feedback: 'Step back — full body must be visible from the side',
        phase: _phase,
        keyAngle: hipAngle,
      );
    }

    bool countRep = false;

    // --- Rep counting: hysteresis-based, order-independent ---
    if (hipAngle <= _bottomAngleMax) {
      _hasReachedBottom = true;
    }
    if (hipAngle >= _lockoutAngleMin && _hasReachedBottom) {
      repCount++;
      countRep = true;
      _hasReachedBottom = false;
    }

    // --- Phase: feedback text only ---
    if (hipAngle >= _lockoutAngleMin) {
      _phase = 'lockout';
    } else if (hipAngle <= _bottomAngleMax) {
      _phase = 'setup';
    } else if (_hasReachedBottom) {
      _phase = 'lifting';
    } else {
      _phase = 'lowering';
    }

    String feedback;
    bool isCorrect;

    if (_phase == 'lockout') {
      feedback = countRep
          ? 'Rep $repCount complete! Reset and hinge again'
          : 'Standing tall — hinge at the hips to begin';
      isCorrect = true;
    } else if (_phase == 'lowering') {
      feedback = 'Push hips back — keep the bar close to your legs';
      isCorrect = true;
    } else if (_phase == 'setup') {
      feedback = 'Good hinge — keep your back flat, drive through heels';
      isCorrect = true;
    } else {
      feedback = 'Drive hips forward — squeeze glutes at the top';
      isCorrect = true;
    }

    return PostureResult(
      isCorrect: isCorrect,
      feedback: feedback,
      phase: _phase,
      keyAngle: hipAngle,
      countRep: countRep,
    );
  }

  void reset() {
    _phase = 'lockout';
    _hasReachedBottom = false;
    repCount = 0;
  }
}

// Lunge Analyser
// Key joint: FRONT knee angle. A lunge is asymmetric (one leg forward, one
// back), unlike a squat — so we auto-detect the "front" leg each frame as
// whichever knee is currently more bent (smaller angle), avoiding the need
// for the user to specify which leg leads.
class LungeAnalyser implements PostureAnalyser {
  static const double _bottomAngleMax = 100.0;   // front knee bent, lunge depth
  static const double _standingAngleMin = 160.0; // both legs near-straight

  String _phase = 'standing';
  bool _hasReachedBottom = false;
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

    final leftKneeAngle = AngleCalculator.calculateAngle(leftHip, leftKnee, leftAnkle);
    final rightKneeAngle = AngleCalculator.calculateAngle(rightHip, rightKnee, rightAnkle);

    // Front leg = whichever knee is currently MORE bent (smaller angle)
    final frontKneeAngle = math.min(leftKneeAngle, rightKneeAngle);

    if (leftKnee.visibility < 0.5 || rightKnee.visibility < 0.5) {
      return PostureResult(
        isCorrect: false,
        feedback: 'Step back — both legs must be visible',
        phase: _phase,
        keyAngle: frontKneeAngle,
      );
    }

    bool countRep = false;

    // --- Rep counting: hysteresis-based, order-independent ---
    if (frontKneeAngle <= _bottomAngleMax) {
      _hasReachedBottom = true;
    }
    if (frontKneeAngle > _standingAngleMin && _hasReachedBottom) {
      repCount++;
      countRep = true;
      _hasReachedBottom = false;
    }

    // --- Phase: feedback text only ---
    if (frontKneeAngle > _standingAngleMin) {
      _phase = 'standing';
    } else if (frontKneeAngle <= _bottomAngleMax) {
      _phase = 'bottom';
    } else if (_hasReachedBottom) {
      _phase = 'coming_up';
    } else {
      _phase = 'going_down';
    }

    String feedback;
    bool isCorrect;

    if (_phase == 'standing') {
      feedback = countRep
          ? 'Rep $repCount complete! Step into the next lunge'
          : 'Stand tall — step forward into your lunge';
      isCorrect = true;
    } else if (_phase == 'going_down') {
      feedback = 'Lower straight down — front knee over ankle';
      isCorrect = true;
    } else if (_phase == 'bottom') {
      feedback = 'Good depth! Push through your front heel to rise';
      isCorrect = true;
    } else {
      feedback = 'Drive up — keep your torso upright';
      isCorrect = true;
    }

    return PostureResult(
      isCorrect: isCorrect,
      feedback: feedback,
      phase: _phase,
      keyAngle: frontKneeAngle,
      countRep: countRep,
    );
  }

  void reset() {
    _phase = 'standing';
    _hasReachedBottom = false;
    repCount = 0;
  }
}

// Bicep Curl Analyser
// Key joint: elbow angle. Unlike push-up/press, a curl starts EXTENDED
// (large angle) and flexes UP to a small angle — the opposite phase order.
// Thresholds (extended >=160°, flexed <=50°) are consistent across multiple
// independent MediaPipe bicep-curl implementations (commonly cited as a
// 40-160° full range-of-motion requirement); 50° used here as a slightly
// safer full-contraction margin over the loosest published bound of 40°.
class BicepCurlAnalyser implements PostureAnalyser {
  static const double _extendedAngleMin = 160.0; // arm straight down
  static const double _flexedAngleMax = 50.0;    // full contraction at top

  String _phase = 'extended';
  bool _hasReachedFlexed = false;
  int repCount = 0;

  PostureResult analyse(List<Landmark> landmarks) {
    if (landmarks.length < 17) {
      return const PostureResult(
        isCorrect: false,
        feedback: 'Position yourself so your arms are visible',
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
        feedback: 'Arms not visible — face the camera directly',
        phase: _phase,
        keyAngle: elbowAngle,
      );
    }

    bool countRep = false;

    // --- Rep counting: hysteresis-based, order-independent ---
    if (elbowAngle <= _flexedAngleMax) {
      _hasReachedFlexed = true;
    }
    if (elbowAngle >= _extendedAngleMin && _hasReachedFlexed) {
      repCount++;
      countRep = true;
      _hasReachedFlexed = false;
    }

    // --- Phase: feedback text only ---
    if (elbowAngle >= _extendedAngleMin) {
      _phase = 'extended';
    } else if (elbowAngle <= _flexedAngleMax) {
      _phase = 'flexed';
    } else if (_hasReachedFlexed) {
      _phase = 'lowering';
    } else {
      _phase = 'curling';
    }

    String feedback;
    bool isCorrect;

    if (_phase == 'extended') {
      feedback = countRep
          ? 'Rep $repCount complete! Curl again'
          : 'Arm extended — curl the weight up';
      isCorrect = true;
    } else if (_phase == 'curling') {
      feedback = 'Keep curling — squeeze at the top';
      isCorrect = true;
    } else if (_phase == 'flexed') {
      feedback = 'Full contraction! Lower with control';
      isCorrect = true;
    } else {
      feedback = 'Lower slowly — full extension at the bottom';
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
    _phase = 'extended';
    _hasReachedFlexed = false;
    repCount = 0;
  }
}

// Exercise Analyser Factory
class ExerciseAnalyserFactory {
  static PostureAnalyser getAnalyser(String exerciseName) {
    final name = exerciseName.toLowerCase();
    if (name.contains('deadlift')) return DeadliftAnalyser();
    if (name.contains('lunge')) return LungeAnalyser();
    if (name.contains('curl')) return BicepCurlAnalyser();
    if (name.contains('squat')) return SquatAnalyser();
    if (name.contains('push') || name.contains('pushup')) return PushUpAnalyser();
    if (name.contains('bench')) return PushUpAnalyser(); // same elbow angle
    if (name.contains('press') || name.contains('shoulder')) return ShoulderPressAnalyser();
    return SquatAnalyser();
  }

  // Returns the expected rep target based on exercise name
  static String getInstructions(String exerciseName) {
    final name = exerciseName.toLowerCase();
    if (name.contains('squat')) {
      return '📱 Place phone 2–3m away at hip height.\n🧍 Stand sideways — your full body must be visible from head to ankles.';
    }
    if (name.contains('push')) {
      return '📱 Place phone on the floor 1m to your side, level with your body — not angled up.\n🧍 Face sideways — your full body from head to feet must be visible.';
    }
    if (name.contains('press') || name.contains('shoulder')) {
      return '📱 Place phone 2m away at chest height.\n🧍 Face the camera directly — both arms must be fully visible.';
    }
    if (name.contains('deadlift')) {
      return '📱 Place phone 2–3m away at hip height.\n🧍 Stand sideways — full body from head to floor must be visible.';
    }
    if (name.contains('lunge')) {
      return '📱 Place phone 2–3m away at hip height.\n🧍 Stand sideways — full body visible, step forward/back within frame.';
    }
    if (name.contains('curl')) {
      return '📱 Place phone 1–2m away at shoulder height.\n🧍 Face the camera — both arms fully visible.';
    }
    return '📱 Place phone 2–3m away.\n🧍 Ensure your full body is visible in the frame before starting.';
  }
}