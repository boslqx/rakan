import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/legal_content.dart';

/// Records that the user agreed to the Terms & Conditions and Privacy
/// Policy at sign-up, so consent can be shown later. Stored on
/// users/{uid}/profile/data as `termsAcceptedAt` (server time) and
/// `termsVersion` (the documents' "last updated" date).
///
/// A new email/password account can't write to Firestore until its email
/// is verified (`isVerified()` in firestore.rules), so the acceptance is
/// first kept on the device and written together with the onboarding
/// profile. Google accounts are verified at once, so theirs is written
/// straight away.
class LegalConsentService {
  static const _kPendingPrefix = 'pending_terms_version_';

  /// Version the user is agreeing to now.
  static String get currentVersion => termsAndConditions.lastUpdated;

  static Map<String, dynamic> consentFields(String version) => {
        'termsAcceptedAt': FieldValue.serverTimestamp(),
        'termsVersion': version,
      };

  /// Call after a successful sign-up where the user ticked the agreement.
  /// [canWriteNow] is false for an unverified email account.
  Future<void> recordAcceptance({
    required String uid,
    required bool canWriteNow,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_kPendingPrefix$uid', currentVersion);
    if (!canWriteNow) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('profile')
          .doc('data')
          .set(consentFields(currentVersion), SetOptions(merge: true));
      await clearPending(uid);
    } catch (e) {
      // Stays pending; written with the onboarding profile instead.
      debugPrint('Terms acceptance not saved yet: $e');
    }
  }

  /// Consent fields still waiting to be written for [uid], or an empty map.
  Future<Map<String, dynamic>> pendingFields(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final version = prefs.getString('$_kPendingPrefix$uid');
    return version == null ? const {} : consentFields(version);
  }

  Future<void> clearPending(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_kPendingPrefix$uid');
  }

  /// Whether agreement is on record: kept on this device (not yet
  /// written), or already on the profile.
  static bool acceptedFrom({
    required bool pendingOnDevice,
    required Map<String, dynamic>? profile,
  }) =>
      pendingOnDevice || profile?['termsAcceptedAt'] != null;

  /// Checked before onboarding (AuthNavigationService): an account that
  /// never ticked the box on Register — a new Google account from the
  /// Login screen, or an email account first opened on another phone —
  /// is asked once (TermsAgreementScreen).
  Future<bool> hasAccepted(String uid) async {
    if ((await pendingFields(uid)).isNotEmpty) return true;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('profile')
        .doc('data')
        .get();
    return acceptedFrom(pendingOnDevice: false, profile: doc.data());
  }
}
