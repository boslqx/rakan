import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../workout/services/notification_service.dart';

/// Permanently deletes the signed-in user's account and all of their data.
///
/// Google Play requires apps that let people create an account to also let
/// them delete it in-app, and Malaysia's PDPA gives users the right to have
/// their personal data removed.
///
/// Firestore has no "delete a document and everything under it" call on the
/// client, so every known subcollection is walked and deleted explicitly
/// (the Firebase docs recommend a Cloud Function for this, which this
/// zero-cost project doesn't use). The `users/{uid}/{document=**}` rule
/// already lets the owner delete everything under their own document.
///
/// Not removed: comments/likes this user left on OTHER people's posts —
/// those live under the other user's document. They keep the author name
/// that was copied in when posted.
class AccountDeletionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Flat subcollections directly under users/{uid}.
  static const _flatCollections = [
    'profile',
    'scheduleOverrides',
    'missedDayResolutions',
    'adaptationProposals',
    'weightRecords',
    'injuries',
    'muscleRecovery',
    'progressPhotos',
    'weeklySummaries',
  ];

  bool get usesPassword =>
      _auth.currentUser?.providerData
          .any((p) => p.providerId == 'password') ??
      false;

  /// Firebase only allows deleting an account after a recent sign-in, so
  /// the user confirms who they are first. Done BEFORE any data is deleted,
  /// so a wrong password can't leave a half-deleted account.
  /// Returns false if the user cancelled the Google prompt.
  Future<bool> reauthenticate({String? password}) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');

    if (usesPassword) {
      final email = user.email;
      if (email == null || password == null || password.isEmpty) {
        throw 'Enter your password to confirm.';
      }
      try {
        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: email, password: password),
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
          throw 'Incorrect password.';
        }
        if (e.code == 'too-many-requests') {
          throw 'Too many attempts. Please wait a moment and try again.';
        }
        throw 'Could not confirm your identity (${e.code}).';
      }
      return true;
    }

    // Google account: re-run the Google sign-in prompt.
    final googleSignIn = GoogleSignIn();
    await googleSignIn.signOut();
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) return false;
    final googleAuth = await googleUser.authentication;
    await user.reauthenticateWithCredential(
      GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      ),
    );
    return true;
  }

  /// Deletes all data, then the Firebase Auth account. Call
  /// [reauthenticate] first.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not signed in');
    final uid = user.uid;
    final userRef = _db.collection('users').doc(uid);

    final refs = <DocumentReference>[];

    // users/{uid}/workoutPlans/{plan}/days/{day}/exercises/{ex}
    final plans = await userRef.collection('workoutPlans').get();
    for (final plan in plans.docs) {
      final days = await plan.reference.collection('days').get();
      for (final day in days.docs) {
        final exercises = await day.reference.collection('exercises').get();
        refs.addAll(exercises.docs.map((d) => d.reference));
        refs.add(day.reference);
      }
      refs.add(plan.reference);
    }

    // users/{uid}/workoutLogs/{log}/exerciseLogs/{ex}
    final logs = await userRef.collection('workoutLogs').get();
    for (final log in logs.docs) {
      final exLogs = await log.reference.collection('exerciseLogs').get();
      refs.addAll(exLogs.docs.map((d) => d.reference));
      refs.add(log.reference);
    }

    // users/{uid}/activityFeed/{post}/(likes|comments)/{id}
    final feed = await userRef.collection('activityFeed').get();
    for (final post in feed.docs) {
      final likes = await post.reference.collection('likes').get();
      final comments = await post.reference.collection('comments').get();
      refs.addAll(likes.docs.map((d) => d.reference));
      refs.addAll(comments.docs.map((d) => d.reference));
      refs.add(post.reference);
    }

    for (final name in _flatCollections) {
      final snap = await userRef.collection(name).get();
      refs.addAll(snap.docs.map((d) => d.reference));
    }

    // Follow graph, both directions
    final asFollower = await _db
        .collection('follows')
        .where('followerUid', isEqualTo: uid)
        .get();
    final asFollowing = await _db
        .collection('follows')
        .where('followingUid', isEqualTo: uid)
        .get();
    refs.addAll(asFollower.docs.map((d) => d.reference));
    refs.addAll(asFollowing.docs.map((d) => d.reference));

    // Release the username so someone else can claim it
    final publicDoc = await userRef.get();
    final username = publicDoc.data()?['username'] as String?;
    if (username != null && username.isNotEmpty) {
      refs.add(_db.collection('usernames').doc(username.toLowerCase()));
    }

    // The top-level users/{uid} doc goes last
    refs.add(userRef);

    // Firestore batches hold at most 500 writes
    const chunk = 400;
    for (int i = 0; i < refs.length; i += chunk) {
      final batch = _db.batch();
      for (final ref in refs.skip(i).take(chunk)) {
        batch.delete(ref);
      }
      await batch.commit();
    }

    try {
      await NotificationService().cancelAllReminders();
    } catch (_) {}

    await user.delete();

    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
  }
}
