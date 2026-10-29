import 'package:flutter_test/flutter_test.dart';
import 'package:rakan/features/workout/services/workout_log_service.dart';

/// V-11: recovery scores follow the 7-day window, not the last save.
void main() {
  final now = DateTime(2026, 10, 29, 12);
  final since = now.subtract(const Duration(days: 7));

  // Not in the exercise table, so no secondary muscles are credited.
  Map<String, dynamic> exLog(String group, int sets) => {
        'exerciseName': 'Test Exercise',
        'muscleGroup': group,
        'setDetails': [
          for (var i = 0; i < sets; i++)
            {'reps': 10, 'weightKg': 20, 'completed': true},
        ],
      };

  RecoverySession session(int daysAgo, List<Map<String, dynamic>> logs) =>
      (completedAt: now.subtract(Duration(days: daysAgo)), exerciseLogs: logs);

  test('a group trained 6 days ago at 0.75 keeps only what is in the window', () {
    final docs = WorkoutLogService.computeRecoveryDocs(
      sessions: [
        session(6, [exLog('Chest', 15)]), // 15 / MRV 20 = 0.75
        session(9, [exLog('Chest', 10)]), // left the window
      ],
      since: since,
      trackedGroups: const ['Chest'],
      now: now,
    );
    expect(docs['Chest']!['fatigueScore'], 0.75);
    expect(docs['Chest']!['weightedSetsLast7Days'], 15);
    expect(docs['Chest']!['lastTrained'],
        now.subtract(const Duration(days: 6)).toIso8601String());
  });

  test('older sessions no longer count once they leave the window', () {
    // Saved 3 days ago: Mon + Tue + Wed added up to 0.75. Today only Wed
    // is still inside the 7 days.
    final docs = WorkoutLogService.computeRecoveryDocs(
      sessions: [
        session(5, [exLog('Legs', 5)]),
        session(8, [exLog('Legs', 5)]),
        session(9, [exLog('Legs', 5)]),
      ],
      since: since,
      trackedGroups: const ['Legs'],
      now: now,
    );
    expect(docs['Legs']!['fatigueScore'], 0.25);
  });

  test('a tracked group with no sets left is reset to zero, keeping lastTrained',
      () {
    final docs = WorkoutLogService.computeRecoveryDocs(
      sessions: [session(2, [exLog('Back', 4)])],
      since: since,
      trackedGroups: const ['Back', 'Core'],
      now: now,
    );
    expect(docs['Core']!['fatigueScore'], 0.0);
    expect(docs['Core']!['weightedSetsLast7Days'], 0.0);
    // Written with merge, so the stored lastTrained is left alone.
    expect(docs['Core']!.containsKey('lastTrained'), isFalse);
    expect(docs['Back']!['fatigueScore'], 0.2);
  });

  test('groups never trained get no document', () {
    final docs = WorkoutLogService.computeRecoveryDocs(
      sessions: const [],
      since: since,
      trackedGroups: const [],
      now: now,
    );
    expect(docs, isEmpty);
  });
}
