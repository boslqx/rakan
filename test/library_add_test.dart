import 'package:flutter_test/flutter_test.dart';
import 'package:rakan/features/workout/screens/exercise_detail_sheet.dart';

/// V-19: ADD TO WORKOUT from the library follows the day screen's rules.
void main() {
  final monday = {'id': 'mon', 'dayNumber': 1, 'dayType': 'workout', 'workoutName': 'Push'};
  final wednesday = {'id': 'wed', 'dayNumber': 3, 'dayType': 'workout', 'workoutName': 'Pull'};
  final planDays = [monday, wednesday];

  bool route(Map<String, dynamic> thisWeek, {bool over = false}) => addsThroughDayScreen(
        planDay: monday,
        thisWeek: thisWeek,
        planDays: planDays,
        over: over,
      );

  test('this week\'s session still to come opens the day (asks plan or just this time)', () {
    expect(route(monday), isTrue);
    // A one-time version of Monday this week (e.g. something added just
    // this time) is still Monday's session.
    expect(route({'dayType': 'workout', 'planDayId': 'mon', 'exercises': []}), isTrue);
  });

  test('a day that is over this week only changes the plan', () {
    expect(route(monday, over: true), isFalse);
  });

  test('a different session on that date this week is never overwritten', () {
    // Swapped: Wednesday's Pull is on Monday this week.
    expect(route({'dayType': 'workout', 'planDayId': 'wed'}), isFalse);
    // Moved away: Monday is a rest day this week.
    expect(route({'dayType': 'rest', 'planDayId': 'mon'}), isFalse);
    // A rescheduled session with no plan day behind it.
    expect(route({'dayType': 'workout', 'workoutName': 'Push'}), isFalse);
  });
}
