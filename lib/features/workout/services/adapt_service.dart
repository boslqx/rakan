import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../../core/utils/backend_headers.dart';
import '../data/exercise_data.dart';
import 'schedule_matcher.dart';
import 'workout_log_service.dart';
import 'workout_plan_service.dart';

class LoggedExerciseInfo {
  final String exerciseName;

  LoggedExerciseInfo({required this.exerciseName});
}

/// A scheduled session on [date] that passed with no completed log and
/// hasn't been resolved yet (Phase 25 missed-day popup — see
/// [AdaptService.findMissedDays]). The whole day, whatever it trained: it's
/// moved or skipped as one session.
class MissedDay {
  final DateTime date;
  final String workoutName;

  /// Every muscle group the session trains — a skip records a break for each.
  final List<String> muscleGroups;

  MissedDay({
    required this.date,
    required this.workoutName,
    required this.muscleGroups,
  });

  /// Stable identity for this missed session — its date, which also keys
  /// its Firestore resolution doc. Use this (not a list index) for any UI
  /// or map/set keying: list positions shift when items resolve out of
  /// order, but this doesn't.
  String get key => ScheduleMatcher.dateKey(date);
}

class AdaptService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _baseUrl = 'https://rakan-backend.onrender.com';

  // Backward/forward scan window for missed-day detection and reschedule
  // search — same span HomeScreen's _calendarLogScanLimit uses, so every
  // part of the app agrees on how much history/future counts.
  static const int _scheduleScanLimitDays = 30;

  // A missed day stops being reschedulable this many days after it was
  // missed — past this, it's automatically resolved as skipped (see
  // partitionMissedDaysByExpiry). Independent of which days it can move to
  // (computeRescheduleDays) — this gates whether moving is offered at all.
  static const int _rescheduleExpiryDays = 7;

  // How far ahead a missed session can be moved — see computeRescheduleDays.
  static const int _rescheduleWindowDays = 7;

  /// Builds one proposal payload per unique primary muscle group
  static List<Map<String, dynamic>> buildSessionProposals({
    required List<LoggedExerciseInfo> sessionExercises,
    required double fatigueScore,
    required String sourceLogId,
  }) {
    final payloads = <Map<String, dynamic>>[];
    final Set<String> seenMuscleGroups = {};

    for (final loggedExercise in sessionExercises) {
      final exerciseData = findExerciseByName(loggedExercise.exerciseName);
      if (exerciseData == null) continue; // unresolvable — nothing to key a proposal on

      final muscleGroup = exerciseData.muscleGroup;
      if (seenMuscleGroups.contains(muscleGroup)) continue; // already proposed this session

      seenMuscleGroups.add(muscleGroup);

      payloads.add({
        'createdAt': FieldValue.serverTimestamp(),
        'muscleGroup': muscleGroup,
        'sessionFatigueScore': fatigueScore,
        'status': 'pending',
        'sourceLogId': sourceLogId,
        'trigger': 'session',
      });
    }

    return payloads;
  }

  /// Builds a single skip-triggered proposal — written the moment the user
  /// picks "Skip entirely" in the missed-day popup, unconditionally (Phase
  /// 25 removed the old streak >= 2 gate: every explicit skip is recorded).
  /// No session occurred, so sessionFatigueScore stays null (Decision #45,
  /// unchanged) — the backend's return_from_break tier handles this case
  /// without a fatigue score.
  ///
  /// [priorLastTrainedDate] is this muscle group's actual last-completed
  /// date *before* the break, captured now while it's still accurate —
  /// once the user trains this muscle group again, the same lookup would
  /// return that new session instead of the one the layoff should be
  /// measured against. `daysSinceLastTrained` itself can't be computed yet
  /// (it isn't known until that next session actually happens — see
  /// [predictAndAdapt]), so it starts out null.
  static Map<String, dynamic> buildReturnFromBreakProposal({
    required String muscleGroup,
    required String sourceLogId,
    required DateTime? priorLastTrainedDate,
  }) {
    return {
      'createdAt': FieldValue.serverTimestamp(),
      'muscleGroup': muscleGroup,
      'sessionFatigueScore': null,
      'status': 'pending',
      'sourceLogId': sourceLogId,
      'trigger': 'skip',
      'priorLastTrainedDate': priorLastTrainedDate != null
          ? ScheduleMatcher.dateKey(priorLastTrainedDate)
          : null,
      'daysSinceLastTrained': null,
    };
  }

  /// Scans backward from yesterday for scheduled sessions that passed with
  /// no completed log and have no resolution recorded yet (neither moved
  /// nor skipped — see [resolveMissedDayAsRescheduled] /
  /// [resolveMissedDayAsSkipped]). One [MissedDay] per date: the whole
  /// session, whatever it trained. This is purely detection for the popup
  /// — it does not create proposals or gate on a streak length; Phase 25
  /// replaced streak-counting with the user's explicit choice.
  ///
  /// [planStartDate] bounds how far back the scan can go: a plan's
  /// `days` are a recurring weekday template with no calendar anchor of
  /// their own (Monday's slot matches every Monday, forever), so without
  /// this bound the scan can't tell "this weekday was scheduled and
  /// skipped" apart from "this weekday recurs, but the plan didn't exist
  /// yet" — a brand-new plan generated on a Wednesday would otherwise see
  /// last Monday's slot and flag it missed, even though the user had no
  /// plan (and nothing to miss) that Monday. Pass null only when the
  /// plan's generation date genuinely isn't known (e.g. an old plan
  /// written before that field existed) — never to intentionally widen
  /// the scan.
  ///
  /// [checkedThrough] is the last date an earlier scan settled — everything
  /// up to it was logged, resolved, or not a workout when it was checked —
  /// so the scan stops there. Without it a later plan change (a rest day
  /// swapped into a workout, say) would turn an old date into a newly
  /// "missed" one.
  ///
  /// Each date is read through [ScheduleMatcher.resolvedDayForDate], so a
  /// workout swapped away for that week isn't flagged on its old day, and
  /// one swapped or moved onto a date is flagged there if skipped.
  /// [resolvedKeys] are resolution doc IDs: a date key, or a legacy
  /// per-muscle-group 'Chest|date' — either settles that date.
  static List<MissedDay> computeMissedDays({
    required List<Map<String, dynamic>> planDays,
    required List<Map<String, dynamic>> logs,
    required Set<String> resolvedKeys,
    required DateTime today,
    required DateTime? planStartDate,
    List<Map<String, dynamic>> overrides = const [],
    DateTime? checkedThrough,
    int scanLimitDays = _scheduleScanLimitDays,
  }) {
    final missed = <MissedDay>[];
    final startDateOnly = planStartDate != null ? _dateOnly(planStartDate) : null;
    final checkedOnly = checkedThrough != null ? _dateOnly(checkedThrough) : null;
    final resolvedDates = {for (final key in resolvedKeys) key.split('|').last};

    for (int offset = 1; offset <= scanLimitDays; offset++) {
      final date = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: offset));

      // Scanning strictly backward in time — once a date is before the
      // plan's start, or already settled, every earlier offset will be too.
      if (startDateOnly != null && date.isBefore(startDateOnly)) break;
      if (checkedOnly != null && !date.isAfter(checkedOnly)) break;

      final day = ScheduleMatcher.resolvedDayForDate(planDays, overrides, date);
      if (day == null || day['dayType'] == 'rest') continue;

      final muscleGroups = _muscleGroupsForPlanDay(day);
      if (muscleGroups.isEmpty) continue;

      if (ScheduleMatcher.logForDate(logs, date) != null) continue; // completed, not missed
      if (resolvedDates.contains(ScheduleMatcher.dateKey(date))) continue;

      missed.add(MissedDay(
        date: date,
        workoutName: day['workoutName'] as String? ?? 'Workout',
        muscleGroups: muscleGroups.toList(),
      ));
    }

    return missed;
  }

  /// Every rest day a missed session can be moved to: from today, up to
  /// [windowDays] ahead, and before that same workout (the same plan day)
  /// comes round again — so it's never doubled up with its own next
  /// session. A day counts as rest when nothing is scheduled on it (a rest
  /// day, or a workout swapped away that week) and nothing was logged on
  /// it. Possibly empty, leaving only a skip.
  static List<DateTime> computeRescheduleDays({
    required List<Map<String, dynamic>> planDays,
    required List<Map<String, dynamic>> overrides,
    required List<Map<String, dynamic>> logs,
    required DateTime missedDate,
    required DateTime today,
    int windowDays = _rescheduleWindowDays,
  }) {
    final missedOnly = _dateOnly(missedDate);
    final todayOnly = _dateOnly(today);
    final missedSession = ScheduleMatcher.resolvedDayForDate(planDays, overrides, missedOnly);
    final workoutId = missedSession == null ? null : _planDayIdOf(missedSession);

    final days = <DateTime>[];
    for (int offset = 0; offset <= windowDays; offset++) {
      final date = todayOnly.add(Duration(days: offset));
      if (!date.isAfter(missedOnly)) continue;

      final day = ScheduleMatcher.resolvedDayForDate(planDays, overrides, date);
      if (day != null && day['dayType'] != 'rest') {
        if (workoutId != null && _planDayIdOf(day) == workoutId) break; // its next session
        continue;
      }
      if (ScheduleMatcher.logForDate(logs, date) != null) continue;
      days.add(date);
    }

    return days;
  }

  /// The plan day a scheduled day's workout belongs to: a plan day's own
  /// 'id', or the one a one-time version was made from.
  static String? _planDayIdOf(Map<String, dynamic> day) =>
      (day['id'] ?? day['planDayId']) as String?;

  /// Splits already-detected, still-unresolved [missedDays] into those
  /// still within the [_rescheduleExpiryDays]-day reschedule-eligible
  /// window ([actionable] — show as a card with Reschedule/Skip choices)
  /// and those whose eligibility has expired ([expired] — auto-resolve as
  /// skipped and show read-only). A missed day exactly at the expiry
  /// boundary is still actionable; only strictly past it expires.
  static ({List<MissedDay> actionable, List<MissedDay> expired})
      partitionMissedDaysByExpiry({
    required List<MissedDay> missedDays,
    required DateTime today,
    int expiryDays = _rescheduleExpiryDays,
  }) {
    final actionable = <MissedDay>[];
    final expired = <MissedDay>[];
    final todayOnly = _dateOnly(today);

    for (final missed in missedDays) {
      final daysSinceMissed = todayOnly.difference(_dateOnly(missed.date)).inDays;
      if (daysSinceMissed > expiryDays) {
        expired.add(missed);
      } else {
        actionable.add(missed);
      }
    }

    return (actionable: actionable, expired: expired);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _missedDayKey(String muscleGroup, DateTime date) =>
      '$muscleGroup|${ScheduleMatcher.dateKey(date)}';

  /// Distinct muscle groups a plan day (or one-time override) trains.
  /// Plan-stored exercises carry `muscleGroup` directly (every write path
  /// — template generation and manual add — sets it), with a fallback to
  /// the static exercise table for older plans written before that field
  /// existed, mirroring the same fallback WorkoutLogService.updateMuscleRecovery uses.
  static Set<String> _muscleGroupsForPlanDay(Map<String, dynamic> planDay) {
    final exercises =
        (planDay['exercises'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final groups = <String>{};

    for (final exercise in exercises) {
      final muscleGroup = _exerciseMuscleGroup(exercise);
      if (muscleGroup != null) groups.add(muscleGroup);
    }

    return groups;
  }

  /// Resolves a single plan-stored exercise's muscle group — direct field
  /// first, falling back to the static exercise table for older plans
  /// written before that field existed (Decision #46).
  static String? _exerciseMuscleGroup(Map<String, dynamic> exercise) {
    final name = exercise['exerciseName'] as String?;
    return exercise['muscleGroup'] as String? ??
        (name != null ? findExerciseByName(name)?.muscleGroup : null);
  }

  /// Fetches this user's active plan, recent logs, and already-resolved
  /// missed days, runs [computeMissedDays] over them, then sweeps the
  /// result through [partitionMissedDaysByExpiry]: anything past the
  /// [_rescheduleExpiryDays]-day window is auto-resolved as skipped right
  /// here (same [resolveMissedDayAsSkipped] path an explicit "Skip" tap
  /// uses) before this returns, so the caller never has to separately
  /// remember to do it. [actionable] is what the popup should show as live
  /// cards; [autoSkipped] is what it should show read-only.
  Future<({List<MissedDay> actionable, List<MissedDay> autoSkipped})>
      findMissedDays(String uid) async {
    final plan = await WorkoutPlanService().getActivePlan(uid);
    if (plan == null) return (actionable: <MissedDay>[], autoSkipped: <MissedDay>[]);

    final planDays = (plan['days'] as List).cast<Map<String, dynamic>>();
    if (planDays.isEmpty) {
      return (actionable: <MissedDay>[], autoSkipped: <MissedDay>[]);
    }

    final logs = await WorkoutLogService()
        .getRecentLogs(uid, limit: _scheduleScanLimitDays);
    final resolutions = await _getResolutions(uid);
    final overrides = await WorkoutPlanService().getScheduleOverrides(uid);

    // Bounds the backward scan to when this plan actually came into
    // existence — see computeMissedDays' planStartDate doc. Old plans
    // written before generatedAt existed fall back to null (unbounded),
    // same as before this fix.
    final generatedAtStr = plan['generatedAt'] as String?;
    final planStartDate =
        // toLocal(): new plans store a UTC timestamp with an offset; without
        // this the date part would be the UTC date, which is the previous
        // day for plans generated before 8am Malaysia time.
        generatedAtStr != null ? DateTime.tryParse(generatedAtStr)?.toLocal() : null;

    final today = DateTime.now();
    final allMissed = computeMissedDays(
      planDays: planDays,
      logs: logs,
      resolvedKeys: resolutions.keys,
      today: today,
      planStartDate: planStartDate,
      overrides: overrides,
      checkedThrough: resolutions.checkedThrough,
    );

    final partition = partitionMissedDaysByExpiry(
      missedDays: allMissed,
      today: today,
    );

    for (final expired in partition.expired) {
      await resolveMissedDayAsSkipped(uid: uid, missed: expired);
    }

    // Everything before the oldest session still awaiting a choice is now
    // settled — logged, resolved, or not a workout.
    final oldestOpen = partition.actionable.isEmpty
        ? _dateOnly(today)
        : partition.actionable.map((m) => m.date).reduce((a, b) => a.isBefore(b) ? a : b);
    await _missedDayResolutions(uid).doc(_scanDocId).set({
      'checkedThrough': ScheduleMatcher.dateKey(oldestOpen.subtract(const Duration(days: 1))),
    });

    return (actionable: partition.actionable, autoSkipped: partition.expired);
  }

  /// Fetches this user's active plan, overrides and recent logs, and runs
  /// [computeRescheduleDays] over them for [missed].
  Future<List<DateTime>> findRescheduleDays({
    required String uid,
    required MissedDay missed,
  }) async {
    final plan = await WorkoutPlanService().getActivePlan(uid);
    if (plan == null) return const [];

    final planDays = (plan['days'] as List).cast<Map<String, dynamic>>();
    final overrides = await WorkoutPlanService().getScheduleOverrides(uid);
    final logs = await WorkoutLogService().getRecentLogs(uid, limit: 7);

    return computeRescheduleDays(
      planDays: planDays,
      overrides: overrides,
      logs: logs,
      missedDate: missed.date,
      today: DateTime.now(),
    );
  }

  CollectionReference<Map<String, dynamic>> _missedDayResolutions(String uid) =>
      _db.collection('users').doc(uid).collection('missedDayResolutions');

  /// Where [findMissedDays] keeps the last date it settled (see
  /// computeMissedDays' checkedThrough) — alongside the resolutions, under
  /// an ID no date key can collide with.
  static const _scanDocId = '_scan';

  Future<({Set<String> keys, DateTime? checkedThrough})> _getResolutions(String uid) async {
    final snapshot = await _missedDayResolutions(uid).get();
    DateTime? checkedThrough;
    for (final doc in snapshot.docs) {
      if (doc.id == _scanDocId) {
        checkedThrough = DateTime.tryParse(doc.data()['checkedThrough'] as String? ?? '');
      }
    }
    return (keys: snapshot.docs.map((d) => d.id).toSet(), checkedThrough: checkedThrough);
  }

  /// How each resolved missed date ended — 'skipped' or 'rescheduled' —
  /// by date key, older per-muscle-group records included.
  Future<Map<String, String>> getMissedDayStatuses(String uid) async {
    final snapshot = await _missedDayResolutions(uid).get();
    return {
      for (final doc in snapshot.docs)
        if (doc.id != _scanDocId)
          doc.id.split('|').last: doc.data()['status'] as String? ?? 'skipped',
    };
  }

  /// "Move to [rescheduledTo]": puts [missed]'s whole session on that rest
  /// day as a one-time change — the plan stays as it is — and records the
  /// missed date as moved (never a skip — nothing is written to
  /// adaptationProposals). The moved session carries its source date, so
  /// the original day reads as moved and the new one as a moved-in session.
  Future<void> resolveMissedDayAsRescheduled({
    required String uid,
    required MissedDay missed,
    required DateTime rescheduledTo,
  }) async {
    try {
      final plan = await WorkoutPlanService().getActivePlan(uid);
      final planDays = (plan?['days'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final overrides = await WorkoutPlanService().getScheduleOverrides(uid);
      // Same lookup detection used, so what moves is what was missed.
      final session = ScheduleMatcher.resolvedDayForDate(planDays, overrides, missed.date);
      if (session == null) throw StateError('Nothing was scheduled on ${missed.key}');

      await WorkoutPlanService().setDaysForDates(uid: uid, contentByDate: {
        rescheduledTo: {
          ...session,
          'planDayId': ?_planDayIdOf(session),
          'sourceMissedDate': null,
          'sourceMissedDates': [missed.key],
        },
      });

      await _missedDayResolutions(uid).doc(missed.key).set({
        'missedDate': missed.key,
        'workoutName': missed.workoutName,
        'muscleGroups': missed.muscleGroups,
        'status': 'rescheduled',
        'rescheduledToDate': ScheduleMatcher.dateKey(rescheduledTo),
        'resolvedAt': FieldValue.serverTimestamp(),
      });
      WorkoutPlanService.scheduleChanges.value++;
    } catch (e, st) {
      // Surfaced rather than left silent: a caller awaiting this (the
      // missed-day popup) needs the rejection to know the card shouldn't
      // be treated as resolved.
      debugPrint('AdaptService.resolveMissedDayAsRescheduled failed for '
          'uid=$uid missedDate=${missed.key}: $e');
      debugPrint('$st');
      rethrow;
    }
  }

  /// "Skip": the only path that counts toward detection. Records the
  /// resolution (so the popup never re-asks about this session) and writes
  /// an unconditional adaptationProposals entry for each muscle group it
  /// trained — every explicit skip is recorded, with no streak gate
  /// (Decision replaced; see Part C).
  /// Also the automatic path an app-open sweep uses once a missed day's
  /// 7-day reschedule window has expired (see [findMissedDays] /
  /// [partitionMissedDaysByExpiry]) — same method, same proposal shape,
  /// whether the skip was tapped explicitly or resolved automatically.
  Future<void> resolveMissedDayAsSkipped({
    required String uid,
    required MissedDay missed,
  }) async {
    try {
      await _missedDayResolutions(uid).doc(missed.key).set({
        'missedDate': missed.key,
        'workoutName': missed.workoutName,
        'muscleGroups': missed.muscleGroups,
        'status': 'skipped',
        'rescheduledToDate': null,
        'resolvedAt': FieldValue.serverTimestamp(),
      });

      for (final muscleGroup in missed.muscleGroups) {
        // Idempotency: don't stack a second pending skip proposal for a
        // muscle group that already has one awaiting resolution.
        if (await _hasPendingSkipProposal(uid, muscleGroup)) continue;

        final priorLastTrainedDate = await WorkoutLogService()
            .getLastTrainedDate(uid: uid, muscleGroup: muscleGroup);

        final proposal = buildReturnFromBreakProposal(
          muscleGroup: muscleGroup,
          sourceLogId: _missedDayKey(muscleGroup, missed.date),
          priorLastTrainedDate: priorLastTrainedDate,
        );

        await _db
            .collection('users')
            .doc(uid)
            .collection('adaptationProposals')
            .add(proposal);
      }
      WorkoutPlanService.scheduleChanges.value++;
    } catch (e, st) {
      debugPrint('AdaptService.resolveMissedDayAsSkipped failed for '
          'uid=$uid missedDate=${missed.key}: $e');
      debugPrint('$st');
      rethrow;
    }
  }

  Future<bool> _hasPendingSkipProposal(String uid, String muscleGroup) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('adaptationProposals')
        .where('muscleGroup', isEqualTo: muscleGroup)
        .where('trigger', isEqualTo: 'skip')
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    return snapshot.docs.isNotEmpty;
  }

  /// A pending skip proposal for [muscleGroup] that hasn't had its
  /// daysSinceLastTrained resolved yet — i.e. the user hasn't actually
  /// returned to train this muscle group since the skip was recorded.
  /// Returns null once it's already been resolved once, so a later
  /// session for the same group (post-return) is treated as an ordinary
  /// session rather than re-triggering this tier.
  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findUnresolvedSkipProposal(
    String uid,
    String muscleGroup,
  ) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('adaptationProposals')
        .where('muscleGroup', isEqualTo: muscleGroup)
        .where('trigger', isEqualTo: 'skip')
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return (doc.data()['daysSinceLastTrained'] == null) ? doc : null;
  }

  /// Pure decision step, called from [predictAndAdapt] for each muscle
  /// group trained in today's session. [pendingSkipProposalData] is the
  /// data of that group's unresolved skip proposal, if any (from
  /// [_findUnresolvedSkipProposal]).
  ///
  /// When one exists, this session is the "return" the return_from_break
  /// tier was waiting on: computes the elapsed daysSinceLastTrained (date
  /// of this session minus the muscle group's actual last-trained date
  /// before the break) and signals that the ordinary session proposal for
  /// this group should be suppressed — Decision #44: only the skip
  /// proposal survives when both would otherwise apply the same day.
  static ({bool suppressSessionProposal, int? daysSinceLastTrained})
      resolvePendingSkipForSession({
    required Map<String, dynamic>? pendingSkipProposalData,
    required DateTime sessionDate,
  }) {
    if (pendingSkipProposalData == null) {
      return (suppressSessionProposal: false, daysSinceLastTrained: null);
    }

    final priorDateStr =
        pendingSkipProposalData['priorLastTrainedDate'] as String?;
    final daysSinceLastTrained = priorDateStr != null
        ? _dateOnly(sessionDate).difference(DateTime.parse(priorDateStr)).inDays
        : null;

    return (suppressSessionProposal: true, daysSinceLastTrained: daysSinceLastTrained);
  }

  /// Pure decision step for exercise-level plateau detection — no
  /// Firestore access, mirroring [computeMissedDays]'s split from its
  /// Firestore-fetching caller. Callers get the raw series from
  /// `WorkoutLogService.getRecentSessionMaxWeights` (oldest-first) and pass
  /// it straight in.
  ///
  /// A plateau is flagged when NONE of the last [n] session-to-session
  /// transitions shows a max-weight increase of at least [thresholdPct]
  /// versus the immediately prior session.
  ///
  /// [n] transitions require n+1 raw session values (n=4 needs 5 sessions:
  /// session 1->2, 2->3, 3->4, 4->5). Until the user has logged that many
  /// sessions for this exercise, this returns false ("insufficient
  /// history", not "plateaued") rather than guessing from a partial
  /// window — detection can only first fire on a user's 5th logged
  /// session of a given exercise.
  ///
  /// Known limitation (deliberate FYP scope decision, not an oversight):
  /// a transition spanning a long calendar gap (e.g. a session after a
  /// multi-week break) is treated identically to a normal week-to-week
  /// transition. This mirrors how other reactive signals in this codebase
  /// accept a similar simplification rather than cross-referencing break
  /// history — see the return-from-break tier's own gap handling in
  /// adaptation_engine.py for the analogous tradeoff on the backend side.
  static bool detectPlateau({
    required List<double> sessionMaxWeights, // oldest -> newest
    int n = 4,
    double thresholdPct = 0.02,
  }) {
    if (sessionMaxWeights.length < n + 1) return false;

    final window = sessionMaxWeights.sublist(sessionMaxWeights.length - (n + 1));

    for (int i = 1; i < window.length; i++) {
      final prior = window[i - 1];
      if (prior <= 0) continue; // no meaningful % change to compute from zero/negative
      final pctChange = (window[i] - prior) / prior;
      if (pctChange >= thresholdPct) return false; // one qualifying increase clears the plateau
    }

    return true;
  }

  // V-12 / P1-7: a session whose /adapt-plan call fails (offline, server
  // error, cold-start timeout) is kept on the device and retried on the
  // next Home open, so it still feeds the weekly adaptation.
  static String _pendingKey(String uid) => 'pending_adapt_predictions_$uid';

  /// Queued sessions older than this are dropped: the weekly runs have
  /// moved on and the reading no longer describes the current week.
  static const Duration kPendingPredictionMaxAge = Duration(days: 14);

  /// Sessions waiting for a retry, oldest first.
  static Future<List<Map<String, dynamic>>> pendingPredictions(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingKey(uid));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _savePending(
      String uid, List<Map<String, dynamic>> entries) async {
    final prefs = await SharedPreferences.getInstance();
    if (entries.isEmpty) {
      await prefs.remove(_pendingKey(uid));
    } else {
      await prefs.setString(_pendingKey(uid), jsonEncode(entries));
    }
  }

  /// Queues [entry] unless the same workout (sourceLogId) already is.
  static Future<void> queuePrediction(
      String uid, Map<String, dynamic> entry) async {
    final entries = await pendingPredictions(uid);
    if (entries.any((e) => e['sourceLogId'] == entry['sourceLogId'])) return;
    await _savePending(uid, [...entries, entry]);
  }

  /// Entries still worth retrying at [now] (see [kPendingPredictionMaxAge]).
  static List<Map<String, dynamic>> unexpiredPredictions(
    List<Map<String, dynamic>> entries,
    DateTime now,
  ) =>
      entries.where((e) {
        final at = DateTime.tryParse(e['sessionAt'] as String? ?? '');
        return at != null && now.difference(at) <= kPendingPredictionMaxAge;
      }).toList();

  /// Retries every queued session; ones that fail again stay queued.
  /// Never throws — called fire-and-forget from Home.
  Future<void> retryPendingPredictions(String uid) async {
    try {
      final entries = await pendingPredictions(uid);
      if (entries.isEmpty) return;
      final failed = <Map<String, dynamic>>[];
      for (final entry in unexpiredPredictions(entries, DateTime.now())) {
        try {
          await _predict(uid, entry);
        } catch (e) {
          debugPrint('AdaptService: retry failed for ${entry['sourceLogId']}: $e');
          failed.add(entry);
        }
      }
      // Keep anything queued while this ran, too.
      final processed = entries.map((e) => e['sourceLogId']).toSet();
      final latest = await pendingPredictions(uid);
      await _savePending(uid, [
        ...failed,
        ...latest.where((e) => !processed.contains(e['sourceLogId'])),
      ]);
    } catch (e) {
      debugPrint('AdaptService: retryPendingPredictions failed: $e');
    }
  }

  /// Predicts fatigue and writes one adaptation proposal per unique primary
  /// muscle group. If that fails, the session is queued for
  /// [retryPendingPredictions] and '' is returned.
  Future<String> predictAndAdapt({
    required String uid,
    required double avgRpe,
    required double maxRpe,
    required double sessionDuration,
    required int exercisesCount,
    required double completionRate,
    required int experienceLevel,
    required String sourceLogId,
    required List<LoggedExerciseInfo> sessionExercises,
  }) async {
    final entry = <String, dynamic>{
      'avgRpe': avgRpe,
      'maxRpe': maxRpe,
      'sessionDuration': sessionDuration,
      'exercisesCount': exercisesCount,
      'completionRate': completionRate,
      'experienceLevel': experienceLevel,
      'sourceLogId': sourceLogId,
      'exerciseNames': [for (final e in sessionExercises) e.exerciseName],
      'sessionAt': DateTime.now().toIso8601String(),
    };
    try {
      return await _predict(uid, entry);
    } catch (e) {
      debugPrint('AdaptService error (queued for retry): $e');
      try {
        await queuePrediction(uid, entry);
      } catch (_) {}
      return '';
    }
  }

  /// One /adapt-plan call plus the proposal writes for a session [entry]
  /// (the shape [predictAndAdapt] queues). Throws on any failure.
  Future<String> _predict(String uid, Map<String, dynamic> entry) async {
    final sourceLogId = entry['sourceLogId'] as String;
    final sessionAt = DateTime.parse(entry['sessionAt'] as String);
    final sessionExercises = [
      for (final name in (entry['exerciseNames'] as List).cast<String>())
        LoggedExerciseInfo(exerciseName: name),
    ];
    final response = await http.post(
      Uri.parse('$_baseUrl/adapt-plan'),
      headers: await backendHeaders(),
      body: jsonEncode({
        'avg_rpe': entry['avgRpe'],
        'max_rpe': entry['maxRpe'],
        'session_duration': entry['sessionDuration'],
        'exercises_count': entry['exercisesCount'],
        'completion_rate': entry['completionRate'],
        'experience_level': entry['experienceLevel'],
      }),
    ).timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      throw Exception('Adaptation prediction failed: ${response.statusCode}');
    }

    final result = jsonDecode(response.body) as Map<String, dynamic>;
    final double fatigueScore = (result['fatigue_score'] as num).toDouble();
    final String fatigueLevel = result['fatigue_level'] as String;
    // The backend message describes a raw adjustment.
    debugPrint(
      'AdaptService: fatigue=$fatigueLevel; '
      'backend message=${result['message']}',
    );

    final sessionProposals = buildSessionProposals(
      sessionExercises: sessionExercises,
      fatigueScore: fatigueScore,
      sourceLogId: sourceLogId,
    );

    final batch = _db.batch();
    final proposalsRef = _db
        .collection('users')
        .doc(uid)
        .collection('adaptationProposals');

    for (final sessionProposal in sessionProposals) {
      final muscleGroup = sessionProposal['muscleGroup'] as String;

      final pendingSkip = await _findUnresolvedSkipProposal(uid, muscleGroup);
      final decision = resolvePendingSkipForSession(
        pendingSkipProposalData: pendingSkip?.data(),
        // The workout's own time, also when it's a retried session.
        sessionDate: sessionAt,
      );

      if (decision.suppressSessionProposal) {
        batch.update(pendingSkip!.reference, {
          'daysSinceLastTrained': decision.daysSinceLastTrained,
        });
        continue;
      }

      batch.set(proposalsRef.doc(), sessionProposal);
    }

    await batch.commit();

    return fatigueLevel;
  }
}
