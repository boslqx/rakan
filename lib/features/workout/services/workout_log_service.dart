import 'package:cloud_firestore/cloud_firestore.dart';

class WorkoutLogService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Saves a completed workout log to Firestore.
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
      'totalSetsCompleted': log['totalSetsCompleted'],
      'prReached': log['prReached'] ?? false,
      'prExerciseNames': log['prExerciseNames'] ?? [],
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

  /// Finds the most recent weight the user logged for a specific exercise
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

      // Prefer the last completed set's weight
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

  /// Finds the heaviest weight ever logged for a specific exercise
  Future<double?> getMaxWeightForExercise({
    required String uid,
    required String exerciseName,
    int scanLimit = 30,
  }) async {
    final snapshot =
        await _db.collection('users').doc(uid).collection('workoutLogs').get();

    final logs = snapshot.docs.map((d) => d.data()).toList();
    logs.sort((a, b) {
      final aDate = a['completedAt'] as String? ?? '';
      final bDate = b['completedAt'] as String? ?? '';
      return bDate.compareTo(aDate);
    });

    double? runningMax;

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
      final setDetails =
          (data['setDetails'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      for (final set in setDetails) {
        final w = (set['weightKg'] as num?)?.toDouble() ?? 0;
        if (w > 0 && (runningMax == null || w > runningMax!)) {
          runningMax = w;
        }
      }
    }

    return runningMax;
  }

  /// Fetches the per-exercise breakdown 
  Future<List<Map<String, dynamic>>> getExerciseLogsForWorkout({
    required String uid,
    required String logId,
  }) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('workoutLogs')
        .doc(logId)
        .collection('exerciseLogs')
        .get();

    return snapshot.docs.map((d) => d.data()).toList();
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