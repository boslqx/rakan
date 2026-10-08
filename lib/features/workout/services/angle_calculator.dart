import 'dart:math' as math;
import 'package:flutter/foundation.dart';

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

// MediaPipe Pose landmark indices (the subset the analysers use)
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
  /// Converts MediaPipe's normalized landmarks into UPRIGHT pixel space.
  ///
  /// 1. Units. MediaPipe returns x as a fraction of the frame WIDTH and y as
  ///    a fraction of the frame HEIGHT. On a non-square frame (e.g. 640x480)
  ///    those two axes use different units, so measuring an angle directly on
  ///    normalized coordinates skews it — by up to ~16 degrees around 90
  ///    degrees on a 4:3 frame. Multiplying back by the frame size puts both
  ///    axes in the same unit (pixels).
  ///
  /// 2. Orientation. The native side hands MediaPipe the raw sensor bitmap
  ///    without rotating it (see PoseDetectorHandler.kt), so "up" in the
  ///    landmarks is not "up" in the real world — on a portrait phone with
  ///    the front camera the sensor reports rotationDegrees = 270 and the
  ///    person lies sideways in the frame. Joint angles (A-B-C) don't care,
  ///    because a rigid rotation preserves angles. But the checks added in
  ///    Phase 29 that measure a segment AGAINST GRAVITY (trunk lean, shank
  ///    verticality) do care, so the frame is rotated upright here using the
  ///    same rotationDegrees CameraX reports. After this call, +y points
  ///    down and (0, -1) is real-world "up".
  ///
  /// Mirroring (front camera) is deliberately ignored: it flips left/right
  /// but changes neither joint angles nor an angle measured from vertical.
  /// Must be applied before any analyser sees the landmarks.
  static List<Landmark> toPixelSpace(
    List<Landmark> landmarks, {
    required int frameWidth,
    required int frameHeight,
    int rotationDegrees = 0,
  }) {
    if (frameWidth <= 0 || frameHeight <= 0) return landmarks;
    final w = frameWidth.toDouble();
    final h = frameHeight.toDouble();
    final r = ((rotationDegrees % 360) + 360) % 360;

    return landmarks.map((l) {
      final px = l.x * w;
      final py = l.y * h;
      double ux;
      double uy;
      // Rotate the image CLOCKWISE by r degrees (CameraX's convention for
      // how far the buffer must be rotated to be displayed upright).
      if (r == 90) {
        ux = h - py;
        uy = px;
      } else if (r == 180) {
        ux = w - px;
        uy = h - py;
      } else if (r == 270) {
        ux = py;
        uy = w - px;
      } else {
        ux = px;
        uy = py;
      }
      return Landmark(x: ux, y: uy, z: l.z, visibility: l.visibility);
    }).toList();
  }

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

  /// Angle (0–180°) between the segment lower→upper and real-world vertical.
  /// 0° = segment points straight up, 90° = horizontal.
  /// Only meaningful on landmarks from [toPixelSpace] with the correct
  /// rotationDegrees, because it relies on (0, -1) being "up".
  ///
  /// Used for trunk lean (hip→shoulder) and shank verticality (ankle→knee).
  static double angleFromVertical(Landmark upper, Landmark lower) {
    final dx = upper.x - lower.x;
    final dy = upper.y - lower.y;
    final mag = math.sqrt(dx * dx + dy * dy);
    if (mag == 0) return 0;
    // Dot product with the unit "up" vector (0, -1) is simply -dy.
    final cosAngle = (-dy / mag).clamp(-1.0, 1.0);
    return math.acos(cosAngle) * 180 / math.pi;
  }
}

/// Every form threshold in one place, with where the number comes from.
/// Full write-up with references: docs/POSTURE_THRESHOLDS.md.
///
/// DESIGN RULE used throughout: threshold = published reference value
/// + a 10° MediaPipe measurement tolerance. 2D MediaPipe joint angles are
/// not motion-capture accurate (Dill et al., 2023), so a rule that demands
/// the exact textbook angle would mark genuinely good reps as wrong.
/// For joints judged near FULL EXTENSION (~180°) the tolerance is doubled
/// to 20°, because Dill et al. (2023) found estimation error grows as a
/// joint approaches straight.
/// Some values have no direct published number — those are marked
/// "ENGINEERING ESTIMATE" and are exactly what the Objective 2 accuracy
/// study must validate.
class FormThresholds {
  /// Landmarks below this MediaPipe visibility score are treated as hidden.
  static const double minVisibility = 0.5;

  /// The general measurement tolerance described above.
  static const double tolerance = 10.0;

  // ---------------------------------------------------------------- SQUAT
  // Inner (included) knee angle, hip-knee-ankle. Rojas-Jaramillo et al.
  // (2024): quarter squat 110–140°, half squat 80–100°, parallel squat
  // ≈60–70°, deep squat 40–45°. The same review (13 of 15 studies) found
  // deep squats safe for healthy knees, so there is NO "too deep" fault.

  /// Rep is counted once the knee passes the top of the half-squat band
  /// (100° + tolerance). Counting shallow reps (instead of ignoring them)
  /// is what lets the app actually flag them as too shallow.
  static const double squatCountMax = 110.0;

  /// Correct depth = parallel (upper bound 70°) + tolerance.
  static const double squatDepthMax = 80.0;

  /// Standing / rep-complete. Unchanged from the original implementation.
  static const double squatStandingMin = 160.0;

  /// Trunk lean from vertical (hip→shoulder). Graber et al. (2023) measured
  /// self-selected bodyweight squats at a parallel depth (110° knee flexion):
  /// 37.8° ± 9.7°. Mean + 2 SD = 57.2°. The ±2 SD band (±19°) is already
  /// wider than the measurement tolerance, so no extra margin is added.
  static const double squatTrunkLeanMax = 57.0;

  // ----------------------------------------------------- LUNGE / SPLIT SQUAT
  // Front-knee inner angle. Farrokhi et al. (2008) measured 110.3° ± 5.9°
  // knee FLEXION (≈70° inner angle) at the bottom of a normal forward lunge;
  // the common coaching cue is a 90° front knee. Depth limit = 90° + 10°.
  static const double lungeCountMax = 120.0;
  static const double lungeDepthMax = 100.0;
  static const double lungeStandingMin = 160.0;

  /// Farrokhi et al. (2008) defined the normal lunge with a VERTICAL trunk;
  /// their deliberate trunk-forward variant raised hip flexion by ≈20°.
  /// Limit = 20° + tolerance — flags lean beyond even that deliberate variant.
  static const double lungeTrunkLeanMax = 30.0;

  // ------------------------------------------------------------ DEADLIFT
  // Hip angle shoulder-hip-knee. Unchanged from the original implementation.
  static const double deadliftHingeMax = 100.0;
  static const double deadliftLockoutMin = 165.0;

  // ---------------------------------------------------- ROMANIAN DEADLIFT
  /// Knee held at ≈15° flexion throughout (Physiopedia, Romanian deadlift).
  /// 15° + tolerance = 25° flexion → inner knee angle must stay ≥ 155°.
  static const double rdlKneeMin = 155.0;

  /// Hinge counted once the hip angle drops below 125°.
  static const double rdlCountMax = 125.0;

  /// ENGINEERING ESTIMATE. The bar should travel to just below the knee
  /// (Physiopedia). With the knees at ~165° that geometrically corresponds to
  /// a trunk ≈60–70° from vertical, i.e. a hip angle of roughly 100–110°.
  static const double rdlDepthMax = 110.0;
  static const double rdlLockoutMin = 165.0;

  // ------------------------------------------------- PUSH-UP / BENCH PRESS
  /// ACSM / FitnessGram push-up standard: lower until the elbows reach 90°
  /// with the upper arms parallel to the floor. 90° + tolerance.
  static const double pushUpDepthMax = 100.0;
  static const double pushUpCountMax = 120.0;
  static const double pushUpTopMin = 145.0;

  /// Body line shoulder-hip-ankle: a straight plank is 180°. Near-extension
  /// tolerance (20°). Unchanged from the original implementation.
  static const double pushUpBodyLineMin = 160.0;

  /// ENGINEERING ESTIMATE. A pike push-up holds the hips flexed at ~90°;
  /// beyond 120° the movement has become a regular (declined) push-up.
  static const double pikeHipMax = 120.0;

  // ---------------------------------------------------------- SHOULDER PRESS
  static const double pressBottomMax = 100.0;
  static const double pressCountTopMin = 145.0;

  /// Full lockout = 180°, near-extension tolerance 20°. Unchanged value.
  static const double pressLockoutMin = 160.0;

  /// Left-vs-right elbow angle difference. Each arm's angle carries ±10°
  /// error, so up to 20° of difference can be pure measurement noise; only
  /// a larger gap is reported as an uneven press.
  static const double pressAsymmetryMax = 20.0;

  // --------------------------------------------------------------- CURLS
  /// Full contraction: the 40–160° range of motion used across published
  /// MediaPipe curl counters; 40° + tolerance. Unchanged value.
  static const double curlFlexedMax = 50.0;
  static const double curlCountMax = 70.0;
  static const double curlExtendedMin = 140.0;

  /// Upper arm vs trunk (hip-shoulder-elbow). Chua et al. (2024): shoulder
  /// flexion stayed within ≈[-10°, 0°] in normal curls and drifted to
  /// ≈[0°, 20°] when fatigued (compensatory swing). 20° + tolerance.
  static const double curlSwingMax = 30.0;
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
// checking concrete types with `is`/`as` — adding another analyser never
// requires touching the dispatch code.
abstract class PostureAnalyser {
  PostureResult analyse(List<Landmark> landmarks);
  int get repCount;
  void reset();
}

// ===========================================================================
// Shared helpers
// ===========================================================================

enum _Side { left, right }

bool _allVisible(List<Landmark> lm, List<int> idx) =>
    idx.every((i) => lm[i].visibility >= FormThresholds.minVisibility);

double _meanVisibility(List<Landmark> lm, List<int> idx) =>
    idx.map((i) => lm[i].visibility).reduce((a, b) => a + b) / idx.length;

/// Picks the body side whose landmarks are all visible. In a side-on view
/// the far limb is usually occluded, so analysers use the near side instead
/// of refusing to analyse. If both sides qualify, the better-tracked one wins.
_Side? _bestSide(List<Landmark> lm, List<int> left, List<int> right) {
  final l = _allVisible(lm, left);
  final r = _allVisible(lm, right);
  if (l && r) {
    return _meanVisibility(lm, left) >= _meanVisibility(lm, right)
        ? _Side.left
        : _Side.right;
  }
  if (l) return _Side.left;
  if (r) return _Side.right;
  return null;
}

/// Index of a landmark on the chosen side.
int _on(_Side s, int left, int right) => s == _Side.left ? left : right;

/// Trunk lean from vertical using whichever side's shoulder+hip is visible.
double? _trunkLean(List<Landmark> lm) {
  final side = _bestSide(
    lm,
    const [PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.leftHip],
    const [PoseLandmarkIndex.rightShoulder, PoseLandmarkIndex.rightHip],
  );
  if (side == null) return null;
  return AngleCalculator.angleFromVertical(
    lm[_on(side, PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.rightShoulder)],
    lm[_on(side, PoseLandmarkIndex.leftHip, PoseLandmarkIndex.rightHip)],
  );
}

/// What happened during one completed rep.
class _RepSummary {
  final double minAngle;
  final double maxAngle;
  final Map<String, double> peaks;
  const _RepSummary(this.minAngle, this.maxAngle, this.peaks);
}

/// Hysteresis rep counter shared by every analyser.
///
/// A rep = leave the REST zone → reach the WORK zone → return to REST.
/// It is order-independent: it only cares that the work zone was reached at
/// some point before returning to rest, so a skipped intermediate frame never
/// loses a rep (the original analysers' design, now in one place).
///
/// While a rep is in progress it records the primary angle's min/max and any
/// secondary "peaks" (e.g. the worst trunk lean). When the rep completes these
/// are returned as a [_RepSummary] so the rep can be judged ONCE, at its true
/// extreme — not per frame.
class _RepTracker {
  _RepTracker({
    required this.workAt,
    required this.restAt,
    required this.workIsBelow,
  });

  /// Threshold of the work zone (e.g. squat bottom, press top).
  final double workAt;

  /// Threshold of the rest zone (e.g. standing, arms down).
  final double restAt;

  /// True when the work zone is a SMALLER angle than rest (squat, push-up,
  /// curl). False when it is larger (overhead press).
  final bool workIsBelow;

  bool armed = false;
  int count = 0;
  double? _min;
  double? _max;
  final Map<String, double> _peaks = {};

  bool isWorking(double a) => workIsBelow ? a <= workAt : a >= workAt;
  bool isResting(double a) => workIsBelow ? a >= restAt : a <= restAt;

  /// Record the highest value of a secondary measure during this rep.
  void noteMax(String key, double v) {
    final old = _peaks[key];
    _peaks[key] = old == null ? v : math.max(old, v);
  }

  /// Record the lowest value of a secondary measure during this rep.
  void noteMin(String key, double v) {
    final old = _peaks[key];
    _peaks[key] = old == null ? v : math.min(old, v);
  }

  /// Feed one frame's primary angle. Returns a summary when a rep completes.
  /// Call noteMax/noteMin for this frame BEFORE calling update().
  _RepSummary? update(double a) {
    _min = _min == null ? a : math.min(_min!, a);
    _max = _max == null ? a : math.max(_max!, a);
    if (isWorking(a)) armed = true;
    if (isResting(a)) {
      _RepSummary? done;
      if (armed) {
        count++;
        done = _RepSummary(_min!, _max!, Map.of(_peaks));
        armed = false;
      }
      // At rest: start a fresh window so set-up frames never pollute a rep.
      _min = null;
      _max = null;
      _peaks.clear();
      return done;
    }
    return null;
  }

  String phase(
    double a, {
    required String rest,
    required String work,
    required String toward,
    required String back,
  }) {
    if (isResting(a)) return rest;
    if (isWorking(a)) return work;
    return armed ? back : toward;
  }

  void reset() {
    armed = false;
    count = 0;
    _min = null;
    _max = null;
    _peaks.clear();
  }
}

String _fmt(double? v) => v?.toStringAsFixed(1) ?? 'null';

/// Validation logging for the Objective 2 accuracy study. Format parsed by
/// tools/posture_study/capture.py (6 fields):
///   VALIDATION|exercise|rep|primaryAngle|secondaryMeasure|isCorrect
/// The squat now also logs trunk lean as the secondary measure.
void _logRep(String tag, int rep, double? primary, double? secondary, bool ok) {
  debugPrint('VALIDATION|$tag|$rep|${_fmt(primary)}|${_fmt(secondary)}|$ok');
}

// ===========================================================================
// Squat — Bodyweight / Barbell / Band / Goblet / Front squat
// ===========================================================================
//
// Primary: inner knee angle (depth). Fault: excessive forward trunk lean.
// Change from the original: the 80–100° "good depth" window was actually the
// HALF-squat band, and < 80° (i.e. a proper parallel squat) was flagged
// "too deep". Corrected to parallel-or-deeper, no "too deep" fault.
class SquatAnalyser implements PostureAnalyser {
  final _RepTracker _t = _RepTracker(
    workAt: FormThresholds.squatCountMax,
    restAt: FormThresholds.squatStandingMin,
    workIsBelow: true,
  );

  String? _lastRepFeedback;
  bool _lastRepOk = true;

  @override
  int get repCount => _t.count;

  @override
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

    // Front-on: both legs visible, average them for robustness. Side-on (the
    // better view for judging depth in 2D): the far leg is usually occluded,
    // so fall back to whichever single leg is fully visible.
    final leftOk = _allVisible(landmarks, const [
      PoseLandmarkIndex.leftHip, PoseLandmarkIndex.leftKnee, PoseLandmarkIndex.leftAnkle,
    ]);
    final rightOk = _allVisible(landmarks, const [
      PoseLandmarkIndex.rightHip, PoseLandmarkIndex.rightKnee, PoseLandmarkIndex.rightAnkle,
    ]);

    final double kneeAngle;
    if (leftOk && rightOk) {
      kneeAngle = (leftKneeAngle + rightKneeAngle) / 2;
    } else if (leftOk) {
      kneeAngle = leftKneeAngle;
    } else if (rightOk) {
      kneeAngle = rightKneeAngle;
    } else {
      return PostureResult(
        isCorrect: false,
        feedback: 'Step back — full legs must be visible',
        phase: _phaseOf((leftKneeAngle + rightKneeAngle) / 2),
        keyAngle: (leftKneeAngle + rightKneeAngle) / 2,
      );
    }

    final lean = _trunkLean(landmarks);
    if (lean != null) _t.noteMax('trunk', lean);

    final rep = _t.update(kneeAngle);
    if (rep != null) {
      final depthOk = rep.minAngle <= FormThresholds.squatDepthMax;
      final trunk = rep.peaks['trunk'];
      final trunkOk = trunk == null || trunk <= FormThresholds.squatTrunkLeanMax;
      _lastRepOk = depthOk && trunkOk;
      _logRep('squat', _t.count, rep.minAngle, trunk, _lastRepOk);
      if (!depthOk) {
        _lastRepFeedback =
            'Rep ${_t.count}: too shallow (${rep.minAngle.toStringAsFixed(0)}°) — sink until thighs are parallel';
      } else if (!trunkOk) {
        _lastRepFeedback = 'Rep ${_t.count}: leaned too far forward — keep your chest up';
      } else {
        _lastRepFeedback = 'Rep ${_t.count} complete — good depth!';
      }
    }

    final phase = _phaseOf(kneeAngle);
    final leaning = lean != null && lean > FormThresholds.squatTrunkLeanMax;

    String feedback;
    bool isCorrect;
    if (leaning && phase != 'standing') {
      feedback = 'Chest up — you\'re leaning too far forward (${lean!.toStringAsFixed(0)}°)';
      isCorrect = false;
    } else if (phase == 'standing') {
      feedback = _lastRepFeedback ?? 'Stand straight, feet shoulder-width apart';
      isCorrect = _lastRepOk;
    } else if (phase == 'going_down') {
      feedback = 'Sit your hips back — chest up';
      isCorrect = true;
    } else if (phase == 'bottom') {
      if (kneeAngle <= FormThresholds.squatDepthMax) {
        feedback = 'Good depth! Drive up through your heels';
      } else {
        feedback = 'A little lower — aim for thighs parallel to the floor';
      }
      isCorrect = true;
    } else {
      feedback = 'Drive up — keep your core tight';
      isCorrect = true;
    }

    return PostureResult(
      isCorrect: isCorrect,
      feedback: feedback,
      phase: phase,
      keyAngle: kneeAngle,
      countRep: rep != null,
    );
  }

  String _phaseOf(double a) => _t.phase(a,
      rest: 'standing', work: 'bottom', toward: 'going_down', back: 'coming_up');

  @override
  void reset() {
    _t.reset();
    _lastRepFeedback = null;
    _lastRepOk = true;
  }
}

// ===========================================================================
// Push-up family — standard / wide / diamond / close-grip / incline /
// decline push-ups, plus the pike push-up and barbell bench press variants.
// ===========================================================================

enum PushUpVariant {
  /// Body must stay in a straight plank (shoulder-hip-ankle).
  standard,

  /// Hips are DELIBERATELY flexed, so the plank check would be wrong.
  /// Checks instead that the hips stay up in the pike.
  pike,

  /// Lying on a bench — no plank to check, elbow depth only.
  bench,
}

class PushUpAnalyser implements PostureAnalyser {
  PushUpAnalyser({this.variant = PushUpVariant.standard});

  final PushUpVariant variant;

  final _RepTracker _t = _RepTracker(
    workAt: FormThresholds.pushUpCountMax,
    restAt: FormThresholds.pushUpTopMin,
    workIsBelow: true,
  );

  String? _lastRepFeedback;
  bool _lastRepOk = true;

  @override
  int get repCount => _t.count;

  String get _tag => switch (variant) {
        PushUpVariant.standard => 'pushup',
        PushUpVariant.pike => 'pike_pushup',
        PushUpVariant.bench => 'bench',
      };

  @override
  PostureResult analyse(List<Landmark> landmarks) {
    if (landmarks.length < 29) {
      return const PostureResult(
        isCorrect: false,
        feedback: 'Position yourself so your full body is visible',
        phase: 'unknown',
      );
    }

    // Side-on view: use the arm nearest the camera (the far one is usually
    // occluded). The original required BOTH elbows visible, which a side-on
    // phone rarely achieves.
    final armSide = _bestSide(
      landmarks,
      const [PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.leftElbow, PoseLandmarkIndex.leftWrist],
      const [PoseLandmarkIndex.rightShoulder, PoseLandmarkIndex.rightElbow, PoseLandmarkIndex.rightWrist],
    );
    if (armSide == null) {
      return const PostureResult(
        isCorrect: false,
        feedback: 'Arms not visible — face the camera sideways',
        phase: 'unknown',
      );
    }
    final elbowAngle = AngleCalculator.calculateAngle(
      landmarks[_on(armSide, PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.rightShoulder)],
      landmarks[_on(armSide, PoseLandmarkIndex.leftElbow, PoseLandmarkIndex.rightElbow)],
      landmarks[_on(armSide, PoseLandmarkIndex.leftWrist, PoseLandmarkIndex.rightWrist)],
    );

    // Shoulder-hip-ankle angle: straight-body check (standard) or pike
    // check (pike). Not used for bench.
    double? hipLine;
    if (variant != PushUpVariant.bench) {
      final bodySide = _bestSide(
        landmarks,
        const [PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.leftHip, PoseLandmarkIndex.leftAnkle],
        const [PoseLandmarkIndex.rightShoulder, PoseLandmarkIndex.rightHip, PoseLandmarkIndex.rightAnkle],
      );
      if (bodySide != null) {
        hipLine = AngleCalculator.calculateAngle(
          landmarks[_on(bodySide, PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.rightShoulder)],
          landmarks[_on(bodySide, PoseLandmarkIndex.leftHip, PoseLandmarkIndex.rightHip)],
          landmarks[_on(bodySide, PoseLandmarkIndex.leftAnkle, PoseLandmarkIndex.rightAnkle)],
        );
      }
    }
    if (hipLine != null) {
      if (variant == PushUpVariant.standard) _t.noteMin('hip', hipLine);
      if (variant == PushUpVariant.pike) _t.noteMax('hip', hipLine);
    }

    final rep = _t.update(elbowAngle);
    if (rep != null) {
      final depthOk = rep.minAngle <= FormThresholds.pushUpDepthMax;
      final hip = rep.peaks['hip'];
      bool hipOk = true;
      if (variant == PushUpVariant.standard && hip != null) {
        hipOk = hip >= FormThresholds.pushUpBodyLineMin;
      } else if (variant == PushUpVariant.pike && hip != null) {
        hipOk = hip <= FormThresholds.pikeHipMax;
      }
      _lastRepOk = depthOk && hipOk;
      _logRep(_tag, _t.count, rep.minAngle, hip, _lastRepOk);
      if (!depthOk) {
        _lastRepFeedback = variant == PushUpVariant.bench
            ? 'Rep ${_t.count}: lower the bar further — elbows to 90°'
            : 'Rep ${_t.count}: go lower — elbows to 90°';
      } else if (!hipOk) {
        _lastRepFeedback = variant == PushUpVariant.pike
            ? 'Rep ${_t.count}: hips dropped — keep them high in the pike'
            : 'Rep ${_t.count}: hips sagged or piked — keep a straight line';
      } else {
        _lastRepFeedback = 'Rep ${_t.count} complete — good rep!';
      }
    }

    final phase = _t.phase(elbowAngle,
        rest: 'up', work: 'bottom', toward: 'going_down', back: 'coming_up');

    // Live body-position faults take priority — a sagging back is a more
    // important safety cue than depth.
    String? liveFault;
    if (variant == PushUpVariant.standard &&
        hipLine != null &&
        hipLine < FormThresholds.pushUpBodyLineMin) {
      liveFault = 'Keep your hips level — body in one straight line';
    } else if (variant == PushUpVariant.pike &&
        hipLine != null &&
        hipLine > FormThresholds.pikeHipMax) {
      liveFault = 'Push your hips up — keep the pike shape';
    }

    String feedback;
    bool isCorrect;
    if (liveFault != null) {
      feedback = liveFault;
      isCorrect = false;
    } else if (phase == 'up') {
      feedback = _lastRepFeedback ??
          (variant == PushUpVariant.bench
              ? 'Arms extended — lower the bar to your chest'
              : 'Arms extended — lower your chest to the ground');
      isCorrect = _lastRepOk;
    } else if (phase == 'going_down') {
      feedback = variant == PushUpVariant.standard
          ? 'Good — keep your body straight like a plank'
          : 'Lower under control';
      isCorrect = true;
    } else if (phase == 'bottom') {
      feedback = elbowAngle <= FormThresholds.pushUpDepthMax
          ? 'Good depth! Push back up'
          : 'Lower a little more — elbows to 90°';
      isCorrect = true;
    } else {
      feedback = 'Push up — lock out your elbows at the top';
      isCorrect = true;
    }

    return PostureResult(
      isCorrect: isCorrect,
      feedback: feedback,
      phase: phase,
      keyAngle: elbowAngle,
      countRep: rep != null,
    );
  }

  @override
  void reset() {
    _t.reset();
    _lastRepFeedback = null;
    _lastRepOk = true;
  }
}

// ===========================================================================
// Shoulder press — Dumbbell / Seated Dumbbell / Barbell Overhead / Arnold
// ===========================================================================
//
// Front-on view (both arms visible). Primary: elbow angle. A rep is
// bottom → top → bottom. Faults: incomplete lockout, uneven arms.
// Change from the original: the "top" threshold for COUNTING is now looser
// (145°) than the lockout STANDARD (160°), so a half-lockout rep is counted
// and flagged instead of silently not counted.
class ShoulderPressAnalyser implements PostureAnalyser {
  final _RepTracker _t = _RepTracker(
    workAt: FormThresholds.pressCountTopMin,
    restAt: FormThresholds.pressBottomMax,
    workIsBelow: false,
  );

  String? _lastRepFeedback;
  bool _lastRepOk = true;

  @override
  int get repCount => _t.count;

  @override
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

    final bothArms = _allVisible(landmarks, const [
      PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.leftElbow, PoseLandmarkIndex.leftWrist,
      PoseLandmarkIndex.rightShoulder, PoseLandmarkIndex.rightElbow, PoseLandmarkIndex.rightWrist,
    ]);
    if (!bothArms) {
      return PostureResult(
        isCorrect: false,
        feedback: 'Face the camera — both arms must be visible',
        phase: 'unknown',
        keyAngle: elbowAngle,
      );
    }

    final asymmetry = (leftElbowAngle - rightElbowAngle).abs();
    _t.noteMax('asym', asymmetry);

    final rep = _t.update(elbowAngle);
    if (rep != null) {
      final lockoutOk = rep.maxAngle >= FormThresholds.pressLockoutMin;
      final asym = rep.peaks['asym'];
      final evenOk = asym == null || asym <= FormThresholds.pressAsymmetryMax;
      _lastRepOk = lockoutOk && evenOk;
      // Primary logged value is the rep's MAX elbow angle (lockout), not min.
      _logRep('press', _t.count, rep.maxAngle, asym, _lastRepOk);
      if (!lockoutOk) {
        _lastRepFeedback =
            'Rep ${_t.count}: not fully locked out (${rep.maxAngle.toStringAsFixed(0)}°) — straighten your arms overhead';
      } else if (!evenOk) {
        _lastRepFeedback = 'Rep ${_t.count}: arms were uneven — press both sides together';
      } else {
        _lastRepFeedback = 'Rep ${_t.count} complete — full lockout!';
      }
    }

    final phase = _t.phase(elbowAngle,
        rest: 'bottom', work: 'top', toward: 'pressing', back: 'lowering');

    String feedback;
    bool isCorrect;
    if (phase != 'bottom' && asymmetry > FormThresholds.pressAsymmetryMax) {
      feedback = 'Press evenly — one arm is lagging';
      isCorrect = false;
    } else if (phase == 'bottom') {
      feedback = _lastRepFeedback ?? 'Elbows at shoulder height — press overhead';
      isCorrect = _lastRepOk;
    } else if (phase == 'pressing') {
      feedback = 'Press overhead — fully extend your arms';
      isCorrect = true;
    } else if (phase == 'top') {
      feedback = elbowAngle >= FormThresholds.pressLockoutMin
          ? 'Full extension! Lower with control'
          : 'Almost — lock your elbows out';
      isCorrect = true;
    } else {
      feedback = 'Lower slowly — control the weight down';
      isCorrect = true;
    }

    return PostureResult(
      isCorrect: isCorrect,
      feedback: feedback,
      phase: phase,
      keyAngle: elbowAngle,
      countRep: rep != null,
    );
  }

  @override
  void reset() {
    _t.reset();
    _lastRepFeedback = null;
    _lastRepOk = true;
  }
}

// ===========================================================================
// Deadlift (conventional)
// ===========================================================================
// Key joint: HIP angle (shoulder-hip-knee) — a deadlift is a hip hinge, so
// hip extension/flexion is the primary diagnostic angle. Thresholds
// unchanged; the only change is using the near-side hip in a side-on view
// rather than requiring both hips visible.
class DeadliftAnalyser implements PostureAnalyser {
  final _RepTracker _t = _RepTracker(
    workAt: FormThresholds.deadliftHingeMax,
    restAt: FormThresholds.deadliftLockoutMin,
    workIsBelow: true,
  );

  @override
  int get repCount => _t.count;

  @override
  PostureResult analyse(List<Landmark> landmarks) {
    if (landmarks.length < 29) {
      return const PostureResult(
        isCorrect: false,
        feedback: 'Position yourself so your full body is visible',
        phase: 'unknown',
      );
    }

    final side = _bestSide(
      landmarks,
      const [PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.leftHip, PoseLandmarkIndex.leftKnee],
      const [PoseLandmarkIndex.rightShoulder, PoseLandmarkIndex.rightHip, PoseLandmarkIndex.rightKnee],
    );
    if (side == null) {
      return const PostureResult(
        isCorrect: false,
        feedback: 'Step back — full body must be visible from the side',
        phase: 'unknown',
      );
    }
    final hipAngle = AngleCalculator.calculateAngle(
      landmarks[_on(side, PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.rightShoulder)],
      landmarks[_on(side, PoseLandmarkIndex.leftHip, PoseLandmarkIndex.rightHip)],
      landmarks[_on(side, PoseLandmarkIndex.leftKnee, PoseLandmarkIndex.rightKnee)],
    );

    final rep = _t.update(hipAngle);
    if (rep != null) {
      final ok = rep.minAngle <= FormThresholds.deadliftHingeMax;
      // 5-field format, unchanged from before.
      debugPrint('VALIDATION|deadlift|${_t.count}|${_fmt(rep.minAngle)}|$ok');
    }

    final phase = _t.phase(hipAngle,
        rest: 'lockout', work: 'setup', toward: 'lowering', back: 'lifting');

    String feedback;
    if (phase == 'lockout') {
      feedback = rep != null
          ? 'Rep ${_t.count} complete! Reset and hinge again'
          : 'Standing tall — hinge at the hips to begin';
    } else if (phase == 'lowering') {
      feedback = 'Push hips back — keep the bar close to your legs';
    } else if (phase == 'setup') {
      feedback = 'Good hinge — keep your back flat, drive through heels';
    } else {
      feedback = 'Drive hips forward — squeeze glutes at the top';
    }

    return PostureResult(
      isCorrect: true,
      feedback: feedback,
      phase: phase,
      keyAngle: hipAngle,
      countRep: rep != null,
    );
  }

  @override
  void reset() => _t.reset();
}

// ===========================================================================
// Romanian deadlift — Barbell / Dumbbell (NEW)
// ===========================================================================
// Same hip hinge as the deadlift, but the knees stay almost straight
// (~15° flexion). Primary: hip angle. Faults: too much knee bend (it has
// turned into a conventional deadlift / squat), hinge too shallow.
class RomanianDeadliftAnalyser implements PostureAnalyser {
  final _RepTracker _t = _RepTracker(
    workAt: FormThresholds.rdlCountMax,
    restAt: FormThresholds.rdlLockoutMin,
    workIsBelow: true,
  );

  String? _lastRepFeedback;
  bool _lastRepOk = true;

  @override
  int get repCount => _t.count;

  @override
  PostureResult analyse(List<Landmark> landmarks) {
    if (landmarks.length < 29) {
      return const PostureResult(
        isCorrect: false,
        feedback: 'Position yourself so your full body is visible',
        phase: 'unknown',
      );
    }

    final side = _bestSide(
      landmarks,
      const [
        PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.leftHip,
        PoseLandmarkIndex.leftKnee, PoseLandmarkIndex.leftAnkle,
      ],
      const [
        PoseLandmarkIndex.rightShoulder, PoseLandmarkIndex.rightHip,
        PoseLandmarkIndex.rightKnee, PoseLandmarkIndex.rightAnkle,
      ],
    );
    if (side == null) {
      return const PostureResult(
        isCorrect: false,
        feedback: 'Step back — stand side-on, head to ankles in frame',
        phase: 'unknown',
      );
    }
    final shoulder = landmarks[_on(side, PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.rightShoulder)];
    final hip = landmarks[_on(side, PoseLandmarkIndex.leftHip, PoseLandmarkIndex.rightHip)];
    final knee = landmarks[_on(side, PoseLandmarkIndex.leftKnee, PoseLandmarkIndex.rightKnee)];
    final ankle = landmarks[_on(side, PoseLandmarkIndex.leftAnkle, PoseLandmarkIndex.rightAnkle)];

    final hipAngle = AngleCalculator.calculateAngle(shoulder, hip, knee);
    final kneeAngle = AngleCalculator.calculateAngle(hip, knee, ankle);
    _t.noteMin('knee', kneeAngle);

    final rep = _t.update(hipAngle);
    if (rep != null) {
      final depthOk = rep.minAngle <= FormThresholds.rdlDepthMax;
      final minKnee = rep.peaks['knee'];
      final kneeOk = minKnee == null || minKnee >= FormThresholds.rdlKneeMin;
      _lastRepOk = depthOk && kneeOk;
      _logRep('rdl', _t.count, rep.minAngle, minKnee, _lastRepOk);
      if (!kneeOk) {
        _lastRepFeedback = 'Rep ${_t.count}: knees bent too much — keep them soft, push hips back';
      } else if (!depthOk) {
        _lastRepFeedback = 'Rep ${_t.count}: hinge deeper — weight to just below the knee';
      } else {
        _lastRepFeedback = 'Rep ${_t.count} complete — good hinge!';
      }
    }

    final phase = _t.phase(hipAngle,
        rest: 'lockout', work: 'bottom', toward: 'lowering', back: 'lifting');

    String feedback;
    bool isCorrect;
    if (phase != 'lockout' && kneeAngle < FormThresholds.rdlKneeMin) {
      feedback = 'Less knee bend — push your hips back instead';
      isCorrect = false;
    } else if (phase == 'lockout') {
      feedback = _lastRepFeedback ?? 'Stand tall, soft knees — push hips back to begin';
      isCorrect = _lastRepOk;
    } else if (phase == 'lowering') {
      feedback = 'Hips back, back flat — slide the weight down your legs';
      isCorrect = true;
    } else if (phase == 'bottom') {
      feedback = hipAngle <= FormThresholds.rdlDepthMax
          ? 'Good stretch — drive your hips forward'
          : 'A little deeper — weight to just below the knee';
      isCorrect = true;
    } else {
      feedback = 'Hips forward — squeeze glutes at the top';
      isCorrect = true;
    }

    return PostureResult(
      isCorrect: isCorrect,
      feedback: feedback,
      phase: phase,
      keyAngle: hipAngle,
      countRep: rep != null,
    );
  }

  @override
  void reset() {
    _t.reset();
    _lastRepFeedback = null;
    _lastRepOk = true;
  }
}

// ===========================================================================
// Lunge / split squat — Forward / Reverse / Barbell lunge, Split squat,
// Bulgarian split squat (bodyweight and dumbbell)
// ===========================================================================
// Key joint: FRONT knee angle. Faults: too shallow, trunk leaning forward.
//
// Change from the original: the front leg used to be "whichever knee is more
// bent". That breaks for a Bulgarian split squat — the REAR knee stays bent
// on the bench even at the top, so the analyser never saw "standing" and
// never counted a rep. The front leg is now the one whose SHIN is closer to
// vertical, which is true for every lunge and split-squat variant (the rear
// shin always slopes back).
class LungeAnalyser implements PostureAnalyser {
  final _RepTracker _t = _RepTracker(
    workAt: FormThresholds.lungeCountMax,
    restAt: FormThresholds.lungeStandingMin,
    workIsBelow: true,
  );

  String? _lastRepFeedback;
  bool _lastRepOk = true;

  @override
  int get repCount => _t.count;

  @override
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

    if (leftKnee.visibility < FormThresholds.minVisibility ||
        rightKnee.visibility < FormThresholds.minVisibility) {
      return PostureResult(
        isCorrect: false,
        feedback: 'Step back — both legs must be visible',
        phase: 'unknown',
        keyAngle: math.min(leftKneeAngle, rightKneeAngle),
      );
    }

    // Front leg = the more vertical shin.
    final leftShin = AngleCalculator.angleFromVertical(leftKnee, leftAnkle);
    final rightShin = AngleCalculator.angleFromVertical(rightKnee, rightAnkle);
    final frontKneeAngle = leftShin <= rightShin ? leftKneeAngle : rightKneeAngle;

    final lean = _trunkLean(landmarks);
    if (lean != null) _t.noteMax('trunk', lean);

    final rep = _t.update(frontKneeAngle);
    if (rep != null) {
      final depthOk = rep.minAngle <= FormThresholds.lungeDepthMax;
      final trunk = rep.peaks['trunk'];
      final trunkOk = trunk == null || trunk <= FormThresholds.lungeTrunkLeanMax;
      _lastRepOk = depthOk && trunkOk;
      _logRep('lunge', _t.count, rep.minAngle, trunk, _lastRepOk);
      if (!depthOk) {
        _lastRepFeedback =
            'Rep ${_t.count}: too shallow (${rep.minAngle.toStringAsFixed(0)}°) — front knee to 90°';
      } else if (!trunkOk) {
        _lastRepFeedback = 'Rep ${_t.count}: torso leaned forward — stay tall';
      } else {
        _lastRepFeedback = 'Rep ${_t.count} complete — good depth!';
      }
    }

    final phase = _t.phase(frontKneeAngle,
        rest: 'standing', work: 'bottom', toward: 'going_down', back: 'coming_up');
    final leaning = lean != null && lean > FormThresholds.lungeTrunkLeanMax;

    String feedback;
    bool isCorrect;
    if (leaning && phase != 'standing') {
      feedback = 'Keep your torso upright (${lean!.toStringAsFixed(0)}° lean)';
      isCorrect = false;
    } else if (phase == 'standing') {
      feedback = _lastRepFeedback ?? 'Stand tall — lower straight down into your lunge';
      isCorrect = _lastRepOk;
    } else if (phase == 'going_down') {
      feedback = 'Lower straight down — front knee over ankle';
      isCorrect = true;
    } else if (phase == 'bottom') {
      feedback = frontKneeAngle <= FormThresholds.lungeDepthMax
          ? 'Good depth! Push through your front heel to rise'
          : 'A little lower — front knee to 90°';
      isCorrect = true;
    } else {
      feedback = 'Drive up — keep your torso upright';
      isCorrect = true;
    }

    return PostureResult(
      isCorrect: isCorrect,
      feedback: feedback,
      phase: phase,
      keyAngle: frontKneeAngle,
      countRep: rep != null,
    );
  }

  @override
  void reset() {
    _t.reset();
    _lastRepFeedback = null;
    _lastRepOk = true;
  }
}

// ===========================================================================
// Bicep curl family — Seated dumbbell, Hammer, Barbell, Band, Cable curl
// ===========================================================================
// Key joint: elbow angle; a curl starts EXTENDED and flexes to a small angle.
// Fault: upper arm swinging forward (shoulder flexion — "cheating" the rep),
// measured as the hip-shoulder-elbow angle.
//
// Change from the original: SIDE-ON view instead of facing the camera. A curl
// moves the forearm in the sagittal plane — straight towards a front-facing
// camera — so a 2D front view foreshortens the forearm and under-reads the
// elbow angle. Side-on, the whole movement is in the image plane. Counting
// thresholds are also looser (70°/140°) than the full-ROM standard (50°) so
// half reps are counted and flagged instead of ignored.
class BicepCurlAnalyser implements PostureAnalyser {
  final _RepTracker _t = _RepTracker(
    workAt: FormThresholds.curlCountMax,
    restAt: FormThresholds.curlExtendedMin,
    workIsBelow: true,
  );

  String? _lastRepFeedback;
  bool _lastRepOk = true;

  @override
  int get repCount => _t.count;

  @override
  PostureResult analyse(List<Landmark> landmarks) {
    if (landmarks.length < 25) {
      return const PostureResult(
        isCorrect: false,
        feedback: 'Position yourself so your arm and hip are visible',
        phase: 'unknown',
      );
    }

    final side = _bestSide(
      landmarks,
      const [PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.leftElbow, PoseLandmarkIndex.leftWrist],
      const [PoseLandmarkIndex.rightShoulder, PoseLandmarkIndex.rightElbow, PoseLandmarkIndex.rightWrist],
    );
    if (side == null) {
      return const PostureResult(
        isCorrect: false,
        feedback: 'Arm not visible — stand side-on to the camera',
        phase: 'unknown',
      );
    }
    final shoulder = landmarks[_on(side, PoseLandmarkIndex.leftShoulder, PoseLandmarkIndex.rightShoulder)];
    final elbow = landmarks[_on(side, PoseLandmarkIndex.leftElbow, PoseLandmarkIndex.rightElbow)];
    final wrist = landmarks[_on(side, PoseLandmarkIndex.leftWrist, PoseLandmarkIndex.rightWrist)];
    final hip = landmarks[_on(side, PoseLandmarkIndex.leftHip, PoseLandmarkIndex.rightHip)];

    final elbowAngle = AngleCalculator.calculateAngle(shoulder, elbow, wrist);

    double? swing;
    if (hip.visibility >= FormThresholds.minVisibility) {
      swing = AngleCalculator.calculateAngle(hip, shoulder, elbow);
      _t.noteMax('swing', swing);
    }

    final rep = _t.update(elbowAngle);
    if (rep != null) {
      final romOk = rep.minAngle <= FormThresholds.curlFlexedMax;
      final maxSwing = rep.peaks['swing'];
      final swingOk = maxSwing == null || maxSwing <= FormThresholds.curlSwingMax;
      _lastRepOk = romOk && swingOk;
      _logRep('curl', _t.count, rep.minAngle, maxSwing, _lastRepOk);
      if (!romOk) {
        _lastRepFeedback = 'Rep ${_t.count}: half rep — curl all the way up';
      } else if (!swingOk) {
        _lastRepFeedback = 'Rep ${_t.count}: elbow swung forward — pin it to your side';
      } else {
        _lastRepFeedback = 'Rep ${_t.count} complete — strict rep!';
      }
    }

    final phase = _t.phase(elbowAngle,
        rest: 'extended', work: 'flexed', toward: 'curling', back: 'lowering');

    String feedback;
    bool isCorrect;
    if (swing != null && swing > FormThresholds.curlSwingMax) {
      feedback = 'Keep your elbow by your side — don\'t swing';
      isCorrect = false;
    } else if (phase == 'extended') {
      feedback = _lastRepFeedback ?? 'Arm extended — curl the weight up';
      isCorrect = _lastRepOk;
    } else if (phase == 'curling') {
      feedback = 'Keep curling — squeeze at the top';
      isCorrect = true;
    } else if (phase == 'flexed') {
      feedback = elbowAngle <= FormThresholds.curlFlexedMax
          ? 'Full contraction! Lower with control'
          : 'A bit higher — squeeze the bicep';
      isCorrect = true;
    } else {
      feedback = 'Lower slowly — full extension at the bottom';
      isCorrect = true;
    }

    return PostureResult(
      isCorrect: isCorrect,
      feedback: feedback,
      phase: phase,
      keyAngle: elbowAngle,
      countRep: rep != null,
    );
  }

  @override
  void reset() {
    _t.reset();
    _lastRepFeedback = null;
    _lastRepOk = true;
  }
}

// ===========================================================================
// Exercise → analyser routing
// ===========================================================================

enum _Family { squat, lunge, deadlift, rdl, pushUp, pikePushUp, bench, press, curl }

class ExerciseAnalyserFactory {
  /// Explicit routing for every exercise with hasPoseDetection == true.
  /// Exact names first, because substring matching alone mis-routes names
  /// like "Leg Curl" (→ bicep curl) or "Pike Push-Up" (→ plank check).
  /// A unit test asserts every pose-enabled exercise in kExercises is here.
  static const Map<String, _Family> _byName = {
    // Squats
    'bodyweight squat': _Family.squat,
    'barbell squat': _Family.squat,
    'resistance band squat': _Family.squat,
    'dumbbell goblet squat': _Family.squat,
    'barbell front squat': _Family.squat,
    // Lunges / split squats
    'forward lunge': _Family.lunge,
    'reverse lunge': _Family.lunge,
    'barbell lunge': _Family.lunge,
    'split squat': _Family.lunge,
    'bulgarian split squat': _Family.lunge,
    'dumbbell bulgarian split squat': _Family.lunge,
    // Hinges
    'barbell deadlift': _Family.deadlift,
    'barbell romanian deadlift': _Family.rdl,
    'dumbbell romanian deadlift': _Family.rdl,
    // Push-ups / bench
    'push-up': _Family.pushUp,
    'wide push-up': _Family.pushUp,
    'diamond push-up': _Family.pushUp,
    'close-grip push-up': _Family.pushUp,
    'incline push-up': _Family.pushUp,
    'decline push-up': _Family.pushUp,
    'pike push-up': _Family.pikePushUp,
    'barbell bench press': _Family.bench,
    // Overhead press
    'dumbbell shoulder press': _Family.press,
    'seated dumbbell shoulder press': _Family.press,
    'barbell overhead press': _Family.press,
    'arnold press': _Family.press,
    // Curls
    'dumbbell seated bicep curl': _Family.curl,
    'dumbbell hammer curl': _Family.curl,
    'barbell curl': _Family.curl,
    'resistance band bicep curl': _Family.curl,
    'cable bicep curl': _Family.curl,
  };

  /// True if [exerciseName] has an explicit analyser mapping.
  static bool hasExplicitMapping(String exerciseName) =>
      _byName.containsKey(exerciseName.trim().toLowerCase());

  static _Family _familyOf(String exerciseName) {
    final name = exerciseName.trim().toLowerCase();
    final exact = _byName[name];
    if (exact != null) return exact;

    // Fallback for names not in the table (e.g. custom names). Order matters.
    if (name.contains('romanian')) return _Family.rdl;
    if (name.contains('deadlift')) return _Family.deadlift;
    if (name.contains('lunge') || name.contains('split squat')) return _Family.lunge;
    if (name.contains('curl') && !name.contains('leg')) return _Family.curl;
    if (name.contains('squat')) return _Family.squat;
    if (name.contains('pike')) return _Family.pikePushUp;
    if (name.contains('push')) return _Family.pushUp;
    if (name.contains('bench')) return _Family.bench;
    if ((name.contains('press') || name.contains('shoulder')) && !name.contains('leg')) {
      return _Family.press;
    }
    return _Family.squat;
  }

  static PostureAnalyser getAnalyser(String exerciseName) {
    switch (_familyOf(exerciseName)) {
      case _Family.squat:
        return SquatAnalyser();
      case _Family.lunge:
        return LungeAnalyser();
      case _Family.deadlift:
        return DeadliftAnalyser();
      case _Family.rdl:
        return RomanianDeadliftAnalyser();
      case _Family.pushUp:
        return PushUpAnalyser();
      case _Family.pikePushUp:
        return PushUpAnalyser(variant: PushUpVariant.pike);
      case _Family.bench:
        return PushUpAnalyser(variant: PushUpVariant.bench);
      case _Family.press:
        return ShoulderPressAnalyser();
      case _Family.curl:
        return BicepCurlAnalyser();
    }
  }

  // Camera set-up instructions shown before the countdown.
  static String getInstructions(String exerciseName) {
    switch (_familyOf(exerciseName)) {
      case _Family.squat:
        return '📱 Place phone 2–3m away at hip height.\n🧍 Stand sideways — your full body must be visible from head to ankles.';
      case _Family.lunge:
        return '📱 Place phone 2–3m away at hip height.\n🧍 Stand sideways — both legs visible, and stay inside the frame (for split squats, include the bench).';
      case _Family.deadlift:
      case _Family.rdl:
        return '📱 Place phone 2–3m away at hip height.\n🧍 Stand sideways — full body from head to floor must be visible.';
      case _Family.pushUp:
      case _Family.pikePushUp:
        return '📱 Place phone on the floor 1m to your side, level with your body — not angled up.\n🧍 Face sideways — your full body from head to feet must be visible.';
      case _Family.bench:
        return '📱 Place phone at bench height, 1.5–2m to your side.\n🧍 Your shoulder, elbow and wrist nearest the camera must stay visible.';
      case _Family.press:
        return '📱 Place phone 2m away at chest height.\n🧍 Face the camera directly — both arms must be fully visible.';
      case _Family.curl:
        return '📱 Place phone 1.5–2m away at chest height.\n🧍 Stand (or sit) side-on — the arm nearest the camera and your hip must be visible.';
    }
  }
}
