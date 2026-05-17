import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/onboarding_data.dart';

class UserProfileService {
  // Get a reference to Firestore
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Saves the completed onboarding data to Firestore
  Future<void> saveOnboardingProfile({
    required String uid,
    required OnboardingData data,
  }) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('profile')
        .doc('data')
        .set(data.toMap(), SetOptions(merge: true));
  }

  /// Checks if a user has completed onboarding.
  Future<bool> hasCompletedOnboarding(String uid) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('profile')
        .doc('data')
        .get();

    if (!doc.exists) return false;
    return doc.data()?['onboardingCompleted'] == true;
  }

  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('profile')
        .doc('data')
        .get();

    if (!doc.exists) return null;
    return doc.data();
  }
}