import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rakan/features/home/widgets/missed_day_dialog.dart';
import 'package:rakan/features/workout/services/adapt_service.dart';

void main() {
  setUpAll(() {
    // Avoid network font fetches in the test sandbox.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  MissedDay missed(DateTime date, String workoutName,
          [List<String> muscleGroups = const ['Chest']]) =>
      MissedDay(date: date, workoutName: workoutName, muscleGroups: muscleGroups);

  Future<void> pumpDialog(
    WidgetTester tester, {
    required List<MissedDay> actionable,
    List<MissedDay> autoSkipped = const [],
    Future<List<DateTime>> Function(MissedDay item)? findRescheduleDaysOverride,
    Future<void> Function(MissedDay item)? resolveSkippedOverride,
    Future<void> Function(MissedDay item, DateTime target)? resolveRescheduledOverride,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => MissedDayDialog(
                uid: 'test-uid',
                actionable: actionable,
                autoSkipped: autoSkipped,
                findRescheduleDaysOverride:
                    findRescheduleDaysOverride ?? (_) async => const [],
                resolveSkippedOverride: resolveSkippedOverride,
                resolveRescheduledOverride: resolveRescheduledOverride,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Taps SKIP on a card, then confirms in the follow-up dialog.
  Future<void> skipAndConfirm(WidgetTester tester, Finder skipButton) async {
    await tester.tap(skipButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('SKIP SESSION'));
    await tester.pumpAndSettle();
  }

  testWidgets('one card per missed session, with the muscle groups it trains',
      (tester) async {
    await pumpDialog(tester, actionable: [
      missed(DateTime(2024, 1, 1), 'Push', ['Chest', 'Shoulders', 'Arms']),
    ]);

    expect(find.text('Push'), findsOneWidget);
    expect(find.text('Chest · Shoulders · Arms'), findsOneWidget);
    expect(find.text('SKIP'), findsOneWidget);
  });

  testWidgets('skipping asks to confirm first, then calls the skip action and '
      'dismisses the card', (tester) async {
    var skipCalled = false;
    final item = missed(DateTime(2024, 1, 1), 'Push', ['Chest', 'Shoulders']);

    await pumpDialog(
      tester,
      actionable: [item],
      resolveSkippedOverride: (m) async {
        skipCalled = true;
      },
    );

    await tester.tap(find.text('SKIP'));
    await tester.pumpAndSettle();

    // Asked, not yet skipped.
    expect(find.text("Skip Monday's Push?"), findsOneWidget);
    expect(find.textContaining('a break for Chest and Shoulders'), findsOneWidget);
    expect(skipCalled, isFalse);

    await tester.tap(find.text('SKIP SESSION'));
    await tester.pumpAndSettle();

    expect(skipCalled, isTrue);
    // The only actionable item resolved and there's nothing read-only to
    // show, so the dialog closes itself.
    expect(find.byType(MissedDayDialog), findsNothing);
  });

  testWidgets('cancelling the skip confirmation leaves the session untouched',
      (tester) async {
    var skipCalled = false;

    await pumpDialog(
      tester,
      actionable: [missed(DateTime(2024, 1, 1), 'Push')],
      resolveSkippedOverride: (_) async {
        skipCalled = true;
      },
    );

    await tester.tap(find.text('SKIP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();

    expect(skipCalled, isFalse);
    expect(find.text('Push'), findsOneWidget);
    expect(find.text('SKIP'), findsOneWidget);
  });

  testWidgets('moving to a rest day calls the reschedule action with that date '
      'and dismisses the card', (tester) async {
    DateTime? rescheduledTo;
    final candidate = DateTime(2024, 1, 3); // a Wednesday

    await pumpDialog(
      tester,
      actionable: [missed(DateTime(2024, 1, 1), 'Push')],
      findRescheduleDaysOverride: (_) async => [candidate],
      resolveRescheduledOverride: (m, target) async {
        rescheduledTo = target;
      },
    );

    await tester.tap(find.text('MOVE TO A REST DAY'));
    await tester.pumpAndSettle();

    // The day picker is now showing the one candidate day.
    expect(find.text('WED 3/1'), findsOneWidget);
    await tester.tap(find.text('WED 3/1'));
    await tester.pumpAndSettle();

    expect(rescheduledTo, candidate);
    expect(find.byType(MissedDayDialog), findsNothing);
  });

  testWidgets(
      'resolving a non-last session does not leave a later one stuck loading '
      '(regression: per-item state must be keyed by identity, not list index)',
      (tester) async {
    await pumpDialog(
      tester,
      actionable: [
        missed(DateTime(2024, 1, 1), 'Push'),
        missed(DateTime(2024, 1, 2), 'Legs'),
      ],
      resolveSkippedOverride: (_) async {},
    );

    expect(find.text('SKIP'), findsNWidgets(2));

    // Resolve the FIRST item, not the last — this is exactly what
    // shifted index-1's item into index 0 under the old implementation,
    // leaving it permanently stuck on the loading spinner because its
    // "candidates loaded" flag was recorded under the wrong key.
    await skipAndConfirm(tester, find.text('SKIP').first);

    expect(find.text('Push'), findsNothing);
    expect(find.text('Legs'), findsOneWidget);
    expect(find.text('SKIP'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failed skip keeps the card and surfaces an error instead of '
      'hanging or silently dismissing', (tester) async {
    await pumpDialog(
      tester,
      actionable: [missed(DateTime(2024, 1, 1), 'Push')],
      resolveSkippedOverride: (_) async {
        throw Exception('write failed');
      },
    );

    await skipAndConfirm(tester, find.text('SKIP'));

    // Card is still there with its button restored — not a permanent
    // spinner, and not silently treated as resolved.
    expect(find.text('Push'), findsOneWidget);
    expect(find.text('SKIP'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('with no free rest day, only Skip is offered — and says why',
      (tester) async {
    await pumpDialog(
      tester,
      actionable: [missed(DateTime(2024, 1, 1), 'Push')],
      findRescheduleDaysOverride: (_) async => const [],
    );

    expect(find.text('MOVE TO A REST DAY'), findsNothing);
    expect(find.textContaining('No rest day is free'), findsOneWidget);
    expect(find.text('SKIP'), findsOneWidget);
  });

  testWidgets('auto-skipped misses collapse into one summary line, not individual '
      'cards, and never show a move action', (tester) async {
    final autoSkipped = [
      missed(DateTime(2024, 1, 1), 'Push'),
      missed(DateTime(2023, 12, 20), 'Legs'),
      missed(DateTime(2023, 12, 10), 'Pull'),
    ];

    await pumpDialog(tester, actionable: const [], autoSkipped: autoSkipped);

    expect(find.textContaining('You also missed 3 workouts'), findsOneWidget);
    expect(find.text('SKIP'), findsNothing);
    expect(find.text('MOVE TO A REST DAY'), findsNothing);

    await tester.tap(find.textContaining('You also missed 3 workouts'));
    await tester.pumpAndSettle();

    expect(find.textContaining('skipped'), findsNWidgets(3));
    expect(find.textContaining('Push —'), findsOneWidget);

    // Nothing actionable, only read-only content -> an explicit close button.
    expect(find.text('GOT IT'), findsOneWidget);
  });
}
