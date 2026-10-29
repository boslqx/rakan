import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../../core/utils/backend_headers.dart';
import '../data/exercise_data.dart';
import 'workout_log_service.dart';

class WeeklySummaryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _baseUrl = 'https://rakan-backend.onrender.com';
  static const Duration kSummaryInterval = Duration(days: 7);

  /// Checks whether at least 7 days have passed since the last weekly summary
  Future<void> checkAndGenerateWeeklySummary(String uid) async {
    try {
      final profileRef = _db
          .collection('users')
          .doc(uid)
          .collection('profile')
          .doc('data');

      final profileDoc = await profileRef.get();
      final lastCheckStr =
          profileDoc.data()?['lastWeeklySummaryAt'] as String?;
      final lastCheck =
          lastCheckStr != null ? DateTime.tryParse(lastCheckStr) : null;

      final now = DateTime.now();
      if (lastCheck != null && now.difference(lastCheck) < kSummaryInterval) {
        return; // not due yet
      }

      // Throws (so nothing below runs) when the run must be retried — see
      // mustRetryWeeklyRun.
      await _generateSummary(uid, now);

      // Advance the checkpoint once the run has been written
      await profileRef.update({
        'lastWeeklySummaryAt': now.toIso8601String(),
      });
    } catch (e) {
      debugPrint('checkAndGenerateWeeklySummary failed for $uid: $e');
    }
  }

  /// V-12: when there were proposals to resolve but /commit-adaptations
  /// failed, the whole run is retried on the next Home open: no summary is
  /// written and neither lastWeeklySummaryAt nor the plan's weekNumber
  /// advances, so the proposals stay pending and a scheduled deload week
  /// isn't skipped.
  static bool mustRetryWeeklyRun({
    required bool hadProposals,
    required bool commitSucceeded,
  }) =>
      hadProposals && !commitSucceeded;

  Future<void> _generateSummary(String uid, DateTime now) async {
    final weekStart = now.subtract(kSummaryInterval);

    // Recovery scores are otherwise only recomputed when a workout is
    // saved, so a muscle last trained days ago would still carry the
    // score from that save (V-11). Best-effort: a failure here leaves the
    // stored scores, as before.
    try {
      await WorkoutLogService().updateMuscleRecovery(uid);
    } catch (e) {
      debugPrint('Weekly summary: recovery refresh failed for $uid: $e');
    }

    // existing session/RPE aggregation — only this week's logs (V-13).
    // completedAt is a local ISO-8601 string, so string comparison orders
    // it correctly (same as updateMuscleRecovery).
    final logsSnapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('workoutLogs')
        .where('completedAt',
            isGreaterThanOrEqualTo: weekStart.toIso8601String())
        .get();

    int sessionsCompleted = 0;
    double totalVolume = 0;
    final List<int> rpeValues = [];

    for (final logDoc in logsSnapshot.docs) {
      final logData = logDoc.data();
      final completedAtStr = logData['completedAt'] as String?;
      if (completedAtStr == null) continue;

      final completedAt = DateTime.tryParse(completedAtStr);
      if (completedAt == null || completedAt.isBefore(weekStart)) continue;

      sessionsCompleted++;
      totalVolume += (logData['totalVolume'] as num?)?.toDouble() ?? 0;

      // Same subcollection-scan pattern as updateMuscleRecovery
      final exerciseLogsSnap =
          await logDoc.reference.collection('exerciseLogs').get();
      for (final exLogDoc in exerciseLogsSnap.docs) {
        final rpe = exLogDoc.data()['rpeScale'] as int? ?? 5;
        rpeValues.add(rpe);
      }
    }

    final avgRpe = rpeValues.isEmpty
        ? null
        : rpeValues.reduce((a, b) => a + b) / rpeValues.length;

    // Mesocycle tracking: read the active plan's current weekNumber 
    final planQuery = await _db
        .collection('users')
        .doc(uid)
        .collection('workoutPlans')
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();

    String? planId;
    int newWeekNumber = 2; // sensible fallback if no plan/weekNumber found yet
    bool isDeloadWeek = false;
    if (planQuery.docs.isNotEmpty) {
      planId = planQuery.docs.first.id;
      final currentWeekNumber =
          planQuery.docs.first.data()['weekNumber'] as int? ?? 1;
      newWeekNumber = currentWeekNumber + 1;
      // Fixed 4-week mesocycle: every 4th week (4, 8, 12, ...) is a deload.
      isDeloadWeek = newWeekNumber % 4 == 0;
    }

    // gather past volumes for trend (up to last 3 weeklySummaries) 
    final pastSummariesSnap = await _db
        .collection('users')
        .doc(uid)
        .collection('weeklySummaries')
        .orderBy('generatedAt', descending: true)
        .limit(3)
        .get();
    final pastVolumes = pastSummariesSnap.docs
        .map((d) => (d.data()['totalVolume'] as num?)?.toDouble() ?? 0.0)
        .toList();

    // gather pending proposals + their muscle recovery scores
    final proposalsSnap = await _db
        .collection('users')
        .doc(uid)
        .collection('adaptationProposals')
        .where('status', isEqualTo: 'pending')
        .get();

    final List<Map<String, dynamic>> proposalPayloads = [];
    final Map<String, DocumentReference> proposalRefsById = {};
    final Map<String, String> muscleGroupByProposalId = {};
    final Map<String, double> recoveryScoreByProposalId = {};

    for (final propDoc in proposalsSnap.docs) {
      final data = propDoc.data();
      final muscleGroup = data['muscleGroup'] as String;
      final trigger = data['trigger'] as String? ?? 'session';
      // Skip-triggered proposals carry no session, so this is null
      // (Decision #45) — resolve_adjustment's return_from_break tier
      // handles that case without a fatigue score.
      final fatigueScore = (data['sessionFatigueScore'] as num?)?.toDouble();

      final daysSinceLastTrained = data['daysSinceLastTrained'] as int?;
      if (trigger == 'skip' && daysSinceLastTrained == null) {
        // The user hasn't actually trained this muscle group again yet —
        // the return-from-break gap can't be computed until they do
        // (AdaptService.predictAndAdapt fills this in on that session).
        // Leave pending and retry next weekly run.
        continue;
      }

      // Read this muscle group's current recovery score
      final recoveryDoc = await _db
          .collection('users')
          .doc(uid)
          .collection('muscleRecovery')
          .doc(muscleGroup)
          .get();
      final recoveryScore =
          (recoveryDoc.data()?['fatigueScore'] as num?)?.toDouble();
      if (recoveryScore == null) {
        // No recovery data yet for this muscle group — skip rather than guess;
        // the proposal stays pending and will be retried next weekly run.
        continue;
      }

      proposalPayloads.add({
        'proposal_id': propDoc.id,
        'fatigue_score': fatigueScore,
        'muscle_recovery_score': recoveryScore,
        'trigger': trigger,
        'days_since_last_trained': ?daysSinceLastTrained,
      });
      proposalRefsById[propDoc.id] = propDoc.reference;
      muscleGroupByProposalId[propDoc.id] = muscleGroup;
      recoveryScoreByProposalId[propDoc.id] = recoveryScore;
    }

    // call the combined backend endpoint 
    Map<String, dynamic>? commitResult;
    if (proposalPayloads.isNotEmpty || pastVolumes.isNotEmpty) {
      final response = await http.post(
        Uri.parse('$_baseUrl/commit-adaptations'),
        headers: await backendHeaders(),
        body: jsonEncode({
          'current_volume': totalVolume,
          'past_volumes': pastVolumes,
          'proposals': proposalPayloads,
          'is_deload_week': isDeloadWeek,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        commitResult = jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        debugPrint('commit-adaptations failed: ${response.statusCode}');
      }
    }

    if (mustRetryWeeklyRun(
      hadProposals: proposalPayloads.isNotEmpty,
      commitSucceeded: commitResult != null,
    )) {
      throw StateError(
          'commit-adaptations failed with pending proposals; retrying next time');
    }

    // apply resolved adjustments + write summary, all in ONE batch
    final batch = _db.batch();
    final List<Map<String, dynamic>> weeklyChanges = [];

    // Advance the mesocycle week counter
    if (planId != null) {
      final planRef = _db
          .collection('users')
          .doc(uid)
          .collection('workoutPlans')
          .doc(planId);
      batch.update(planRef, {'weekNumber': newWeekNumber});
    }

    if (commitResult != null) {
      final resolvedProposals = commitResult['resolved_proposals'] as List<dynamic>;

      for (final resolved in resolvedProposals) {
        final proposalId = resolved['proposal_id'] as String;
        final finalAdjustment = (resolved['final_adjustment'] as num).toDouble();
        final tier = resolved['tier'] as String;
        final reason = resolved['reason'] as String;
        final muscleGroup = muscleGroupByProposalId[proposalId]!;
        final recoveryScore = recoveryScoreByProposalId[proposalId];

        // Apply to every future exercise whose primary muscleGroup matches
        await _applyAdjustmentToMuscleGroup(
          batch: batch,
          uid: uid,
          planId: planId,
          muscleGroup: muscleGroup,
          adjustment: finalAdjustment,
          tier: tier,
          reason: reason,
          recoveryScore: recoveryScore,
          todayWeekday: now.weekday,
          changesOut: weeklyChanges,
        );

        // Mark this proposal committed
        batch.update(proposalRefsById[proposalId]!, {
          'status': 'committed',
          'resolvedTier': tier,
          'resolvedAdjustment': finalAdjustment,
          'committedAt': FieldValue.serverTimestamp(),
        });
      }
    }

    // Existing summary write, now with trend fields added
    final summaryRef = _db
        .collection('users')
        .doc(uid)
        .collection('weeklySummaries')
        .doc();
    batch.set(summaryRef, {
      'weekStart': weekStart.toIso8601String(),
      'weekEnd': now.toIso8601String(),
      'sessionsCompleted': sessionsCompleted,
      'avgRpe': avgRpe,
      'totalVolume': totalVolume,
      'trend': commitResult?['trend'] ?? 'insufficient_data',
      'trendAdjustment': commitResult?['trend_adjustment'] ?? 0.0,
      'weekNumber': newWeekNumber,
      'isDeloadWeek': isDeloadWeek,
      'generatedAt': now.toIso8601String(),
      'changes': weeklyChanges,
      'changesAcknowledged': false,
    });

    await batch.commit();
  }

  /// Finds every exercise in every future workout day whose primary
  /// muscle group matches [muscleGroup], applies [adjustment], and records
  /// a summary entry only when at least one exercise actually changes.
  Future<void> _applyAdjustmentToMuscleGroup({
    required WriteBatch batch,
    required String uid,
    required String? planId,
    required String muscleGroup,
    required double adjustment,
    required String tier,
    required String reason,
    required double? recoveryScore,
    required int todayWeekday,
    required List<Map<String, dynamic>> changesOut,
  }) async {
    // planId is resolved once, up in _generateSummary, and threaded 
    if (planId == null) return;

    final daysSnap = await _db
        .collection('users')
        .doc(uid)
        .collection('workoutPlans')
        .doc(planId)
        .collection('days')
        .get();

    int exercisesAffected = 0;

    for (final dayDoc in daysSnap.docs) {
      final dayData = dayDoc.data();
      final int dayNumber = dayData['dayNumber'] as int? ?? 0;
      final bool isRestDay = dayData['dayType'] == 'rest';
      if (dayNumber <= todayWeekday || isRestDay) continue;

      final exercisesSnap = await dayDoc.reference.collection('exercises').get();

      for (final exDoc in exercisesSnap.docs) {
        final exData = exDoc.data();
        final exerciseName = exData['exerciseName'] as String?;
        if (exerciseName == null) continue;

        final exerciseInfo = findExerciseByName(exerciseName);
        if (exerciseInfo == null || exerciseInfo.muscleGroup != muscleGroup) continue;

        final currentSets = exData['sets'] as int? ?? 3;
        final currentReps = exData['reps'] as int? ?? 10;

        final newSets = _clampInt((currentSets * (1 + adjustment)).round(), min: 1, max: 6);
        final newReps = _clampInt((currentReps * (1 + adjustment)).round(), min: 3, max: 20);

        if (newSets != currentSets || newReps != currentReps) {
          batch.update(exDoc.reference, {
            'sets': newSets,
            'reps': newReps,
            'adaptedAt': FieldValue.serverTimestamp(),
            'fatigueLevel': tier,
            'adaptationSource': 'engine_v2',
          });
          exercisesAffected++;
        }
      }
    }

    // Capture the diff here, while both the pre- and post-adjustment values
    // are available in memory. Do not surface resolutions that changed nothing.
    if (exercisesAffected > 0) {
      changesOut.add({
        'muscleGroup': muscleGroup,
        'tier': tier,
        'reason': reason,
        'adjustment': adjustment,
        'exercisesAffected': exercisesAffected,
        'recoveryScore': ?recoveryScore,
      });
    }
  }

  int _clampInt(int value, {required int min, required int max}) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  /// Reads recent weekly summaries, most recent first.
  Future<List<Map<String, dynamic>>> getRecentSummaries(
    String uid, {
    int limit = 10,
  }) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('weeklySummaries')
        .get();

    final summaries = snapshot.docs.map((d) => d.data()).toList();
    summaries.sort((a, b) {
      final aDate = a['generatedAt'] as String? ?? '';
      final bDate = b['generatedAt'] as String? ?? '';
      return bDate.compareTo(aDate);
    });

    return summaries.take(limit).toList();
  }

  /// Returns the newest weekly summary the user has not yet seen — whether
  /// or not it contains any plan changes (`changesAcknowledged` gates
  /// showing the recap popup at all, not just the changes section within it).
  Future<Map<String, dynamic>?> getLatestUnacknowledgedChanges(
    String uid,
  ) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('weeklySummaries')
        .where('changesAcknowledged', isEqualTo: false)
        .orderBy('generatedAt', descending: true)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;

    final doc = snap.docs.first;
    return {'id': doc.id, ...doc.data()};
  }

  /// Marks a summary's changes as acknowledged after the user dismisses them.
  Future<void> acknowledgeChanges(String uid, String summaryId) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('weeklySummaries')
        .doc(summaryId)
        .update({'changesAcknowledged': true});
  }

  /// Returns the 30 most recent summaries that contain at least one change.
  Future<List<Map<String, dynamic>>> getChangeHistory(String uid) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('weeklySummaries')
        .orderBy('generatedAt', descending: true)
        .limit(30)
        .get();

    return snap.docs
        .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
        .where((data) => (data['changes'] as List<dynamic>? ?? []).isNotEmpty)
        .toList();
  }
}
