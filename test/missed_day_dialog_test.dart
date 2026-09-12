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

  Future<void> pumpDialog(
    WidgetTester tester, {
    required List<MissedDay> actionable,
    List<MissedDay> autoSkipped = const [],
    Future<List<DateTime>> Function(MissedDay item)? findValidRescheduleDaysOverride,
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
                findValidRescheduleDaysOverride:
                    findValidRescheduleDaysOverride ?? (_) async => const [],
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

  testWidgets('tapping Skip entirely calls the skip action and dismisses the card',
      (tester) async {
    var skipCalled = false;
    final item = MissedDay(muscleGroup: 'Chest', date: DateTime(2024, 1, 1));

    await pumpDialog(
      tester,
      actionable: [item],
      resolveSkippedOverride: (m) async {
        skipCalled = true;
      },
    );

    expect(find.text('Chest'), findsOneWidget);
    expect(find.text('SKIP ENTIRELY'), findsOneWidget);

    await tester.tap(find.text('SKIP ENTIRELY'));
    await tester.pumpAndSettle();

    expect(skipCalled, isTrue);
    // The only actionable item resolved and there's nothing read-only to
    // show, so the dialog closes itself.
    expect(find.byType(MissedDayDialog), findsNothing);
  });

  testWidgets('tapping Reschedule then a day calls the reschedule action with that '
      'date and dismisses the card', (tester) async {
    DateTime? rescheduledTo;
    final item = MissedDay(muscleGroup: 'Chest', date: DateTime(2024, 1, 1));
    final candidate = DateTime(2024, 1, 3); // a Wednesday

    await pumpDialog(
      tester,
      actionable: [item],
      findValidRescheduleDaysOverride: (_) async => [candidate],
      resolveRescheduledOverride: (m, target) async {
        rescheduledTo = target;
      },
    );

    expect(find.text('RESCHEDULE'), findsOneWidget);
    await tester.tap(find.text('RESCHEDULE'));
    await tester.pumpAndSettle();

    // The day picker is now showing the one candidate day.
    expect(find.text('WED 3/1'), findsOneWidget);
    await tester.tap(find.text('WED 3/1'));
    await tester.pumpAndSettle();

    expect(rescheduledTo, candidate);
    expect(find.byType(MissedDayDialog), findsNothing);
  });

  testWidgets(
      'resolving a non-last item does not leave a later item stuck loading '
      '(regression: per-item state must be keyed by identity, not list index)',
      (tester) async {
    final itemA = MissedDay(muscleGroup: 'Chest', date: DateTime(2024, 1, 1));
    final itemB = MissedDay(muscleGroup: 'Legs', date: DateTime(2024, 1, 2));

    await pumpDialog(
      tester,
      actionable: [itemA, itemB],
      findValidRescheduleDaysOverride: (_) async => const [],
      resolveSkippedOverride: (_) async {},
    );

    expect(find.text('SKIP ENTIRELY'), findsNWidgets(2));

    // Resolve the FIRST item, not the last — this is exactly what
    // shifted index-1's item into index 0 under the old implementation,
    // leaving it permanently stuck on the loading spinner because its
    // "candidates loaded" flag was recorded under the wrong key.
    await tester.tap(find.text('SKIP ENTIRELY').first);
    await tester.pumpAndSettle();

    expect(find.text('Chest'), findsNothing);
    expect(find.text('Legs'), findsOneWidget);
    expect(find.text('SKIP ENTIRELY'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
      'resolving one muscle group under a shared date header does not affect '
      'the other rows under that same header (regression: grouping by date '
      'must not reintroduce index-based state keying — see Decision #51)',
      (tester) async {
    final sameDate = DateTime(2024, 1, 6); // Sat 6/1
    final chest = MissedDay(muscleGroup: 'Chest', date: sameDate);
    final shoulders = MissedDay(muscleGroup: 'Shoulders', date: sameDate);
    final arms = MissedDay(muscleGroup: 'Arms', date: sameDate);

    await pumpDialog(
      tester,
      actionable: [chest, shoulders, arms],
      findValidRescheduleDaysOverride: (_) async => const [],
      resolveSkippedOverride: (_) async {},
    );

    // All three share one date header, not three repeated ones.
    expect(find.text('Sat 6/1'), findsOneWidget);
    expect(find.text('Chest'), findsOneWidget);
    expect(find.text('Shoulders'), findsOneWidget);
    expect(find.text('Arms'), findsOneWidget);
    expect(find.text('SKIP ENTIRELY'), findsNWidgets(3));

    // Resolve the middle row (Shoulders) — under the old index-keyed bug
    // this is exactly the case that would shift a sibling under the same
    // group into a stale slot and leave it stuck on a permanent spinner.
    await tester.tap(find.text('SKIP ENTIRELY').at(1));
    await tester.pumpAndSettle();

    expect(find.text('Shoulders'), findsNothing);
    // The date header survives — Chest and Arms are still under it, each
    // still independently actionable and not stuck loading.
    expect(find.text('Sat 6/1'), findsOneWidget);
    expect(find.text('Chest'), findsOneWidget);
    expect(find.text('Arms'), findsOneWidget);
    expect(find.text('SKIP ENTIRELY'), findsNWidgets(2));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Resolving the remaining two rows should make the whole date group
    // disappear along with the dialog (nothing actionable or read-only left).
    await tester.tap(find.text('SKIP ENTIRELY').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('SKIP ENTIRELY').first);
    await tester.pumpAndSettle();

    expect(find.text('Sat 6/1'), findsNothing);
    expect(find.byType(MissedDayDialog), findsNothing);
  });

  testWidgets('a failed skip keeps the card and surfaces an error instead of '
      'hanging or silently dismissing', (tester) async {
    final item = MissedDay(muscleGroup: 'Chest', date: DateTime(2024, 1, 1));

    await pumpDialog(
      tester,
      actionable: [item],
      resolveSkippedOverride: (_) async {
        throw Exception('write failed');
      },
    );

    await tester.tap(find.text('SKIP ENTIRELY'));
    await tester.pumpAndSettle();

    // Card is still there with its button restored — not a permanent
    // spinner, and not silently treated as resolved.
    expect(find.text('Chest'), findsOneWidget);
    expect(find.text('SKIP ENTIRELY'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('an empty candidate list offers only Skip entirely, no Reschedule button',
      (tester) async {
    final item = MissedDay(muscleGroup: 'Chest', date: DateTime(2024, 1, 1));

    await pumpDialog(
      tester,
      actionable: [item],
      findValidRescheduleDaysOverride: (_) async => const [],
    );

    expect(find.text('RESCHEDULE'), findsNothing);
    expect(find.text('SKIP ENTIRELY'), findsOneWidget);
  });

  testWidgets('auto-skipped misses collapse into one summary line, not individual '
      'cards, and never show a reschedule action', (tester) async {
    final autoSkipped = [
      MissedDay(muscleGroup: 'Chest', date: DateTime(2024, 1, 1)),
      MissedDay(muscleGroup: 'Legs', date: DateTime(2023, 12, 20)),
      MissedDay(muscleGroup: 'Back', date: DateTime(2023, 12, 10)),
    ];

    await pumpDialog(tester, actionable: const [], autoSkipped: autoSkipped);

    expect(find.textContaining('You also missed 3 workouts'), findsOneWidget);
    expect(find.text('SKIP ENTIRELY'), findsNothing);
    expect(find.text('RESCHEDULE'), findsNothing);

    await tester.tap(find.textContaining('You also missed 3 workouts'));
    await tester.pumpAndSettle();

    expect(find.textContaining('skipped'), findsNWidgets(3));

    // Nothing actionable, only read-only content -> an explicit close button.
    expect(find.text('GOT IT'), findsOneWidget);
  });
}
