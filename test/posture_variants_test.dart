// Phase 29 — posture detection variants.
//
// Every pose here is a synthetic side-on stick figure built in UPRIGHT pixel
// space (+y down, (0,-1) = up), i.e. what AngleCalculator.toPixelSpace hands
// the analysers. Building them from segment directions means each test
// states the exact joint angle it is feeding in, so a failure points at a
// threshold, not at noisy data.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rakan/features/workout/data/exercise_data.dart';
import 'package:rakan/features/workout/services/angle_calculator.dart';

typedef P = (double, double);

/// Unit direction θ degrees CLOCKWISE from straight up (0 = up, 90 = +x).
P dir(double deg) {
  final r = deg * math.pi / 180;
  return (math.sin(r), -math.cos(r));
}

P step(P from, double deg, double len) {
  final d = dir(deg);
  return (from.$1 + d.$1 * len, from.$2 + d.$2 * len);
}

/// 33 landmarks, all hidden except the ones given (visibility 0.95).
List<Landmark> pose(Map<int, P> pts) {
  final out = List<Landmark>.generate(
    33,
    (_) => const Landmark(x: 0, y: 0, z: 0, visibility: 0.05),
  );
  pts.forEach((i, p) {
    out[i] = Landmark(x: p.$1, y: p.$2, z: 0, visibility: 0.95);
  });
  return out;
}

const _l = PoseLandmarkIndex.leftShoulder;
const _lh = PoseLandmarkIndex.leftHip;
const _lk = PoseLandmarkIndex.leftKnee;
const _la = PoseLandmarkIndex.leftAnkle;
const _le = PoseLandmarkIndex.leftElbow;
const _lw = PoseLandmarkIndex.leftWrist;

/// Side-on squat: inner knee angle [knee], trunk lean from vertical [lean].
List<Landmark> squatPose(double knee, double lean) {
  final shin = (180 - knee) / 3; // shin tilts forward as the knee bends
  const ankle = (300.0, 600.0);
  final k = step(ankle, shin, 100);
  final hip = step(k, shin + 180 + knee, 100);
  final sh = step(hip, lean, 120);
  return pose({_la: ankle, _lk: k, _lh: hip, _l: sh});
}

/// Side-on push-up with inner elbow angle [elbow]. [sag] bends the body
/// line at the hip (180 - sag). [pike] puts the hips at ~90°.
List<Landmark> pushUpPose(double elbow, {double sag = 0, bool pike = false}) {
  const wrist = (200.0, 500.0);
  final el = step(wrist, 0, 60);
  final sh = step(el, 180 - elbow, 60);
  final P hip;
  final P ankle;
  if (pike) {
    hip = step(sh, 45, 120);
    ankle = step(hip, 135, 150);
  } else {
    hip = step(sh, 90, 150);
    ankle = step(hip, 90 + sag, 150);
  }
  return pose({_lw: wrist, _le: el, _l: sh, _lh: hip, _la: ankle});
}

/// Side-on curl: inner elbow angle [elbow], upper arm swung forward [swing].
List<Landmark> curlPose(double elbow, double swing) {
  const sh = (300.0, 200.0);
  const hip = (300.0, 400.0);
  final el = step(sh, 180 - swing, 80);
  final wr = step(el, -swing + elbow, 80);
  return pose({_l: sh, _lh: hip, _le: el, _lw: wr});
}

/// Bulgarian split squat, front leg = left. The rear (right) knee stays bent
/// with its shin sloping back to the bench — the case the old "most bent
/// knee = front knee" rule got wrong.
List<Landmark> bulgarianPose(double frontKnee, {double lean = 10}) {
  const ankle = (400.0, 600.0);
  final shin = (180 - frontKnee) / 4;
  final k = step(ankle, shin, 100);
  final hip = step(k, shin + 180 + frontKnee, 100);
  final rearKnee = step(hip, 195, 100);
  final rearAnkle = step(rearKnee, 250, 100);
  final sh = step(hip, lean, 120);
  return pose({
    _la: ankle, _lk: k, _lh: hip, _l: sh,
    PoseLandmarkIndex.rightHip: hip,
    PoseLandmarkIndex.rightKnee: rearKnee,
    PoseLandmarkIndex.rightAnkle: rearAnkle,
  });
}

/// Front-on press: both arms with the given inner elbow angles.
List<Landmark> pressPose(double leftElbow, double rightElbow) {
  const ls = (250.0, 300.0);
  const rs = (350.0, 300.0);
  // Upper arms out to the sides, forearms rotate upward as the elbow opens.
  final le = step(ls, 270, 70);
  final re = step(rs, 90, 70);
  final lw = step(le, 90 - leftElbow, 70);
  final rw = step(re, 270 + rightElbow, 70);
  return pose({
    _l: ls, _le: le, _lw: lw,
    PoseLandmarkIndex.rightShoulder: rs,
    PoseLandmarkIndex.rightElbow: re,
    PoseLandmarkIndex.rightWrist: rw,
  });
}

/// Feeds frames in order and returns the result of the last one.
PostureResult run(PostureAnalyser a, List<List<Landmark>> frames) {
  late PostureResult r;
  for (final f in frames) {
    r = a.analyse(f);
  }
  return r;
}

void main() {
  group('Pose builders are exact', () {
    test('squat builder produces the requested knee angle and lean', () {
      final p = squatPose(65, 40);
      expect(AngleCalculator.calculateAngle(p[_lh], p[_lk], p[_la]), closeTo(65, 0.01));
      expect(AngleCalculator.angleFromVertical(p[_l], p[_lh]), closeTo(40, 0.01));
    });
  });

  group('AngleCalculator.toPixelSpace rotation', () {
    test('rotation 270 (front camera, portrait) makes the head point up', () {
      // Raw sensor frame: the painter treats larger raw x as higher on screen.
      const head = Landmark(x: 0.8, y: 0.5, z: 0, visibility: 1);
      const feet = Landmark(x: 0.2, y: 0.5, z: 0, visibility: 1);
      final up = AngleCalculator.toPixelSpace(
        [head, feet],
        frameWidth: 640,
        frameHeight: 480,
        rotationDegrees: 270,
      );
      expect(AngleCalculator.angleFromVertical(up[0], up[1]), closeTo(0, 0.001));
    });

    test('rotation does not change joint angles', () {
      const a = Landmark(x: 0.3, y: 0.2, z: 0, visibility: 1);
      const b = Landmark(x: 0.5, y: 0.5, z: 0, visibility: 1);
      const c = Landmark(x: 0.7, y: 0.4, z: 0, visibility: 1);
      final r0 = AngleCalculator.toPixelSpace([a, b, c], frameWidth: 640, frameHeight: 480);
      final r270 = AngleCalculator.toPixelSpace([a, b, c],
          frameWidth: 640, frameHeight: 480, rotationDegrees: 270);
      expect(
        AngleCalculator.calculateAngle(r270[0], r270[1], r270[2]),
        closeTo(AngleCalculator.calculateAngle(r0[0], r0[1], r0[2]), 0.001),
      );
    });
  });

  group('SquatAnalyser (corrected depth rule)', () {
    test('a parallel squat (65°) is CORRECT — no longer "too deep"', () {
      final a = SquatAnalyser();
      final r = run(a, [squatPose(180, 0), squatPose(120, 20), squatPose(65, 40), squatPose(120, 20), squatPose(178, 0)]);
      expect(a.repCount, 1);
      expect(r.countRep, isTrue);
      expect(r.isCorrect, isTrue);
    });

    test('a deep squat (45°) is correct', () {
      final a = SquatAnalyser();
      final r = run(a, [squatPose(180, 0), squatPose(45, 45), squatPose(178, 0)]);
      expect(a.repCount, 1);
      expect(r.isCorrect, isTrue);
    });

    test('a half squat (95°) is counted but flagged too shallow', () {
      final a = SquatAnalyser();
      final r = run(a, [squatPose(180, 0), squatPose(95, 30), squatPose(178, 0)]);
      expect(a.repCount, 1);
      expect(r.isCorrect, isFalse);
      expect(r.feedback, contains('shallow'));
    });

    test('excessive forward lean (70°) is flagged', () {
      final a = SquatAnalyser();
      final mid = a.analyse(squatPose(65, 70));
      expect(mid.isCorrect, isFalse);
      final r = a.analyse(squatPose(178, 0));
      expect(r.isCorrect, isFalse);
    });
  });

  group('LungeAnalyser — split squat variants', () {
    test('Bulgarian split squat counts reps although the rear knee stays bent', () {
      final a = LungeAnalyser();
      final r = run(a, [bulgarianPose(175), bulgarianPose(85), bulgarianPose(175)]);
      expect(a.repCount, 1);
      expect(r.isCorrect, isTrue);
    });

    test('torso leaning 45° in a split squat is flagged', () {
      final a = LungeAnalyser();
      final r = a.analyse(bulgarianPose(85, lean: 45));
      expect(r.isCorrect, isFalse);
    });
  });

  group('PushUpAnalyser variants', () {
    test('standard push-up to 85° with a straight body is correct', () {
      final a = PushUpAnalyser();
      final r = run(a, [pushUpPose(170), pushUpPose(85), pushUpPose(170)]);
      expect(a.repCount, 1);
      expect(r.isCorrect, isTrue);
    });

    test('a 115° push-up is counted but too shallow', () {
      final a = PushUpAnalyser();
      final r = run(a, [pushUpPose(170), pushUpPose(115), pushUpPose(170)]);
      expect(a.repCount, 1);
      expect(r.isCorrect, isFalse);
    });

    test('sagging hips (150° body line) are flagged live', () {
      final r = PushUpAnalyser().analyse(pushUpPose(150, sag: 30));
      expect(r.isCorrect, isFalse);
    });

    test('pike push-up is NOT flagged for its deliberate 90° hip angle', () {
      final a = PushUpAnalyser(variant: PushUpVariant.pike);
      final r = run(a, [
        pushUpPose(170, pike: true),
        pushUpPose(85, pike: true),
        pushUpPose(170, pike: true),
      ]);
      expect(a.repCount, 1);
      expect(r.isCorrect, isTrue);
    });
  });

  group('BicepCurlAnalyser (side-on)', () {
    test('strict full curl is correct', () {
      final a = BicepCurlAnalyser();
      final r = run(a, [curlPose(170, 5), curlPose(40, 10), curlPose(170, 5)]);
      expect(a.repCount, 1);
      expect(r.isCorrect, isTrue);
    });

    test('swinging the upper arm 40° forward is flagged', () {
      final a = BicepCurlAnalyser();
      final mid = a.analyse(curlPose(40, 40));
      expect(mid.isCorrect, isFalse);
      final r = run(a, [curlPose(170, 5)]);
      expect(a.repCount, 1);
      expect(r.isCorrect, isFalse);
    });

    test('a half curl (65°) is counted but flagged', () {
      final a = BicepCurlAnalyser();
      final r = run(a, [curlPose(170, 5), curlPose(65, 8), curlPose(170, 5)]);
      expect(a.repCount, 1);
      expect(r.isCorrect, isFalse);
    });
  });

  group('ShoulderPressAnalyser', () {
    test('even press to full lockout is correct', () {
      final a = ShoulderPressAnalyser();
      final r = run(a, [pressPose(90, 90), pressPose(170, 168), pressPose(90, 92)]);
      expect(a.repCount, 1);
      expect(r.isCorrect, isTrue);
    });

    test('partial lockout (150°) is counted but flagged', () {
      final a = ShoulderPressAnalyser();
      final r = run(a, [pressPose(90, 90), pressPose(150, 150), pressPose(90, 90)]);
      expect(a.repCount, 1);
      expect(r.isCorrect, isFalse);
    });

    test('one arm lagging by 40° is flagged', () {
      final r = ShoulderPressAnalyser().analyse(pressPose(165, 125));
      expect(r.isCorrect, isFalse);
    });
  });

  group('ExerciseAnalyserFactory routing', () {
    test('every pose-enabled exercise in the library has an explicit mapping', () {
      final unmapped = kExercises
          .where((e) => e.hasPoseDetection)
          .where((e) => !ExerciseAnalyserFactory.hasExplicitMapping(e.name))
          .map((e) => e.name)
          .toList();
      expect(unmapped, isEmpty);
    });

    test('variants route to the right analyser', () {
      expect(ExerciseAnalyserFactory.getAnalyser('Dumbbell Goblet Squat'), isA<SquatAnalyser>());
      expect(ExerciseAnalyserFactory.getAnalyser('Bulgarian Split Squat'), isA<LungeAnalyser>());
      expect(ExerciseAnalyserFactory.getAnalyser('Barbell Romanian Deadlift'),
          isA<RomanianDeadliftAnalyser>());
      expect(ExerciseAnalyserFactory.getAnalyser('Dumbbell Hammer Curl'), isA<BicepCurlAnalyser>());
      expect(ExerciseAnalyserFactory.getAnalyser('Arnold Press'), isA<ShoulderPressAnalyser>());
      final pike = ExerciseAnalyserFactory.getAnalyser('Pike Push-Up');
      expect(pike, isA<PushUpAnalyser>());
      expect((pike as PushUpAnalyser).variant, PushUpVariant.pike);
    });

    test('"Leg Curl" is not routed to the bicep curl analyser', () {
      expect(ExerciseAnalyserFactory.getAnalyser('Leg Curl'), isNot(isA<BicepCurlAnalyser>()));
    });
  });
}
