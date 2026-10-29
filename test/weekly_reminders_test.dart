import 'package:flutter_test/flutter_test.dart';
import 'package:rakan/features/workout/services/notification_service.dart';

/// V-20: weekly reminders are built from the current plan; rest days get none.
void main() {
  test('one reminder per workout day, none for rest days', () {
    final reminders = NotificationService.weeklyReminderContent([
      {'dayNumber': 1, 'dayType': 'workout', 'workoutName': 'Push'},
      {'dayNumber': 2, 'dayType': 'rest', 'workoutName': 'Rest Day'},
      {'dayNumber': 3, 'dayType': 'workout', 'workoutName': 'Pull'},
      {'dayNumber': 7, 'dayType': 'rest', 'workoutName': 'Rest Day'},
    ]);
    expect(reminders.map((r) => r.weekday), [1, 3]);
    expect(reminders.first.body, contains('Push'));
    expect(reminders.any((r) => r.title.contains('Rest')), isFalse);
  });

  test('a day turned into a rest day loses its reminder', () {
    final before = NotificationService.weeklyReminderContent([
      {'dayNumber': 5, 'dayType': 'workout', 'workoutName': 'Legs'},
    ]);
    final after = NotificationService.weeklyReminderContent([
      {'dayNumber': 5, 'dayType': 'rest', 'workoutName': 'Rest Day'},
    ]);
    expect(before, hasLength(1));
    expect(after, isEmpty);
  });
}
