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