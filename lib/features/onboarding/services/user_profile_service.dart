import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/onboarding_data.dart';
import '../../social/services/public_profile_service.dart';

class UserProfileService {
  // Get a reference to Firestore
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final _publicProfileService = PublicProfileService();

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

    // Public index doc for search/follow — username is already claimed by
    // Step1Profile at this point, this just syncs name/photo alongside it.
    await _publicProfileService.syncPublicProfile(
      uid: uid,
      displayName: data.name,
    );
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

  /// Updates only the `equipment` field on an existing profile doc.
  Future<void> updateEquipment({
    required String uid,
    required Set<EquipmentType> equipment,
  }) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('profile')
        .doc('data')
        .set(
      {'equipment': equipment.map((e) => e.name).toList()},
      SetOptions(merge: true),
    );
  }

  /// Updates the personal-stats fields (age, height, weight, activity
  /// level) plus the unit preference used to display them, without
  /// touching the rest of the profile doc — same single-field merge-write
  /// pattern as updateEquipment. Editing these does not regenerate the
  /// active plan; use PlanResetFlow for that.
  Future<void> updateStats({
    required String uid,
    required int age,
    required double heightCm,
    required double weightKg,
    required ActivityLevel activityLevel,
    required bool isMetric,
  }) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('profile')
        .doc('data')
        .set(
      {
        'age': age,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'activityLevel': activityLevel.name,
        'isMetric': isMetric,
      },
      SetOptions(merge: true),
    );
  }

  /// Writes/overwrites the user's profile picture as a base64-encoded
  /// JPEG string, using the same single-field merge-write pattern as
  /// updateEquipment. See ProfilePictureService for why base64 (not
  /// Firebase Storage) is used.
  Future<void> updateProfilePicture({
    required String uid,
    required String base64Image,
  }) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('profile')
        .doc('data')
        .set(
      {'profilePictureBase64': base64Image},
      SetOptions(merge: true),
    );
  }

  /// Removes the user's profile picture field entirely (not just
  /// setting it to an empty string) so the document doesn't carry
  /// dead weight for a user who removed their photo.
  Future<void> removeProfilePicture(String uid) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('profile')
        .doc('data')
        .set(
      {'profilePictureBase64': FieldValue.delete()},
      SetOptions(merge: true),
    );
  }
}