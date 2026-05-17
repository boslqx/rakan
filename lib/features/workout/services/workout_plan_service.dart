import 'package:cloud_firestore/cloud_firestore.dart';

class WorkoutPlanService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Fetches the active workout plan for a user.
  /// Returns null if no active plan exists.
  Future<Map<String, dynamic>?> getActivePlan(String uid) async {
    // Fetch all plans then filter in Dart — avoids any index requirements.
    // Each user realistically has very few plans (1-3), so this is fine.
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('workoutPlans')
        .get();

    if (snapshot.docs.isEmpty) return null;

    // Find the active plan in Dart instead of Firestore query
    final activeDocs = snapshot.docs
        .where((doc) => doc.data()['status'] == 'active')
        .toList();

    if (activeDocs.isEmpty) return null;

    final planDoc = activeDocs.first;
    final planData = planDoc.data();

    // Fetch all 7 days ordered by dayNumber
    final daysSnapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('workoutPlans')
        .doc(planDoc.id)
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
          .doc(planDoc.id)
          .collection('days')
          .doc(dayDoc.id)
          .collection('exercises')
          .get();

      final exercises = exercisesSnapshot.docs
          .map((e) => e.data())
          .toList();

      days.add({...dayData, 'exercises': exercises});
    }

    return {...planData, 'days': days};
  }
}