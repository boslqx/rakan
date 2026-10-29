import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rakan/features/auth/screens/register_screen.dart';
import 'package:rakan/features/legal/screens/legal_screen.dart';

void main() {
  setUpAll(() {
    // Avoid network font fetches in the test sandbox.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpRegister(WidgetTester tester) async {
    // Tall surface so the whole form fits without scrolling.
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
  }

  Future<void> fillValidForm(WidgetTester tester) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'athlete@example.com');
    await tester.enterText(fields.at(1), 'Strong!Pass1');
    await tester.enterText(fields.at(2), 'Strong!Pass1');
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.text('INITIALIZE ACCOUNT'));
    await tester.pump();
  }

  Checkbox termsCheckbox(WidgetTester tester) =>
      tester.widget<Checkbox>(find.byType(Checkbox));

  /// Real tap on the [label] part of the agreement sentence, so the gesture
  /// goes through the same arena as a finger would.
  Future<void> tapInSentence(WidgetTester tester, String label) async {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate((w) =>
          w is RichText && w.text.toPlainText().startsWith('I agree to the')),
    );
    final start = paragraph.text.toPlainText().indexOf(label);
    final box = paragraph
        .getBoxesForSelection(TextSelection(
          baseOffset: start,
          extentOffset: start + label.length,
        ))
        .first
        .toRect();
    await tester.tapAt(paragraph.localToGlobal(box.center));
    await tester.pumpAndSettle();
  }

  testWidgets('agreement box starts unticked', (tester) async {
    await pumpRegister(tester);
    expect(termsCheckbox(tester).value, isFalse);
    expect(
      find.textContaining('Terms & Conditions', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('blocks sign-up until terms are accepted', (tester) async {
    await pumpRegister(tester);
    await fillValidForm(tester);

    await submit(tester);

    expect(find.text('Please agree to continue'), findsOneWidget);
    // No sign-up attempt was made, so no error snackbar either.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('tapping the sentence ticks the box and clears the error',
      (tester) async {
    await pumpRegister(tester);
    await fillValidForm(tester);
    await submit(tester);
    expect(find.text('Please agree to continue'), findsOneWidget);

    await tapInSentence(tester, 'I agree');

    expect(find.byType(LegalScreen), findsNothing);
    expect(termsCheckbox(tester).value, isTrue);
    expect(find.text('Please agree to continue'), findsNothing);
  });

  testWidgets('with terms accepted, sign-up is attempted', (tester) async {
    await pumpRegister(tester);
    await fillValidForm(tester);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    await submit(tester);
    await tester.pump();

    expect(find.text('Please agree to continue'), findsNothing);
    // Firebase isn't initialised in tests, so the attempt fails and the
    // screen reports it — proving it got past the terms gate.
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('Google sign-up is blocked until terms are accepted',
      (tester) async {
    await pumpRegister(tester);

    await tester.tap(find.text('CONTINUE WITH GOOGLE'));
    await tester.pumpAndSettle();

    expect(find.text('Please agree to continue'), findsOneWidget);
    expect(
      find.textContaining('Please agree to the Terms', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('with terms accepted, Google sign-up is attempted',
      (tester) async {
    await pumpRegister(tester);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    await tester.tap(find.text('CONTINUE WITH GOOGLE'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Please agree to continue'), findsNothing);
    // Firebase isn't initialised in tests, so the attempt itself fails —
    // with a Firebase error, not the terms prompt.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.textContaining('Please agree to the Terms', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('links open the Terms and Privacy pages', (tester) async {
    await pumpRegister(tester);

    await tapInSentence(tester, 'Terms & Conditions');
    expect(find.byType(LegalScreen), findsOneWidget);
    expect(find.text('TERMS & CONDITIONS'), findsOneWidget);
    // Opening a link must not tick the box.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(termsCheckbox(tester).value, isFalse);

    await tapInSentence(tester, 'Privacy Policy');
    expect(find.text('PRIVACY POLICY'), findsOneWidget);
  });
}
