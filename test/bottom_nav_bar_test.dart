import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakan/shared/widgets/bottom_nav_bar.dart';

void main() {
  Widget bar(int currentIndex, {ValueChanged<int>? onTap}) {
    return MaterialApp(
      home: Scaffold(
        bottomNavigationBar: RakanBottomNavBar(
          currentIndex: currentIndex,
          onTap: onTap ?? (_) {},
        ),
      ),
    );
  }

  testWidgets('each tab reports its own index', (tester) async {
    final tapped = <int>[];
    await tester.pumpWidget(bar(0, onTap: tapped.add));

    for (final label in ['Dashboard', 'Schedule', 'Coach', 'Settings']) {
      await tester.tap(find.bySemanticsLabel('$label tab'));
      await tester.pump();
    }

    expect(tapped, [0, 1, 2, 3]);
  });

  testWidgets('every tab shows its name', (tester) async {
    await tester.pumpWidget(bar(0));

    for (final label in ['Dashboard', 'Schedule', 'Coach', 'Settings']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('very large system text does not overflow the bar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(bar(0));

    expect(tester.takeException(), isNull);
  });

  testWidgets('only the selected tab shows its filled icon', (tester) async {
    await tester.pumpWidget(bar(0));
    expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
    expect(find.byIcon(Icons.settings_rounded), findsNothing);

    await tester.pumpWidget(bar(3));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.grid_view_rounded), findsNothing);
    expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
  });

  testWidgets('the selected tab opens filled, without animating', (
    tester,
  ) async {
    await tester.pumpWidget(bar(2));

    // On the very first frame the outline has already faded out completely.
    final outline = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byIcon(Icons.auto_awesome_outlined),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(outline.opacity, 0);
    expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
  });

  testWidgets('screen readers get the label and the selected state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(bar(1));

    expect(
      tester.getSemantics(find.bySemanticsLabel('Schedule tab')),
      isSemantics(isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Coach tab')),
      isSemantics(isButton: true, isSelected: false),
    );

    semantics.dispose();
  });

  testWidgets('tabs meet the tap target guideline on a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(bar(0));

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    semantics.dispose();
  });
}
