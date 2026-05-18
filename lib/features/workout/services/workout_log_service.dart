import 'package:cloud_firestore/cloud_firestore.dart';

class WorkoutLogService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Saves a completed workout log to Firestore.
  /// Path: users/{uid}/workoutLogs/{logId}
  Future<void> saveWorkoutLog({
    required String uid,
    required Map<String, dynamic> log,
  }) async {
    final logRef = _db
        .collection('users')
        .doc(uid)
        .collection('workoutLogs')
        .doc(log['logId'] as String);

    // Save top-level log
    await logRef.set({
      'logId': log['logId'],
      'planId': log['planId'],
      'dayPlanId': log['dayPlanId'],
      'workoutName': log['workoutName'],
      'startedAt': log['startedAt'],
      'completedAt': log['completedAt'],
      'totalDurationMins': log['totalDurationMins'],
      'totalVolume': log['totalVolume'],
      'isCompleted': true,
    });

    // Save each exercise log as subcollection
    final exercises = log['exerciseLogs'] as List<Map<String, dynamic>>;
    for (final ex in exercises) {
      await logRef
          .collection('exerciseLogs')
          .doc(ex['exerciseLogId'] as String)
          .set(ex);
    }
  }

  /// Fetches recent workout logs for the home screen activity feed.
  Future<List<Map<String, dynamic>>> getRecentLogs(String uid,
      {int limit = 10}) async {
    // Fetch all logs and sort in Dart to avoid Firestore index requirement
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('workoutLogs')
        .get();

    final logs = snapshot.docs.map((d) => d.data()).toList();

    // Sort by completedAt descending in Dart
    logs.sort((a, b) {
      final aDate = a['completedAt'] as String? ?? '';
      final bDate = b['completedAt'] as String? ?? '';
      return bDate.compareTo(aDate);
    });

    return logs.take(limit).toList();
  }
}