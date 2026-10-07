import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../data/exercise_data.dart';
import '../data/muscle_recovery_constants.dart';
import 'schedule_matcher.dart';

/// Per-exercise weight history, built from ONE pass over recent logs
/// (see [WorkoutLogService.getWeightHistory]).
class ExerciseWeightHistory {
  /// Most recent logged working weight (kg > 0), or null if never logged.
  final double? lastWeight;

  /// Heaviest weight ever logged in the scanned window, or null.
  final double? maxWeight;

  /// One max weight per session that logged this exercise, oldest-first.
  final List<double> sessionMaxesOldestFirst;

  const ExerciseWeightHistory({
    required this.lastWeight,
    required this.maxWeight,
    required this.sessionMaxesOldestFirst,
  });

  static const empty = ExerciseWeightHistory(
    lastWeight: null,
    maxWeight: null,
    sessionMaxesOldestFirst: [],
  );
}

class WorkoutLogService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// How long to wait for the server to acknowledge a workout save before
  /// treating it as "queued offline". Firestore applies the write to its
  /// local cache immediately and syncs it once the device is back online,
  /// but the commit() future only completes on the server's ack — awaiting
  /// it with no limit made the Complete button spin forever with no signal.
  static const Duration _saveAckTimeout = Duration(seconds: 15);

  CollectionReference<Map<String, dynamic>> _logs(String uid) =>
      _db.collection('users').doc(uid).collection('workoutLogs');

  /// Saves a completed workout log to Firestore.
  ///
  /// Every document (the log, its exercise logs, the follower feed copy and
  /// the session counter) is written in ONE batch, so a failure can no
  /// longer leave a log without its exercises or a feed entry without a
  /// log. Returns true if the server confirmed the save, false if it was
  /// queued locally (offline) and will sync later. Throws only if the write
  /// was rejected outright (e.g. permissions).
  Future<bool> saveWorkoutLog({
    required String uid,
    required Map<String, dynamic> log,
  }) async {
    final logId = log['logId'] as String;
    final logRef = _logs(uid).doc(logId);
    final batch = _db.batch();

    batch.set(logRef, {
      'logId': log['logId'],
      'planId': log['planId'],
      'dayPlanId': log['dayPlanId'],
      'workoutName': log['workoutName'],
      'startedAt': log['startedAt'],
      'completedAt': log['completedAt'],
      'totalDurationMins': log['totalDurationMins'],
      'totalVolume': log['totalVolume'],
      'totalSetsCompleted': log['totalSetsCompleted'],
      'totalSetsPlanned': log['totalSetsPlanned'],
      'completionRate': log['completionRate'],
      'prReached': log['prReached'] ?? false,
      'prExerciseNames': log['prExerciseNames'] ?? [],
      'isCompleted': true,
    });

    final exercises = log['exerciseLogs'] as List<Map<String, dynamic>>;
    for (final ex in exercises) {
      batch.set(
        logRef.collection('exerciseLogs').doc(ex['exerciseLogId'] as String),
        ex,
      );
    }

    // Thin denormalized copy for followers — deliberately excludes
    // per-set weights/reps (totalVolume, exerciseLogs), only the same
    // summary fields the Home feed card shows. See PublicProfileService /
    // firestore.rules for why this lives in a separate subcollection
    // instead of exposing workoutLogs itself to non-owners.
    batch.set(
      _db.collection('users').doc(uid).collection('activityFeed').doc(logId),
      {
        'workoutName': log['workoutName'],
        'completedAt': log['completedAt'],
        'totalDurationMins': log['totalDurationMins'],
        'totalSetsCompleted': log['totalSetsCompleted'],
        'prReached': log['prReached'] ?? false,
      },
    );

    batch.set(
      _db.collection('users').doc(uid),
      {'totalSessionsLogged': FieldValue.increment(1)},
      SetOptions(merge: true),
    );

    bool confirmed = true;
    try {
      await batch.commit().timeout(_saveAckTimeout);
    } on TimeoutException {
      // Already applied to the local cache; Firestore will sync it.
      confirmed = false;
    }

    // P1: refresh per-muscle recovery tracking after every save. Skipped
    // when offline — it would only recompute from cached data, and runs
    // again after the next online save.
    if (confirmed) {
      try {
        await updateMuscleRecovery(uid);
      } catch (e) {
        debugPrint('updateMuscleRecovery failed for $uid: $e');
      }
    }
    return confirmed;
  }

  /// Saves a progress photo for a log. Photos live in their own
  /// `progressPhotos/{logId}` doc rather than on the workout log: they are
  /// ~100 KB of base64 each, and every history query that reads workout
  /// logs would otherwise download every photo too.
  Future<void> saveProgressPhoto({
    required String uid,
    required String logId,
    required String photoBase64,
  }) async {
    final batch = _db.batch();
    batch.set(
      _db.collection('users').doc(uid).collection('progressPhotos').doc(logId),
      {'photoBase64': photoBase64, 'logId': logId},
    );
    // Small flag so lists know a photo exists without downloading it.
    batch.update(_logs(uid).doc(logId), {'hasProgressPhoto': true});
    try {
      await batch.commit().timeout(_saveAckTimeout);
    } on TimeoutException {
      // Queued locally while offline; Firestore syncs it later.
    }
  }

  /// One-off migration: moves photos older versions stored inline on the
  /// workout log (`progressPhotoBase64`) into `progressPhotos/{logId}`, so
  /// history queries stop downloading them. Safe to call repeatedly —
  /// once nothing is left to move, the query returns no documents.
  /// Fire-and-forget: never throws.
  Future<void> migrateLegacyProgressPhotos(String uid) async {
    try {
      final legacy = await _logs(uid)
          .where('progressPhotoBase64', isNotEqualTo: null)
          .get();
      if (legacy.docs.isEmpty) return;

      final photos =
          _db.collection('users').doc(uid).collection('progressPhotos');
      // 2 writes per log; stay well under the 500-writes-per-batch limit
      const perBatch = 200;
      for (int i = 0; i < legacy.docs.length; i += perBatch) {
        final batch = _db.batch();
        for (final doc in legacy.docs.skip(i).take(perBatch)) {
          final photo = doc.data()['progressPhotoBase64'] as String?;
          if (photo != null && photo.isNotEmpty) {
            batch.set(photos.doc(doc.id),
                {'photoBase64': photo, 'logId': doc.id});
          }
          batch.update(doc.reference, {
            'progressPhotoBase64': FieldValue.delete(),
            'hasProgressPhoto': photo != null && photo.isNotEmpty,
          });
        }
        await batch.commit();
      }
      debugPrint('Migrated ${legacy.docs.length} legacy progress photo(s)');
    } catch (e) {
      debugPrint('Progress photo migration skipped: $e');
    }
  }

  /// Loads a log's progress photo: the new `progressPhotos` doc first, then
  /// the legacy `progressPhotoBase64` field older logs stored inline.
  Future<String?> getProgressPhoto({
    required String uid,
    required String logId,
  }) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('progressPhotos')
        .doc(logId)
        .get();
    final photo = doc.data()?['photoBase64'] as String?;
    if (photo != null && photo.isNotEmpty) return photo;

    final legacy = await _logs(uid).doc(logId).get();
    return legacy.data()?['progressPhotoBase64'] as String?;
  }

  /// Newest-first workout logs, sorted and limited by Firestore itself.
  ///
  /// A single-field orderBy needs no composite index (Firestore creates
  /// single-field indexes automatically), so there is no need to download
  /// the whole collection and sort it in Dart. Each map also gets
  /// 'logId' from the doc id if the field is missing.
  Future<List<Map<String, dynamic>>> _recentLogs(String uid, int limit) async {
    final snapshot = await _logs(uid)
        .orderBy('completedAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((d) => {...d.data(), 'logId': d.data()['logId'] ?? d.id})
        .toList();
  }

  /// Recomputes and writes per-muscle recovery data for [uid]
  Future<void> updateMuscleRecovery(String uid) async {
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));

    // Only the last 7 days are needed. completedAt is a local ISO-8601
    // string, so string comparison orders it correctly.
    final logsSnapshot = await _logs(uid)
        .where('completedAt',
            isGreaterThanOrEqualTo: sevenDaysAgo.toIso8601String())
        .get();

    // Fetch every log's exercise list in parallel instead of one by one.
    final exerciseSnaps = await Future.wait(logsSnapshot.docs
        .map((d) => d.reference.collection('exerciseLogs').get()));

    // Accumulated per broad muscle group across all logs in the window.
    final Map<String, double> weightedSets = {};
    final Map<String, double> rawVolume = {};
    final Map<String, DateTime> lastTrained = {};

    for (int i = 0; i < logsSnapshot.docs.length; i++) {
      final logDoc = logsSnapshot.docs[i];
      final logData = logDoc.data();
      final completedAtStr = logData['completedAt'] as String?;
      if (completedAtStr == null) continue;

      final completedAt = DateTime.tryParse(completedAtStr);
      if (completedAt == null || completedAt.isBefore(sevenDaysAgo)) {
        continue;
      }

      final exerciseLogsSnap = exerciseSnaps[i];

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
        final volume = completedSets.fold<double>(0.0, (total, s) {
          final reps = (s['reps'] as num?)?.toDouble() ?? 0;
          final weightKg = (s['weightKg'] as num?)?.toDouble() ?? 0;
          // Bodyweight sets contribute reps only, not reps × 0.
          return total + (weightKg > 0 ? reps * weightKg : reps);
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

  /// Weight history for several exercises in ONE pass: one query for the
  /// newest [scanLimit] logs, then every log's exercise list fetched in
  /// parallel. Replaces calling a per-exercise scan once per exercise,
  /// which re-read the whole log collection plus up to 30 sequential
  /// queries for EACH exercise (slow workout start and slow "Complete").
  Future<Map<String, ExerciseWeightHistory>> getWeightHistory({
    required String uid,
    required Iterable<String> exerciseNames,
    int scanLimit = 30,
  }) async {
    final wanted = exerciseNames.toSet();
    if (wanted.isEmpty) return {};

    final logs = await _recentLogs(uid, scanLimit); // newest first
    final exerciseSnaps = await Future.wait(logs.map((log) => _logs(uid)
        .doc(log['logId'] as String)
        .collection('exerciseLogs')
        .get()));

    final last = <String, double>{};
    final max = <String, double>{};
    final sessionMaxesNewestFirst = <String, List<double>>{};

    for (final snap in exerciseSnaps) {
      final seenThisSession = <String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = data['exerciseName'] as String?;
        if (name == null || !wanted.contains(name)) continue;
        if (!seenThisSession.add(name)) continue; // one entry per session

        final sets =
            (data['setDetails'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        double sessionMax = 0;
        double? lastInSession;
        for (final set in sets) {
          final w = (set['weightKg'] as num?)?.toDouble() ?? 0;
          if (w > sessionMax) sessionMax = w;
          if (w > 0) lastInSession = w; // last set with a weight
        }
        lastInSession ??= () {
          final top = (data['weightKg'] as num?)?.toDouble() ?? 0;
          return top > 0 ? top : null;
        }();

        if (lastInSession != null) last.putIfAbsent(name, () => lastInSession!);
        if (sessionMax > 0) {
          if (sessionMax > (max[name] ?? 0)) max[name] = sessionMax;
          sessionMaxesNewestFirst.putIfAbsent(name, () => []).add(sessionMax);
        }
      }
    }

    return {
      for (final name in wanted)
        name: ExerciseWeightHistory(
          lastWeight: last[name],
          maxWeight: max[name],
          sessionMaxesOldestFirst:
              (sessionMaxesNewestFirst[name] ?? []).reversed.toList(),
        ),
    };
  }

  /// Finds the most recent weight the user logged for a specific exercise
  Future<double?> getLastWeightForExercise({
    required String uid,
    required String exerciseName,
    int scanLimit = 15,
  }) async {
    final history = await getWeightHistory(
        uid: uid, exerciseNames: [exerciseName], scanLimit: scanLimit);
    return history[exerciseName]?.lastWeight;
  }

  /// Finds the heaviest weight ever logged for a specific exercise
  Future<double?> getMaxWeightForExercise({
    required String uid,
    required String exerciseName,
    int scanLimit = 30,
  }) async {
    final history = await getWeightHistory(
        uid: uid, exerciseNames: [exerciseName], scanLimit: scanLimit);
    return history[exerciseName]?.maxWeight;
  }

  /// Returns up to [limit] most-recent per-session max weights for
  /// [exerciseName], oldest-first — the chronological series plateau
  /// detection (AdaptService.detectPlateau) needs.
  ///
  /// [limit] defaults to 5, not 4: detectPlateau checks the last 4
  /// session-to-session transitions, which needs 5 sessions (Decision
  /// #59). With the previous default of 4 this never returned enough data,
  /// so the plateau notice could never appear in the app.
  Future<List<double>> getRecentSessionMaxWeights({
    required String uid,
    required String exerciseName,
    int limit = 5,
    int scanLimit = 30,
  }) async {
    final history = await getWeightHistory(
        uid: uid, exerciseNames: [exerciseName], scanLimit: scanLimit);
    final all = history[exerciseName]?.sessionMaxesOldestFirst ?? const [];
    return all.length <= limit ? all : all.sublist(all.length - limit);
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

  /// The actual last-completed date [muscleGroup] was trained — not a
  /// scheduled date, the date a session for it was really logged (which
  /// may differ from the plan if there was an earlier ad-hoc session).
  /// Backed by the same `muscleRecovery.lastTrained` field
  /// [updateMuscleRecovery] already maintains on every save, rather than
  /// duplicating that computation here.
  Future<DateTime?> getLastTrainedDate({
    required String uid,
    required String muscleGroup,
  }) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('muscleRecovery')
        .doc(muscleGroup)
        .get();

    final lastTrainedStr = doc.data()?['lastTrained'] as String?;
    if (lastTrainedStr == null) return null;
    return DateTime.tryParse(lastTrainedStr);
  }

  /// Finds a completed workout log whose completedAt falls on [date] — for
  /// callers that don't already hold a full logs list in memory (unlike
  /// HomeScreen, which keeps `_allLogs` and calls ScheduleMatcher directly)
  Future<Map<String, dynamic>?> getLogForDate({
    required String uid,
    required DateTime date,
  }) async {
    // Only that calendar day's logs: [00:00 that day, 00:00 next day).
    final dayStart = DateTime(date.year, date.month, date.day);
    final nextDay = DateTime(date.year, date.month, date.day + 1);
    final snapshot = await _logs(uid)
        .where('completedAt', isGreaterThanOrEqualTo: dayStart.toIso8601String())
        .where('completedAt', isLessThan: nextDay.toIso8601String())
        .get();
    final logs = snapshot.docs.map((d) => d.data()).toList();
    return ScheduleMatcher.logForDate(logs, date);
  }

  /// Fetches recent workout logs for the home screen activity feed.
  Future<List<Map<String, dynamic>>> getRecentLogs(String uid,
      {int limit = 10}) =>
      _recentLogs(uid, limit);

  /// Fetches the thin, follower-visible activity feed for [uid] — see the
  /// `activityFeed` write in [saveWorkoutLog] for what it contains and why
  /// it's separate from [getRecentLogs]'s full `workoutLogs` data.
  Future<List<Map<String, dynamic>>> getActivityFeed(String uid, {int limit = 20}) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('activityFeed')
        .orderBy('completedAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs.map((d) => {'logId': d.id, ...d.data()}).toList();
  }
}