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

      days.add({...dayData, 'exercises': exercises});
    }

    return days;
  }
}