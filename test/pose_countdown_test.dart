import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rakan/features/workout/widgets/pose_countdown_overlay.dart';

/// V-22 / UT-GDE-03: the countdown only runs while the user is in view.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('counts down while visible, starts over while not', () {
    expect(PoseCountdownOverlay.nextRemaining(5, visible: true, total: 7), 4);
    expect(PoseCountdownOverlay.nextRemaining(5, visible: false, total: 7), 7);
  });

  Future<void> pumpOverlay(WidgetTester tester,
      {required bool visible, required VoidCallback onComplete}) {
    return tester.pumpWidget(MaterialApp(
      home: PoseCountdownOverlay(bodyVisible: visible, onComplete: onComplete),
    ));
  }

  testWidgets('never finishes while nobody is in view', (tester) async {
    var done = false;
    await pumpOverlay(tester, visible: false, onComplete: () => done = true);
    await tester.pump(const Duration(seconds: 20));
    expect(done, isFalse);
    expect(find.text('STEP INTO VIEW'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('losing the user mid-count starts it over', (tester) async {
    var done = false;
    void complete() => done = true;

    await pumpOverlay(tester, visible: true, onComplete: complete);
    await tester.pump(const Duration(seconds: 5)); // 2 left
    expect(find.text('2'), findsOneWidget);

    await pumpOverlay(tester, visible: false, onComplete: complete);
    await tester.pump(const Duration(seconds: 3));
    expect(done, isFalse);

    await pumpOverlay(tester, visible: true, onComplete: complete);
    await tester.pump(const Duration(seconds: 6));
    expect(done, isFalse); // needs the full 7 s in view again
    await tester.pump(const Duration(seconds: 1));
    expect(done, isTrue);
  });
}
