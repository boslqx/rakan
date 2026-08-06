import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/exercise_data.dart';

class WorkoutPlanService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Fetches the active workout plan for a user.
  /// Returns null if no active plan exists.
  Future<Map<String, dynamic>?> getActivePlan(String uid) async {
    try {
      final activePlansSnapshot = await _db
          .collection('users')
          .doc(uid)
          .collection('workoutPlans')
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (activePlansSnapshot.docs.isEmpty) {
        print('WorkoutPlanService: no active plan found for uid=$uid');
        return null;
      }

      final planDoc = activePlansSnapshot.docs.first;
      final planData = planDoc.data();
      print('WorkoutPlanService: loaded active plan ${planDoc.id} for uid=$uid');

      return {
        ...planData,
        // Injected explicitly rather than assumed to be part of planData —
        // needed so screens can target this specific plan doc (e.g. for
        // swapDays/cancelDay) without guessing whether the underlying
        // document already stores its own ID as a field.
        'id': planDoc.id,
        'days': await _loadDays(uid, planDoc.id),
      };
    } on FirebaseException catch (e) {
      print('WorkoutPlanService: Firestore error for uid=$uid code=${e.code} message=${e.message}');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _loadDays(
    String uid,
    String planId,
  ) async {
    final daysSnapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('workoutPlans')
        .doc(planId)
        .collection('days')
        .orderBy('dayNumber')
        .get();

    final days = <Map<String, dynamic>>[];

    for (final dayDoc in daysSnapshot.docs) {
      final dayData = dayDoc.data();

      final exercisesSnapshot = await _db
          .collection('users')
          .doc(uid)
          .collection('workoutPlans')
          .doc(planId)
          .collection('days')
          .doc(dayDoc.id)
          .collection('exercises')
          .get();

      final exercises = exercisesSnapshot.docs
          .map((e) => {...e.data(), 'docId': e.id})
          .toList();

      // Sort by 'order' if present. Exercises added before this field
      // existed default to a large sort key, so they keep their original
      // (arbitrary) relative order and simply appear after any explicitly
      // ordered ones — nothing breaks for plans generated before reordering
      // was supported.
      exercises.sort((a, b) {
        final orderA = a['order'] as int? ?? 999999;
        final orderB = b['order'] as int? ?? 999999;
        return orderA.compareTo(orderB);
      });

      // 'id' injected here for the same reason as on the plan map — the
      // Schedule tab's edit feature needs each day's Firestore doc ID to
      // call swapDays/cancelDay.
      days.add({...dayData, 'id': dayDoc.id, 'exercises': exercises});
    }

    return days;
  }

  /// Swaps the workout *content* (name, focus, duration, and full
  /// exercise list) between two days in the plan, while keeping each
  /// day's calendar position fixed — dayNumber and dayName never move.
  /// The day type moves with the content, so a workout can be swapped with
  /// a rest day.
  ///
  /// This is a genuine swap, not a copy: whatever Monday had, Wednesday
  /// now has, and vice versa. Because nothing is added or removed, the
  /// plan's total weekly volume is unchanged — which is why this doesn't
  /// need to trigger any special recovery/intensity recalculation; the
  /// existing post-workout adaptation still reacts to whatever actually
  /// gets logged, same as before.
  Future<void> swapDays({
    required String uid,
    required String planId,
    required String dayIdA,
    required String dayIdB,
  }) async {
    // Calendar-position fields stay with their existing documents. The
    // day type (including the legacy isRestDay field) moves with its content.
    const slotFields = {
      'dayNumber', 'dayName', 'dayOfWeek',
    };

    final daysRef = _db
        .collection('users')
        .doc(uid)
        .collection('workoutPlans')
        .doc(planId)
        .collection('days');

    final dayRefA = daysRef.doc(dayIdA);
    final dayRefB = daysRef.doc(dayIdB);

    final dayDocA = await dayRefA.get();
    final dayDocB = await dayRefB.get();
    final dataA = dayDocA.data() ?? {};
    final dataB = dayDocB.data() ?? {};

    final contentA = {
      for (final entry in dataA.entries)
        if (!slotFields.contains(entry.key)) entry.key: entry.value,
    };
    final contentB = {
      for (final entry in dataB.entries)
        if (!slotFields.contains(entry.key)) entry.key: entry.value,
    };
    final slotA = {
      for (final entry in dataA.entries)
        if (slotFields.contains(entry.key)) entry.key: entry.value,
    };
    final slotB = {
      for (final entry in dataB.entries)
        if (slotFields.contains(entry.key)) entry.key: entry.value,
    };

    final exercisesASnap = await dayRefA.collection('exercises').get();
    final exercisesBSnap = await dayRefB.collection('exercises').get();

    final batch = _db.batch();

    // Replace each document's content completely, so workout-only fields
    // cannot remain after that day becomes a rest day.
    batch.set(dayRefA, {...slotA, ...contentB});
    batch.set(dayRefB, {...slotB, ...contentA});

    // Swap the exercises subcollections: remove both, then rewrite each
    // day's subcollection with the other's original exercise docs
    // (original doc IDs preserved, just moved to the other parent).
    for (final doc in exercisesASnap.docs) {
      batch.delete(doc.reference);
    }
    for (final doc in exercisesBSnap.docs) {
      batch.delete(doc.reference);
    }
    for (final doc in exercisesBSnap.docs) {
      batch.set(dayRefA.collection('exercises').doc(doc.id), doc.data());
    }
    for (final doc in exercisesASnap.docs) {
      batch.set(dayRefB.collection('exercises').doc(doc.id), doc.data());
    }

    await batch.commit();
  }

  /// Explicitly cancels a scheduled workout day: converts it to a rest
  /// day and clears its exercises. This is distinct from a day that
  /// simply goes unlogged (shown as "Skipped" on the Home calendar) — a
  /// cancel is a deliberate action taken before the day is attempted.
  Future<void> cancelDay({
    required String uid,
    required String planId,
    required String dayId,
  }) async {
    final dayRef = _db
        .collection('users')
        .doc(uid)
        .collection('workoutPlans')
        .doc(planId)
        .collection('days')
        .doc(dayId);

    final exercisesSnap = await dayRef.collection('exercises').get();

    final batch = _db.batch();
    for (final doc in exercisesSnap.docs) {
      batch.delete(doc.reference);
    }
    batch.update(dayRef, {
      'dayType': 'rest',
      'workoutName': 'Rest Day',
      'focusDescription': '',
      'durationMinutes': 0,
    });

    await batch.commit();
  }

  /// Converts a rest day into a workout day. dayNumber/dayName (calendar
  /// slot) are never touched. If [templateExercises] is provided, they're
  /// batch-written into the exercises subcollection using the exact same
  /// document shape as addExerciseToDay() (exerciseId as millis timestamp,
  /// order as index) — so WorkoutDayDetailScreen reads templated and
  /// manually-added exercises identically, no special-casing needed there.
  Future<Map<String, dynamic>> convertRestDayToWorkout({
    required String uid,
    required String planId,
    required String dayId,
    required String workoutName,
    List<ExerciseData>? templateExercises,
  }) async {
    final dayRef = _db
        .collection('users')
        .doc(uid)
        .collection('workoutPlans')
        .doc(planId)
        .collection('days')
        .doc(dayId);

    final batch = _db.batch();

    batch.update(dayRef, {
      'dayType': 'workout',
      'workoutName': workoutName,
      'focusDescription': '',
      'durationMinutes': 0,
    });

    if (templateExercises != null && templateExercises.isNotEmpty) {
      final exercisesRef = dayRef.collection('exercises');
      final exercisesForDuration = <Map<String, dynamic>>[];

      for (var i = 0; i < templateExercises.length; i++) {
        final ex = templateExercises[i];
        final docRef = exercisesRef.doc();
        final exerciseMap = {
          'exerciseId': DateTime.now().millisecondsSinceEpoch.toString(),
          'exerciseName': ex.name,
          'muscleGroup': ex.muscleGroup,
          'sets': 3,
          'reps': 10,
          'restSeconds': 60,
          'order': i,
        };
        batch.set(docRef, exerciseMap);
        exercisesForDuration.add(exerciseMap);
      }

      // Reuse the exact same deterministic formula from WorkoutDayDetailScreen
      // (reps × 3s, min 15s per set, plus rest between sets).
      const secondsPerRep = 3;
      const minWorkSeconds = 15;
      int totalSeconds = 0;

      for (final ex in exercisesForDuration) {
        final sets = ex['sets'] as int? ?? 3;
        final reps = ex['reps'] as int? ?? 10;
        final restSeconds = ex['restSeconds'] as int? ?? 60;
        final workSeconds = (reps * secondsPerRep) < minWorkSeconds
            ? minWorkSeconds
            : reps * secondsPerRep;
        totalSeconds += sets * workSeconds + (sets - 1) * restSeconds;
      }

      final minutes = (totalSeconds / 60).round();
      batch.update(dayRef, {'durationMinutes': minutes < 10 ? 10 : minutes});
    }

    await batch.commit();

    final snap = await dayRef.get();
    return {...snap.data()!, 'id': snap.id};
  }

  /// Adds a new exercise to a day, appended after its current last
  /// exercise (by 'order'), and writes a fresh duration estimate for the
  /// day in the same batch — computed by the caller (the detail screen),
  /// since only it has the live, up-to-date exercise list to estimate
  /// from.
  Future<void> addExerciseToDay({
    required String uid,
    required String planId,
    required String dayId,
    required Map<String, dynamic> exercise,
    required int order,
    required int newDurationMinutes,
  }) async {
    final dayRef = _db
        .collection('users')
        .doc(uid)
        .collection('workoutPlans')
        .doc(planId)
        .collection('days')
        .doc(dayId);
    final newExerciseRef = dayRef.collection('exercises').doc();

    final batch = _db.batch();
    batch.set(newExerciseRef, {...exercise, 'order': order});
    batch.update(dayRef, {'durationMinutes': newDurationMinutes});
    await batch.commit();
  }

  /// Removes a single exercise from a day (by its Firestore doc ID — see
  /// the 'docId' field injected in [_loadDays]) and updates the day's
  /// duration estimate to match. Remaining exercises' 'order' values are
  /// left as-is — gaps in the sequence don't affect sort correctness.
  Future<void> removeExerciseFromDay({
    required String uid,
    required String planId,
    required String dayId,
    required String exerciseDocId,
    required int newDurationMinutes,
  }) async {
    final dayRef = _db
        .collection('users')
        .doc(uid)
        .collection('workoutPlans')
        .doc(planId)
        .collection('days')
        .doc(dayId);

    final batch = _db.batch();
    batch.delete(dayRef.collection('exercises').doc(exerciseDocId));
    batch.update(dayRef, {'durationMinutes': newDurationMinutes});
    await batch.commit();
  }

  /// Persists a new exercise order for a day, after the user drags to
  /// reorder them in the UI. Takes the exercises' Firestore doc IDs in
  /// their new display order and writes sequential 'order' values.
  Future<void> reorderExercisesInDay({
    required String uid,
    required String planId,
    required String dayId,
    required List<String> orderedExerciseDocIds,
  }) async {
    final exercisesRef = _db
        .collection('users')
        .doc(uid)
        .collection('workoutPlans')
        .doc(planId)
        .collection('days')
        .doc(dayId)
        .collection('exercises');

    final batch = _db.batch();
    for (int i = 0; i < orderedExerciseDocIds.length; i++) {
      batch.update(exercisesRef.doc(orderedExerciseDocIds[i]), {'order': i});
    }
    await batch.commit();
  }
}
