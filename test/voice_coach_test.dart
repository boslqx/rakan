import 'package:flutter_test/flutter_test.dart';
import 'package:rakan/features/workout/services/voice_coach.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records what would have been said.
class _FakeSpeaker implements CueSpeaker {
  final said = <String>[];
  int stops = 0;

  @override
  Future<void> speak(String text) async => said.add(text);

  @override
  Future<void> stop() async => stops++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSpeaker speaker;
  late DateTime now;
  late VoiceCoach coach;

  void wait(int ms) => now = now.add(Duration(milliseconds: ms));

  /// Feeds [message] as every frame of [ms] at 30 fps.
  void hold(String? message, int ms) {
    for (var t = 0; t < ms; t += 33) {
      coach.fault(message);
      wait(33);
    }
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    speaker = _FakeSpeaker();
    now = DateTime(2026, 1, 1);
    coach = VoiceCoach(speaker: speaker, clock: () => now);
  });

  group('VoiceCoach.speakable', () {
    test('drops angle readouts and reads dashes as pauses', () {
      expect(VoiceCoach.speakable("Chest up — you're leaning too far forward (23°)"),
          "Chest up, you're leaning too far forward");
    });

    test('reads the degree sign', () {
      expect(VoiceCoach.speakable('Elbows to 90°'), 'Elbows to 90 degrees');
    });
  });

  group('rep cues', () {
    test('a good rep is just its number', () {
      coach.rep(3, good: true, verdict: 'Rep 3 complete — good depth!');
      expect(speaker.said, ['3']);
    });

    test('a bad rep says what went wrong, without the rep prefix', () {
      coach.rep(4,
          good: false,
          verdict: 'Rep 4: too shallow (85°) — sink until thighs are parallel');
      expect(speaker.said, ['4. Too shallow, sink until thighs are parallel']);
    });

    test('a new rep cuts off the last one', () {
      coach.rep(1, good: false, verdict: 'Rep 1: leaned too far forward — keep your chest up');
      wait(200);
      coach.rep(2, good: true);
      expect(speaker.said.last, '2');
    });
  });

  group('form faults', () {
    const fault = 'Keep your elbow by your side — don\'t swing';

    test('a fault that flickers is never said', () {
      for (var i = 0; i < 60; i++) {
        coach.fault(i.isEven ? fault : null);
        wait(33);
      }
      expect(speaker.said, isEmpty);
    });

    test('a fault held for a second is said once', () {
      hold(fault, 1200);
      expect(speaker.said, ["Keep your elbow by your side, don't swing"]);
    });

    test('a persisting fault repeats only after the cooldown', () {
      hold(fault, 4500);
      expect(speaker.said, hasLength(1));
      hold(fault, 2000);
      expect(speaker.said, hasLength(2));
    });

    test('a fault never talks over a rep count', () {
      hold(fault, 900);
      coach.rep(5, good: false, verdict: 'Rep 5: elbow swung forward — pin it to your side');
      hold(fault, 200); // held long enough, but the rep is still being said
      expect(speaker.said, ['5. Elbow swung forward, pin it to your side']);
      hold(fault, 4000);
      expect(speaker.said.last, "Keep your elbow by your side, don't swing");
    });

    test('a rep count cuts off a fault', () {
      hold(fault, 1100);
      coach.rep(6, good: true);
      expect(speaker.said.last, '6');
    });

    test("the last rep's verdict, still on screen, isn't said again", () {
      const verdict = 'Rep 2: half rep — curl all the way up';
      coach.rep(2, good: false, verdict: verdict);
      hold(verdict, 8000);
      expect(speaker.said, hasLength(1));
    });

    test('a new set forgets the last set', () {
      hold(fault, 1200);
      wait(3000); // a short rest — still inside the fault's cooldown
      coach.resetForSet();
      hold(fault, 1200);
      expect(speaker.said, hasLength(2));
    });
  });

  group('mute', () {
    test('muted, nothing is said', () async {
      await coach.setEnabled(false);
      coach.rep(1, good: true);
      coach.say('Set 1 done.');
      expect(speaker.said, isEmpty);
    });

    test('muting stops what is being said', () async {
      coach.say('Set 1 done. Rest 90 seconds.');
      await coach.setEnabled(false);
      expect(speaker.stops, 1);
    });

    test('is remembered', () async {
      await coach.setEnabled(false);
      final next = VoiceCoach(speaker: speaker, clock: () => now);
      await next.loadEnabled();
      expect(next.enabled, isFalse);
    });
  });
}
