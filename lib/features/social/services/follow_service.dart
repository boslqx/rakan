import 'package:cloud_firestore/cloud_firestore.dart';

enum FollowStatus { self, none, pending, accepted }

/// Manages the `follows` collection. Doc id is deterministic
/// (`{followerUid}_{followingUid}`) so "do I already follow this person"
/// is a single-doc read, not a query.
///
/// Follower/following counts are computed on demand via count()
/// aggregation queries rather than denormalized counters — a counter
/// would need user A's follow to increment a field on user B's doc, which
/// the existing owner-only `users/{uid}` write rule blocks (safely opening
/// that up would need a Cloud Function, which this project doesn't have).
/// count() queries are billed as a single read regardless of match size,
/// so this is cheap at this app's scale and avoids denormalization drift.
class FollowService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _followDoc(
      String followerUid, String followingUid) {
    return _db.collection('follows').doc('${followerUid}_$followingUid');
  }

  /// Follows [followingUid] as [followerUid]. If the target account is
  /// private, this creates a pending request instead of following
  /// immediately. No-op if a follow/request already exists.
  Future<void> followUser({
    required String followerUid,
    required String followingUid,
  }) async {
    if (followerUid == followingUid) return;

    final followRef = _followDoc(followerUid, followingUid);
    final existing = await followRef.get();
    if (existing.exists) return;

    final targetSnap = await _db.collection('users').doc(followingUid).get();
    final isPrivate = targetSnap.data()?['isPrivate'] as bool? ?? false;

    await followRef.set({
      'followerUid': followerUid,
      'followingUid': followingUid,
      'status': isPrivate ? 'pending' : 'accepted',
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  /// Removes a follow relationship, whichever side initiated it (unfollow,
  /// cancelling your own pending request, or a target declining/removing
  /// someone).
  Future<void> removeFollow({
    required String followerUid,
    required String followingUid,
  }) async {
    await _followDoc(followerUid, followingUid).delete();
  }

  /// Accepts a pending request from [followerUid] to follow [followingUid]
  /// — called by the account being followed.
  Future<void> acceptRequest({
    required String followerUid,
    required String followingUid,
  }) async {
    final followRef = _followDoc(followerUid, followingUid);
    final snap = await followRef.get();
    if (!snap.exists || snap.data()?['status'] != 'pending') return;

    await followRef.update({'status': 'accepted'});
  }

  /// The relationship from [viewerUid]'s perspective looking at [targetUid].
  Future<FollowStatus> getFollowStatus({
    required String viewerUid,
    required String targetUid,
  }) async {
    if (viewerUid == targetUid) return FollowStatus.self;

    final snap = await _followDoc(viewerUid, targetUid).get();
    if (!snap.exists) return FollowStatus.none;

    return snap.data()?['status'] == 'accepted'
        ? FollowStatus.accepted
        : FollowStatus.pending;
  }

  Future<int> getFollowerCount(String uid) async {
    final agg = await _db
        .collection('follows')
        .where('followingUid', isEqualTo: uid)
        .where('status', isEqualTo: 'accepted')
        .count()
        .get();
    return agg.count ?? 0;
  }

  Future<int> getFollowingCount(String uid) async {
    final agg = await _db
        .collection('follows')
        .where('followerUid', isEqualTo: uid)
        .where('status', isEqualTo: 'accepted')
        .count()
        .get();
    return agg.count ?? 0;
  }

  /// Accepted followers of [uid], newest first, with their public profile
  /// fields merged in. Sorted in Dart (not via orderBy) to avoid requiring
  /// a Firestore composite index — same approach as
  /// WorkoutLogService.getRecentLogs.
  Future<List<Map<String, dynamic>>> getFollowers(String uid) async {
    final snapshot = await _db
        .collection('follows')
        .where('followingUid', isEqualTo: uid)
        .where('status', isEqualTo: 'accepted')
        .get();

    return _withProfiles(snapshot.docs, (d) => d['followerUid'] as String);
  }

  /// Accounts [uid] accepted-follows, newest first, with public profile
  /// fields merged in.
  Future<List<Map<String, dynamic>>> getFollowing(String uid) async {
    final snapshot = await _db
        .collection('follows')
        .where('followerUid', isEqualTo: uid)
        .where('status', isEqualTo: 'accepted')
        .get();

    return _withProfiles(snapshot.docs, (d) => d['followingUid'] as String);
  }

  /// Incoming pending requests to follow [uid] — only meaningful for a
  /// private account, since public accounts auto-accept on follow.
  Future<List<Map<String, dynamic>>> getPendingRequests(String uid) async {
    final snapshot = await _db
        .collection('follows')
        .where('followingUid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .get();

    return _withProfiles(snapshot.docs, (d) => d['followerUid'] as String);
  }

  Future<List<Map<String, dynamic>>> _withProfiles(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> followDocs,
    String Function(Map<String, dynamic>) uidOf,
  ) async {
    final sorted = followDocs.toList()
      ..sort((a, b) {
        final aDate = a.data()['createdAt'] as String? ?? '';
        final bDate = b.data()['createdAt'] as String? ?? '';
        return bDate.compareTo(aDate);
      });

    return Future.wait(sorted.map((doc) async {
      final uid = uidOf(doc.data());
      final profileSnap = await _db.collection('users').doc(uid).get();
      return {'uid': uid, ...?profileSnap.data()};
    }));
  }
}
