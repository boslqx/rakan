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

  /// Finds the most recent weight the user logged for a specific exercise,
  /// by name. Used to prefill the weight field on the active workout screen
  /// so users don't have to type it in every session.
  ///
  /// Scans the user's most recent workout logs (newest first, same
  /// in-Dart-sort pattern as [getRecentLogs] to avoid requiring a new
  /// Firestore composite index), and for each one checks whether its
  /// `exerciseLogs` subcollection contains this exercise. Returns the last
  /// non-zero weight recorded for it, or null if the exercise has never
  /// been logged before (first time doing it, or bodyweight-only history).
  ///
  /// [scanLimit] bounds how many past logs we're willing to check, so a
  /// long-time user's history doesn't turn this into an expensive scan.
  Future<double?> getLastWeightForExercise({
    required String uid,
    required String exerciseName,
    int scanLimit = 15,
  }) async {
    final snapshot =
        await _db.collection('users').doc(uid).collection('workoutLogs').get();

    final logs = snapshot.docs.map((d) => d.data()).toList();
    logs.sort((a, b) {
      final aDate = a['completedAt'] as String? ?? '';
      final bDate = b['completedAt'] as String? ?? '';
      return bDate.compareTo(aDate);
    });

    for (final log in logs.take(scanLimit)) {
      final logId = log['logId'] as String?;
      if (logId == null) continue;

      final exerciseLogsSnap = await _db
          .collection('users')
          .doc(uid)
          .collection('workoutLogs')
          .doc(logId)
          .collection('exerciseLogs')
          .where('exerciseName', isEqualTo: exerciseName)
          .limit(1)
          .get();

      if (exerciseLogsSnap.docs.isEmpty) continue;

      final data = exerciseLogsSnap.docs.first.data();

      // Prefer the last completed set's weight (most representative of
      // where the user ended up that session), falling back to the
      // top-level weightKg field if setDetails is missing.
      final setDetails =
          (data['setDetails'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final set in setDetails.reversed) {
        final w = (set['weightKg'] as num?)?.toDouble() ?? 0;
        if (w > 0) return w;
      }

      final topLevelWeight = (data['weightKg'] as num?)?.toDouble() ?? 0;
      if (topLevelWeight > 0) return topLevelWeight;
    }

    return null; // No prior history found for this exercise
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