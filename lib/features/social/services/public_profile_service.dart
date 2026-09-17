import 'package:cloud_firestore/cloud_firestore.dart';

/// Manages the top-level `users/{uid}` public index doc and the
/// `usernames/{usernameLower}` uniqueness index — the public-facing
/// counterpart to the private, nested `users/{uid}/profile/data` doc that
/// UserProfileService manages. Everything here is meant to be safely
/// readable by any signed-in user (see firestore.rules).
class PublicProfileService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static final RegExp _usernamePattern = RegExp(r'^[a-z0-9_]{3,20}$');

  /// Returns an error message if [username] fails the format rules
  /// (3-20 chars, lowercase letters/digits/underscore only), or null if valid.
  static String? validateUsernameFormat(String username) {
    if (username.isEmpty) return 'Username is required';
    if (!_usernamePattern.hasMatch(username.toLowerCase())) {
      return '3-20 characters: letters, numbers, underscore only';
    }
    return null;
  }

  /// Creates/updates the public index doc for [uid]. Only the fields passed
  /// in are touched (merge-write) — username, counters and isPrivate are
  /// managed separately and never clobbered by a profile-name/photo sync.
  Future<void> syncPublicProfile({
    required String uid,
    String? displayName,
    String? photoBase64,
  }) async {
    final update = <String, dynamic>{'updatedAt': DateTime.now().toIso8601String()};
    if (displayName != null) update['displayName'] = displayName;
    if (photoBase64 != null) update['photoBase64'] = photoBase64;

    await _db.collection('users').doc(uid).set(update, SetOptions(merge: true));
  }

  /// Reads the username currently claimed by [uid], if any.
  Future<String?> getUsername(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data()?['username'] as String?;
  }

  /// Format-valid and not already claimed by a different uid.
  Future<bool> isUsernameAvailable(String username) async {
    if (validateUsernameFormat(username) != null) return false;
    final lower = username.toLowerCase();

    final doc = await _db.collection('usernames').doc(lower).get();
    return !doc.exists;
  }

  /// Atomically claims [username] for [uid], releasing any previously-held
  /// username for that uid in the same transaction. Throws a [StateError]
  /// if the username is already taken by a different uid.
  Future<void> claimUsername({
    required String uid,
    required String username,
  }) async {
    final formatError = validateUsernameFormat(username);
    if (formatError != null) throw FormatException(formatError);

    final lower = username.toLowerCase();
    final newRef = _db.collection('usernames').doc(lower);
    final userRef = _db.collection('users').doc(uid);

    await _db.runTransaction((tx) async {
      final newSnap = await tx.get(newRef);
      if (newSnap.exists && newSnap.data()?['uid'] != uid) {
        throw StateError('username_taken');
      }
      if (newSnap.exists) return; // already owns this exact username

      final userSnap = await tx.get(userRef);
      final oldLower = userSnap.data()?['usernameLower'] as String?;
      if (oldLower != null && oldLower != lower) {
        tx.delete(_db.collection('usernames').doc(oldLower));
      }

      tx.set(newRef, {'uid': uid});
      tx.set(
        userRef,
        {
          'username': username,
          'usernameLower': lower,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        SetOptions(merge: true),
      );
    });
  }

  /// Removes the public copy of the profile photo (mirrors
  /// UserProfileService.removeProfilePicture for the private copy).
  Future<void> clearPhoto(String uid) async {
    await _db.collection('users').doc(uid).set(
      {'photoBase64': FieldValue.delete()},
      SetOptions(merge: true),
    );
  }

  Future<void> setPrivate(String uid, bool isPrivate) async {
    await _db.collection('users').doc(uid).set(
      {'isPrivate': isPrivate},
      SetOptions(merge: true),
    );
  }

  /// Prefix search on `usernameLower`, e.g. "jo" matches "john", "joyce".
  Future<List<Map<String, dynamic>>> searchUsers(String query, {int limit = 20}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    final snapshot = await _db
        .collection('users')
        .where('usernameLower', isGreaterThanOrEqualTo: q)
        .where('usernameLower', isLessThan: '$q')
        .limit(limit)
        .get();

    return snapshot.docs.map((d) => {'uid': d.id, ...d.data()}).toList();
  }
}
