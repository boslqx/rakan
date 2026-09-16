import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../data/exercise_data.dart';
import 'schedule_matcher.dart';
import 'workout_log_service.dart';
import 'workout_plan_service.dart';

class LoggedExerciseInfo {
  final String exerciseName;

  LoggedExerciseInfo({required this.exerciseName});
}

/// A scheduled occurrence of [muscleGroup] on [date] that passed with no
/// completed log and hasn't been shown to the user yet (Phase 25 missed-day
/// popup — see [AdaptService.findMissedDays]).
class MissedDay {
  final String muscleGroup;
  final DateTime date;

  MissedDay({required this.muscleGroup, required this.date});

  /// Stable identity for this missed occurrence — muscle group + date, the
  /// same pairing that keys its Firestore resolution doc. Use this (not a
  /// list index) for any UI or map/set keying: list positions shift when
  /// items resolve out of order, but this doesn't.
  String get key => '$muscleGroup|${ScheduleMatcher.dateKey(date)}';
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
  // partitionMissedDaysByExpiry). Independent of the reschedule-day-finding
  // constraints in computeValidRescheduleDays — this gates whether that
  // search is even attempted, not a competing window within it.
  static const int _rescheduleExpiryDays = 7;

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

  /// Scans backward from yesterday for scheduled occurrences that passed
  /// with no completed log and have no resolution recorded yet (neither
  /// rescheduled nor skipped — see [resolveMissedDayAsRescheduled] /
  /// [resolveMissedDayAsSkipped]). This is purely detection for the
  /// popup — it does not create proposals or gate on a streak length;
  /// Phase 25 replaced streak-counting with the user's explicit choice.
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
  static List<MissedDay> computeMissedDays({
    required List<Map<String, dynamic>> planDays,
    required List<Map<String, dynamic>> logs,
    required Set<String> resolvedKeys,
    required DateTime today,
    required DateTime? planStartDate,
    int scanLimitDays = _scheduleScanLimitDays,
  }) {
    final missed = <MissedDay>[];
    final startDateOnly = planStartDate != null ? _dateOnly(planStartDate) : null;

    for (int offset = 1; offset <= scanLimitDays; offset++) {
      final date = DateTime(today.year, today.month, today.day)
          .subtract(Duration(days: offset));

      // Scanning strictly backward in time — once a date is before the
      // plan's start, every earlier offset will be too.
      if (startDateOnly != null && date.isBefore(startDateOnly)) break;

      final planDay = ScheduleMatcher.planDayForWeekday(planDays, date.weekday);
      if (planDay == null || planDay['dayType'] == 'rest') continue;

      final muscleGroups = _muscleGroupsForPlanDay(planDay);
      if (muscleGroups.isEmpty) continue;

      if (ScheduleMatcher.logForDate(logs, date) != null) continue; // completed, not missed

      for (final group in muscleGroups) {
        if (resolvedKeys.contains(_missedDayKey(group, date))) continue;
        missed.add(MissedDay(muscleGroup: group, date: date));
      }
    }

    return missed;
  }

  /// Finds every valid empty day to move [muscleGroup]'s [missedDate]
  /// session to (Part A). Forward-scanning mirror of the old backward
  /// streak scan. A candidate date must be:
  ///   1. Strictly after [missedDate], and after today if [missedDate] is
  ///      in the past.
  ///   2. At least 48 hours after [lastTrainedDate] — the muscle group's
  ///      actual last completed session, not the missed scheduled date.
  ///   3. Strictly before the next already-scheduled occurrence of
  ///      [muscleGroup] in the plan.
  ///   4. An empty day — no plan day or a rest day, and no existing
  ///      override already occupying it.
  /// Returns every date in [candidateStart, nextOccurrence) satisfying
  /// constraint 4, in order — possibly empty, including when constraint 2
  /// pushes at or past constraint 3 (no valid window at all). This is a
  /// separate axis from the missed-day reschedule-eligibility expiry (see
  /// [_rescheduleExpiryDays]/[partitionMissedDaysByExpiry]) — no "within N
  /// days" cutoff is applied here; the four constraints above are the
  /// complete window definition.
  static List<DateTime> computeValidRescheduleDays({
    required List<Map<String, dynamic>> planDays,
    required List<Map<String, dynamic>> overrides,
    required String muscleGroup,
    required DateTime missedDate,
    required DateTime? lastTrainedDate,
    required DateTime today,
    int scanLimitDays = _scheduleScanLimitDays,
  }) {
    final missedDay = _dateOnly(missedDate);
    final todayOnly = _dateOnly(today);

    // Constraint 1.
    final afterMissed = missedDay.add(const Duration(days: 1));
    final afterToday = todayOnly.add(const Duration(days: 1));
    var candidateStart = afterMissed.isAfter(afterToday) ? afterMissed : afterToday;

    // Constraint 3: next already-scheduled occurrence of the same muscle
    // group, scanning forward from the missed day.
    DateTime? nextOccurrence;
    for (int offset = 1; offset <= scanLimitDays; offset++) {
      final date = missedDay.add(Duration(days: offset));
      final resolvedDay = ScheduleMatcher.resolvedDayForDate(planDays, overrides, date);
      if (resolvedDay == null || resolvedDay['dayType'] == 'rest') continue;
      if (_muscleGroupsForPlanDay(resolvedDay).contains(muscleGroup)) {
        nextOccurrence = date;
        break;
      }
    }
    if (nextOccurrence == null) return const []; // no known bound — can't confirm a safe window

    // Constraint 2.
    if (lastTrainedDate != null) {
      final floor = _dateOnly(lastTrainedDate).add(const Duration(days: 2));
      if (floor.isAfter(candidateStart)) candidateStart = floor;
    }

    if (!candidateStart.isBefore(nextOccurrence)) {
      return const []; // constraint 2 pushed at/past constraint 3 — no window, not even same-day
    }

    // Constraint 4: every empty day in [candidateStart, nextOccurrence).
    final validDays = <DateTime>[];
    for (DateTime date = candidateStart;
        date.isBefore(nextOccurrence);
        date = date.add(const Duration(days: 1))) {
      final resolvedDay = ScheduleMatcher.resolvedDayForDate(planDays, overrides, date);
      if (resolvedDay == null || resolvedDay['dayType'] == 'rest') {
        validDays.add(date);
      }
    }

    return validDays;
  }

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
  /// written before that field existed. Shared by
  /// [_muscleGroupsForPlanDay] and [resolveMissedDayAsRescheduled] so both
  /// use the same one resolution rule (Decision #46).
  static String? _exerciseMuscleGroup(Map<String, dynamic> exercise) {
    final name = exercise['exerciseName'] as String?;
    return exercise['muscleGroup'] as String? ??
        (name != null ? findExerciseByName(name)?.muscleGroup : null);
  }

  /// Fetches this user's active plan, recent logs, and already-resolved
  /// missed days, runs [computeMissedDays] over them, then sweeps the
  /// result through [partitionMissedDaysByExpiry]: anything past the
  /// [_rescheduleExpiryDays]-day window is auto-resolved as skipped right
  /// here (same [resolveMissedDayAsSkipped] path an explicit "Skip
  /// entirely" tap uses) before this returns, so the caller never has to
  /// separately remember to do it. [actionable] is what the popup should
  /// show as live cards; [autoSkipped] is what it should show read-only.
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
    final resolvedKeys = await _getResolvedMissedDayKeys(uid);

    // Bounds the backward scan to when this plan actually came into
    // existence — see computeMissedDays' planStartDate doc. Old plans
    // written before generatedAt existed fall back to null (unbounded),
    // same as before this fix.
    final generatedAtStr = plan['generatedAt'] as String?;
    final planStartDate =
        generatedAtStr != null ? DateTime.tryParse(generatedAtStr) : null;

    final allMissed = computeMissedDays(
      planDays: planDays,
      logs: logs,
      resolvedKeys: resolvedKeys,
      today: DateTime.now(),
      planStartDate: planStartDate,
    );

    final partition = partitionMissedDaysByExpiry(
      missedDays: allMissed,
      today: DateTime.now(),
    );

    for (final expired in partition.expired) {
      await resolveMissedDayAsSkipped(
        uid: uid,
        muscleGroup: expired.muscleGroup,
        missedDate: expired.date,
      );
    }

    return (actionable: partition.actionable, autoSkipped: partition.expired);
  }

  /// Fetches this user's active plan + overrides + [muscleGroup]'s actual
  /// last-trained date, and runs [computeValidRescheduleDays] over them.
  Future<List<DateTime>> findValidRescheduleDays({
    required String uid,
    required String muscleGroup,
    required DateTime missedDate,
  }) async {
    final plan = await WorkoutPlanService().getActivePlan(uid);
    if (plan == null) return const [];

    final planDays = (plan['days'] as List).cast<Map<String, dynamic>>();
    final overrides = await WorkoutPlanService().getScheduleOverrides(uid);
    final lastTrainedDate = await WorkoutLogService()
        .getLastTrainedDate(uid: uid, muscleGroup: muscleGroup);

    return computeValidRescheduleDays(
      planDays: planDays,
      overrides: overrides,
      muscleGroup: muscleGroup,
      missedDate: missedDate,
      lastTrainedDate: lastTrainedDate,
      today: DateTime.now(),
    );
  }

  Future<Set<String>> _getResolvedMissedDayKeys(String uid) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('missedDayResolutions')
        .get();

    return snapshot.docs.map((d) => d.id).toSet();
  }

  /// Part B, "Move to [date]": records this missed day as rescheduled
  /// (never a skip — nothing is written to adaptationProposals) and
  /// installs the one-time schedule override so the moved session
  /// actually appears on [rescheduledTo]. Only [muscleGroup]'s exercises
  /// from the originally-missed day move — if that day trained several
  /// muscle groups (e.g. a combined Push day), the others are unaffected
  /// and keep whatever resolution they get on their own.
  Future<void> resolveMissedDayAsRescheduled({
    required String uid,
    required String muscleGroup,
    required DateTime missedDate,
    required DateTime rescheduledTo,
  }) async {
    try {
      final plan = await WorkoutPlanService().getActivePlan(uid);
      final planDays = (plan?['days'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final originalDay = ScheduleMatcher.planDayForWeekday(planDays, missedDate.weekday);
      final allExercises =
          (originalDay?['exercises'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final groupExercises = allExercises
          .where((exercise) => _exerciseMuscleGroup(exercise) == muscleGroup)
          .toList();

      await WorkoutPlanService().addScheduleOverride(
        uid: uid,
        date: rescheduledTo,
        muscleGroup: muscleGroup,
        workoutName: '$muscleGroup (Rescheduled)',
        exercises: groupExercises,
        sourceMissedDate: ScheduleMatcher.dateKey(missedDate),
      );

      await _db
          .collection('users')
          .doc(uid)
          .collection('missedDayResolutions')
          .doc(_missedDayKey(muscleGroup, missedDate))
          .set({
        'muscleGroup': muscleGroup,
        'missedDate': ScheduleMatcher.dateKey(missedDate),
        'status': 'rescheduled',
        'rescheduledToDate': ScheduleMatcher.dateKey(rescheduledTo),
        'resolvedAt': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      // Surfaced rather than left silent: a caller awaiting this (the
      // missed-day popup) needs the rejection to know the card shouldn't
      // be treated as resolved.
      print('AdaptService.resolveMissedDayAsRescheduled failed for '
          'uid=$uid muscleGroup=$muscleGroup missedDate=$missedDate: $e');
      print(st);
      rethrow;
    }
  }

  /// Part B, "Skip entirely": the only path that counts toward detection.
  /// Records the resolution (so the popup never re-asks about this missed
  /// day) and writes an unconditional adaptationProposals entry — every
  /// explicit skip is recorded, with no streak gate (Decision replaced;
  /// see Part C).
  /// Also the automatic path an app-open sweep uses once a missed day's
  /// 7-day reschedule window has expired (see [findMissedDays] /
  /// [partitionMissedDaysByExpiry]) — same method, same proposal shape,
  /// whether the skip was tapped explicitly or resolved automatically.
  Future<void> resolveMissedDayAsSkipped({
    required String uid,
    required String muscleGroup,
    required DateTime missedDate,
  }) async {
    try {
      await _db
          .collection('users')
          .doc(uid)
          .collection('missedDayResolutions')
          .doc(_missedDayKey(muscleGroup, missedDate))
          .set({
        'muscleGroup': muscleGroup,
        'missedDate': ScheduleMatcher.dateKey(missedDate),
        'status': 'skipped',
        'rescheduledToDate': null,
        'resolvedAt': FieldValue.serverTimestamp(),
      });

      // Idempotency: don't stack a second pending skip proposal for a
      // muscle group that already has one awaiting resolution.
      if (await _hasPendingSkipProposal(uid, muscleGroup)) return;

      final priorLastTrainedDate = await WorkoutLogService()
          .getLastTrainedDate(uid: uid, muscleGroup: muscleGroup);

      final proposal = buildReturnFromBreakProposal(
        muscleGroup: muscleGroup,
        sourceLogId: _missedDayKey(muscleGroup, missedDate),
        priorLastTrainedDate: priorLastTrainedDate,
      );

      await _db
          .collection('users')
          .doc(uid)
          .collection('adaptationProposals')
          .add(proposal);
    } catch (e, st) {
      print('AdaptService.resolveMissedDayAsSkipped failed for '
          'uid=$uid muscleGroup=$muscleGroup missedDate=$missedDate: $e');
      print(st);
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

  /// Predicts fatigue and writes one adaptation proposal per unique primary
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
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/adapt-plan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'avg_rpe': avgRpe,
          'max_rpe': maxRpe,
          'session_duration': sessionDuration,
          'exercises_count': exercisesCount,
          'completion_rate': completionRate,
          'experience_level': experienceLevel,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        throw Exception('Adaptation prediction failed: ${response.statusCode}');
      }

      final result = jsonDecode(response.body) as Map<String, dynamic>;
      final double fatigueScore = (result['fatigue_score'] as num).toDouble();
      final String fatigueLevel = result['fatigue_level'] as String;
      // The backend message describes a raw adjustment.
      print(
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
          sessionDate: DateTime.now(),
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
    } catch (e) {
      print('AdaptService error: $e');
      return '';
    }
  }
}
