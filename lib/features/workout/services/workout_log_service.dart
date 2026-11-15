import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../shared/utils/workout_stats_format.dart';
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

/// One finished session in the recovery window: when it was completed
/// and its exercise logs (see [WorkoutLogService.computeRecoveryDocs]).
typedef RecoverySession = ({
  DateTime completedAt,
  List<Map<String, dynamic>> exerciseLogs,
});

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

  CollectionReference<Map<String, dynamic>> _feed(String uid) =>
      _db.collection('users').doc(uid).collection('activityFeed');

  /// Longest caption a session can carry.
  static const int maxCaptionLength = 280;

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
      'totalDurationSecs': log['totalDurationSecs'],
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

    // Thin denormalized copy for followers — only the summary totals the
    // feed card shows (including total kg lifted), never the per-set
    // weights/reps in exerciseLogs. See firestore.rules for why this lives
    // in a separate subcollection instead of exposing workoutLogs itself
    // to non-owners.
    batch.set(_feed(uid).doc(logId), _feedSummary(log));

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

  /// The follower-visible summary of a full `workoutLogs` doc, for its
  /// `activityFeed` copy. Exact seconds fall back to startedAt→completedAt
  /// for logs saved before they were stored. Deliberately leaves out the
  /// photo-sharing flag and caption: those are only ever set by their own
  /// explicit actions ([saveProgressPhoto], [setProgressPhotoShared],
  /// [saveCaption]), so rebuilding a summary can never publish a photo.
  static Map<String, dynamic> _feedSummary(Map<String, dynamic> log) {
    final secs = logDurationSecs(log);
    return {
      'workoutName': log['workoutName'],
      'completedAt': log['completedAt'],
      'totalDurationMins': log['totalDurationMins'],
      'totalDurationSecs': ?secs,
      'totalVolume': (log['totalVolume'] as num?) ?? 0,
      'totalSetsCompleted': log['totalSetsCompleted'],
      'prReached': log['prReached'] ?? false,
    };
  }

  static String _feedBackfillKey(String uid) => 'activityFeedStatsV1_$uid';

  /// One-off repair of this user's own `activityFeed` copies saved before
  /// they carried `totalVolume` and `totalDurationSecs` — followers saw
  /// "—" for KG LIFTED and "0m" for any sub-minute session. Rebuilds the
  /// summary from the owner-only `workoutLogs` source. Only the owner can
  /// write their feed, so each account heals the next time its owner opens
  /// the app; a local flag stops it re-reading the feed after that. Older
  /// progress photos stay private (see [_feedSummary]).
  /// Fire-and-forget: never throws.
  Future<void> backfillActivityFeedStats(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_feedBackfillKey(uid)) ?? false) return;

      final feed = await _feed(uid).get();
      final stale = feed.docs.where((d) =>
          !d.data().containsKey('totalVolume') ||
          !d.data().containsKey('totalDurationSecs'));

      final updates = <DocumentReference<Map<String, dynamic>>,
          Map<String, dynamic>>{};
      await Future.wait(stale.map((doc) async {
        final source = await _logs(uid).doc(doc.id).get();
        final log = source.data();
        if (log == null) return; // source log deleted; nothing to copy
        updates[doc.reference] = _feedSummary(log);
      }));

      final entries = updates.entries.toList();
      const perBatch = 400; // under Firestore's 500-writes-per-batch limit
      for (int i = 0; i < entries.length; i += perBatch) {
        final batch = _db.batch();
        for (final e in entries.skip(i).take(perBatch)) {
          batch.set(e.key, e.value, SetOptions(merge: true));
        }
        await batch.commit();
      }
      await prefs.setBool(_feedBackfillKey(uid), true);
      if (entries.isNotEmpty) {
        debugPrint('Backfilled stats on ${entries.length} activityFeed doc(s)');
      }
    } catch (e) {
      debugPrint('activityFeed stats backfill skipped: $e');
    }
  }

  /// Saves a progress photo for a log. Photos live in their own
  /// `progressPhotos/{logId}` doc rather than on the workout log: they are
  /// ~100 KB of base64 each, and every history query that reads workout
  /// logs would otherwise download every photo too.
  ///
  /// [shareWithFollowers] sets the feed copy's `hasProgressPhoto` flag,
  /// which firestore.rules checks before letting anyone but the owner read
  /// the photo. The full log keeps `hasProgressPhoto: true` either way (the
  /// owner always sees it) plus `photoShared` for the owner's toggle.
  Future<void> saveProgressPhoto({
    required String uid,
    required String logId,
    required String photoBase64,
    bool shareWithFollowers = false,
  }) async {
    final batch = _db.batch();
    batch.set(
      _db.collection('users').doc(uid).collection('progressPhotos').doc(logId),
      {'photoBase64': photoBase64, 'logId': logId},
    );
    // Small flag so lists know a photo exists without downloading it.
    batch.update(_logs(uid).doc(logId),
        {'hasProgressPhoto': true, 'photoShared': shareWithFollowers});
    // Merge: the feed copy was written with the log just before this.
    batch.set(_feed(uid).doc(logId), {'hasProgressPhoto': shareWithFollowers},
        SetOptions(merge: true));
    try {
      await batch.commit().timeout(_saveAckTimeout);
    } on TimeoutException {
      // Queued locally while offline; Firestore syncs it later.
    }
  }

  /// Shows or hides an existing progress photo from followers. Rewrites
  /// the feed copy's summary from the log too, so a log saved before the
  /// feed existed gets a complete card rather than a bare flag.
  Future<void> setProgressPhotoShared({
    required String uid,
    required String logId,
    required bool shared,
  }) async {
    final log = (await _logs(uid).doc(logId).get()).data();
    if (log == null) return;
    final batch = _db.batch();
    batch.update(_logs(uid).doc(logId), {'photoShared': shared});
    batch.set(_feed(uid).doc(logId),
        {..._feedSummary(log), 'hasProgressPhoto': shared},
        SetOptions(merge: true));
    try {
      await batch.commit().timeout(_saveAckTimeout);
    } on TimeoutException {
      // Queued locally while offline; Firestore syncs it later.
    }
  }

  /// Sets (or, when blank, removes) a session's caption on both the log
  /// and its follower-visible feed copy.
  Future<void> saveCaption({
    required String uid,
    required String logId,
    required String caption,
  }) async {
    var text = caption.trim();
    if (text.length > maxCaptionLength) {
      text = text.substring(0, maxCaptionLength);
    }
    final Object value = text.isEmpty ? FieldValue.delete() : text;
    final batch = _db.batch();
    batch.update(_logs(uid).doc(logId), {'caption': value});
    batch.set(_feed(uid).doc(logId), {'caption': value}, SetOptions(merge: true));
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
      // `isNull: false` is Firestore's "field != null". This used to be
      // `isNotEqualTo: null`, which cloud_firestore silently drops (it only
      // adds a condition for a non-null value), so the query matched EVERY
      // log and set `hasProgressPhoto: false` on each one on every Home
      // load — photos vanished from their owner's cards after a refresh.
      // See [repairProgressPhotoFlags] for undoing that.
      final legacy = await _logs(uid)
          .where('progressPhotoBase64', isNull: false)
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
            batch.update(doc.reference, {
              'progressPhotoBase64': FieldValue.delete(),
              'hasProgressPhoto': true,
            });
          } else {
            // Empty leftover field: just drop it. Never clears the flag —
            // the log may have a photo in progressPhotos already.
            batch.update(
                doc.reference, {'progressPhotoBase64': FieldValue.delete()});
          }
        }
        await batch.commit();
      }
      debugPrint('Migrated ${legacy.docs.length} legacy progress photo(s)');
    } catch (e) {
      debugPrint('Progress photo migration skipped: $e');
    }
  }

  static String _photoFlagRepairKey(String uid) =>
      'progressPhotoFlagRepairV1_$uid';

  /// One-off repair for logs whose `hasProgressPhoto` flag the broken
  /// [migrateLegacyProgressPhotos] query wiped: every photo still in
  /// `progressPhotos` gets its log's flag back. Touches only the owner's
  /// own log — whether followers can see a photo (the activityFeed flag)
  /// was never affected and isn't changed here. Reads the photo docs (and
  /// so downloads each photo) once per account on this phone, then a
  /// local flag skips it. Returns the ids it fixed so the caller can
  /// update logs it already holds. Fire-and-forget: never throws.
  Future<Set<String>> repairProgressPhotoFlags(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_photoFlagRepairKey(uid)) ?? false) return {};

      final photos = await _db
          .collection('users')
          .doc(uid)
          .collection('progressPhotos')
          .get();
      final photoLogIds = photos.docs
          .where((d) => (d.data()['photoBase64'] as String?)?.isNotEmpty ?? false)
          .map((d) => d.id);
      final logs =
          await Future.wait(photoLogIds.map((id) => _logs(uid).doc(id).get()));
      final broken = logs
          .where((l) => l.exists && l.data()?['hasProgressPhoto'] != true)
          .toList();

      const perBatch = 400; // under Firestore's 500-writes-per-batch limit
      for (int i = 0; i < broken.length; i += perBatch) {
        final batch = _db.batch();
        for (final log in broken.skip(i).take(perBatch)) {
          batch.update(log.reference, {'hasProgressPhoto': true});
        }
        await batch.commit();
      }
      await prefs.setBool(_photoFlagRepairKey(uid), true);
      if (broken.isNotEmpty) {
        debugPrint('Restored hasProgressPhoto on ${broken.length} log(s)');
      }
      return broken.map((l) => l.id).toSet();
    } catch (e) {
      debugPrint('Progress photo flag repair skipped: $e');
      return {};
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

  /// Recomputes and writes per-muscle recovery data for [uid]. Also run
  /// before the weekly summary and when the Coach Recovery tab opens, so
  /// scores follow the 7-day window between saves (V-11).
  Future<void> updateMuscleRecovery(String uid) async {
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));

    // Only the last 7 days are needed. completedAt is a local ISO-8601
    // string, so string comparison orders it correctly.
    final logsSnapshot = await _logs(uid)
        .where('completedAt',
            isGreaterThanOrEqualTo: sevenDaysAgo.toIso8601String())
        .get();

    final muscleRecoveryRef =
        _db.collection('users').doc(uid).collection('muscleRecovery');

    // Fetch every log's exercise list in parallel instead of one by one,
    // alongside the groups already tracked (to reset ones that dropped out).
    final results = await Future.wait<Object>([
      muscleRecoveryRef.get(),
      ...logsSnapshot.docs.map((d) => d.reference.collection('exerciseLogs').get()),
    ]);
    final tracked = (results.first as QuerySnapshot<Map<String, dynamic>>)
        .docs
        .map((d) => d.id);

    final sessions = <RecoverySession>[];
    for (int i = 0; i < logsSnapshot.docs.length; i++) {
      final completedAt = DateTime.tryParse(
          logsSnapshot.docs[i].data()['completedAt'] as String? ?? '');
      if (completedAt == null) continue;
      final exerciseLogsSnap =
          results[i + 1] as QuerySnapshot<Map<String, dynamic>>;
      sessions.add((
        completedAt: completedAt,
        exerciseLogs: exerciseLogsSnap.docs.map((d) => d.data()).toList(),
      ));
    }

    final docs = computeRecoveryDocs(
      sessions: sessions,
      since: sevenDaysAgo,
      trackedGroups: tracked,
      now: now,
    );
    if (docs.isEmpty) return; // nothing trained, nothing to reset

    final batch = _db.batch();
    docs.forEach((group, fields) {
      batch.set(muscleRecoveryRef.doc(group), fields, SetOptions(merge: true));
    });

    try {
      await batch.commit().timeout(_saveAckTimeout);
    } on TimeoutException {
      // Already applied to the local cache; Firestore will sync it.
    }
  }

  /// Pure core of [updateMuscleRecovery]: the muscleRecovery fields to
  /// merge per broad muscle group, from the [sessions] completed since
  /// [since]. A group in [trackedGroups] (its doc already exists) with no
  /// sets left in the window is reset to zero, keeping its lastTrained, so
  /// it doesn't stay "fatigued" until it turns "unknown".
  static Map<String, Map<String, dynamic>> computeRecoveryDocs({
    required List<RecoverySession> sessions,
    required DateTime since,
    required Iterable<String> trackedGroups,
    required DateTime now,
  }) {
    // Accumulated per broad muscle group across all logs in the window.
    final Map<String, double> weightedSets = {};
    final Map<String, double> rawVolume = {};
    final Map<String, DateTime> lastTrained = {};

    for (final session in sessions) {
      final completedAt = session.completedAt;
      if (completedAt.isBefore(since)) continue;

      for (final exLog in session.exerciseLogs) {
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
        // The primary group is dropped: it already has full credit, so a
        // same-group secondary (e.g. Brachialis on a curl) must not add
        // 0.5 more. Also compared with the library's own group, which uses
        // the same constants as kGranularToBroadMuscleGroup, because logs
        // saved before 4 Aug 2026 hold the backend's lowercase 'arms'.
        final secondaryGroups = (exerciseMeta?.secondaryMuscles ?? [])
            .map((m) => kGranularToBroadMuscleGroup[m])
            .whereType<String>()
            .where((g) => g != primaryGroup && g != exerciseMeta?.muscleGroup)
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

    final updatedAt = now.toIso8601String();
    final docs = <String, Map<String, dynamic>>{};

    for (final group in weightedSets.keys) {
      final mrv = kWeeklyMRVByMuscleGroup[group] ?? kFallbackWeeklyMRV;
      final fatigueScore = (weightedSets[group]! / mrv).clamp(0.0, 1.0);
      final recommendedRestDays = fatigueScore < kRestDayFatigueThreshold
          ? kDefaultRestDays
          : kElevatedRestDays;

      docs[group] = {
        'muscleGroup': group,
        'lastTrained': lastTrained[group]?.toIso8601String(),
        'fatigueScore': fatigueScore,
        'volumeLast7Days': rawVolume[group],
        'weightedSetsLast7Days': weightedSets[group],
        'weeklyMrv': mrv,
        'recommendedRestDays': recommendedRestDays,
        'updatedAt': updatedAt,
      };
    }

    // No sets left in the window: fully recovered. lastTrained is left
    // as it is (merge), so "days since trained" stays correct.
    for (final group in trackedGroups) {
      if (docs.containsKey(group)) continue;
      docs[group] = {
        'fatigueScore': 0.0,
        'volumeLast7Days': 0.0,
        'weightedSetsLast7Days': 0.0,
        'recommendedRestDays': kDefaultRestDays,
        'updatedAt': updatedAt,
      };
    }

    return docs;
  }

  static void _updateLastTrained(
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