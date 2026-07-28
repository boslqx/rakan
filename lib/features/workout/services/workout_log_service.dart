import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/exercise_data.dart';
import '../data/muscle_recovery_constants.dart';

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

    // P1: refresh per-muscle recovery tracking after every save.
    try {
      await updateMuscleRecovery(uid);
    } catch (e) {
      // TODO: replace with proper logging once a logging strategy exists.
      print('updateMuscleRecovery failed for $uid: $e');
    }
  }

  /// Recomputes and writes per-muscle recovery data for [uid]
  Future<void> updateMuscleRecovery(String uid) async {
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));

    final logsSnapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('workoutLogs')
        .get();

    // Accumulated per broad muscle group across all logs in the window.
    final Map<String, double> weightedSets = {};
    final Map<String, double> rawVolume = {};
    final Map<String, DateTime> lastTrained = {};

    for (final logDoc in logsSnapshot.docs) {
      final logData = logDoc.data();
      final completedAtStr = logData['completedAt'] as String?;
      if (completedAtStr == null) continue;

      final completedAt = DateTime.tryParse(completedAtStr);
      if (completedAt == null || completedAt.isBefore(sevenDaysAgo)) {
        continue;
      }

      final exerciseLogsSnap =
          await logDoc.reference.collection('exerciseLogs').get();

      for (final exLogDoc in exerciseLogsSnap.docs) {
        final exLog = exLogDoc.data();
        final exerciseName = exLog['exerciseName'] as String?;
        if (exerciseName == null) continue;

        // Secondary muscles aren't stored on the log document — resolve
        // via the static exercise table (the standard lookup pattern used
        // elsewhere in this app, per findExerciseByName's own doc comment).
        final exerciseMeta = findExerciseByName(exerciseName);

        final primaryGroup =
            exLog['muscleGroup'] as String? ?? exerciseMeta?.muscleGroup;
        if (primaryGroup == null) continue;

        final setDetails =
            (exLog['setDetails'] as List?)?.cast<Map<String, dynamic>>() ??
                [];
        final completedSets =
            setDetails.where((s) => s['completed'] == true).toList();
        if (completedSets.isEmpty) continue;

        final setCount = completedSets.length;
        final volume = completedSets.fold<double>(0.0, (sum, s) {
          final reps = (s['reps'] as num?)?.toDouble() ?? 0;
          final weightKg = (s['weightKg'] as num?)?.toDouble() ?? 0;
          // Bodyweight sets contribute reps only, not reps × 0.
          return sum + (weightKg > 0 ? reps * weightKg : reps);
        });

        // Primary muscle: full credit.
        weightedSets[primaryGroup] =
            (weightedSets[primaryGroup] ?? 0) + setCount;
        rawVolume[primaryGroup] = (rawVolume[primaryGroup] ?? 0) + volume;
        _updateLastTrained(lastTrained, primaryGroup, completedAt);

        // Secondary muscles: partial credit, mapped down to broad groups.
        // A Set (not List) dedupes cases where two granular tags map to
        // the same broad group (e.g. 'Biceps' + 'Rear Deltoids' would
        // both be distinct groups here, but two chest-adjacent tags could
        // collapse to one) — avoids double-crediting the same broad group
        // twice from a single exercise.
        final secondaryGroups = (exerciseMeta?.secondaryMuscles ?? [])
            .map((m) => kGranularToBroadMuscleGroup[m])
            .whereType<String>()
            .toSet();

        for (final group in secondaryGroups) {
          weightedSets[group] =
              (weightedSets[group] ?? 0) + setCount * kSecondaryMuscleWeight;
          rawVolume[group] =
              (rawVolume[group] ?? 0) + volume * kSecondaryMuscleWeight;
          _updateLastTrained(lastTrained, group, completedAt);
        }
      }
    }

    if (weightedSets.isEmpty) return; // nothing trained in the window

    final batch = _db.batch();
    final muscleRecoveryRef =
        _db.collection('users').doc(uid).collection('muscleRecovery');

    for (final group in weightedSets.keys) {
      final mrv = kWeeklyMRVByMuscleGroup[group] ?? kFallbackWeeklyMRV;
      final fatigueScore = (weightedSets[group]! / mrv).clamp(0.0, 1.0);
      final recommendedRestDays = fatigueScore < kRestDayFatigueThreshold
          ? kDefaultRestDays
          : kElevatedRestDays;

      batch.set(
        muscleRecoveryRef.doc(group),
        {
          'muscleGroup': group,
          'lastTrained': lastTrained[group]?.toIso8601String(),
          'fatigueScore': fatigueScore,
          'volumeLast7Days': rawVolume[group],
          'weightedSetsLast7Days': weightedSets[group],
          'weeklyMrv': mrv,
          'recommendedRestDays': recommendedRestDays,
          'updatedAt': DateTime.now().toIso8601String(),
        },
      );
    }

    await batch.commit();
  }

  void _updateLastTrained(
      Map<String, DateTime> lastTrained, String group, DateTime completedAt) {
    final current = lastTrained[group];
    if (current == null || completedAt.isAfter(current)) {
      lastTrained[group] = completedAt;
    }
  }

  /// Reads current recovery status for all tracked muscle groups.

  Future<Map<String, Map<String, dynamic>>> getMuscleRecoveryStatus(
      String uid) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('muscleRecovery')
        .get();

    return {
      for (final doc in snapshot.docs) doc.id: doc.data(),
    };
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