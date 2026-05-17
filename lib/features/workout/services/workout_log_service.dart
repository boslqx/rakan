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
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('workoutLogs')
        .orderBy('completedAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs.map((d) => d.data()).toList();
  }
}