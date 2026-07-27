import 'package:cloud_firestore/cloud_firestore.dart';

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
        // Injected explicitly rather than assumed to be part of planData 
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
          .map((e) => e.data())
          .toList();

      // 'id' injected here for the same reason as on the plan map
      days.add({...dayData, 'id': dayDoc.id, 'exercises': exercises});
    }

    return days;
  }

  /// Swaps the workout
  Future<void> swapDays({
    required String uid,
    required String planId,
    required String dayIdA,
    required String dayIdB,
  }) async {
    // Only calendar-position fields stay with their existing documents.
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

    // Replace each day document's content completely. This prevents fields
    batch.set(dayRefA, {...slotA, ...contentB});
    batch.set(dayRefB, {...slotB, ...contentA});

    // Swap the exercises subcollections
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

  /// Explicitly cancels a scheduled workout day
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
}
