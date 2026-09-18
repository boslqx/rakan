import 'package:cloud_firestore/cloud_firestore.dart';

/// Likes and comments on a `users/{ownerUid}/activityFeed/{logId}` entry —
/// the only session representation non-owners can ever read (see
/// firestore.rules), so it's the only place other users can attach
/// interactions to. Counts are computed on demand via count() aggregation
/// queries rather than stored counters, for the same reason
/// FollowService avoids denormalized follower/following counts: a like
/// from user A would need to write a counter field on owner B's doc,
/// which the existing owner-only rule blocks without a Cloud Function.
class ActivityInteractionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _likesRef(String ownerUid, String logId) {
    return _db
        .collection('users')
        .doc(ownerUid)
        .collection('activityFeed')
        .doc(logId)
        .collection('likes');
  }

  CollectionReference<Map<String, dynamic>> _commentsRef(String ownerUid, String logId) {
    return _db
        .collection('users')
        .doc(ownerUid)
        .collection('activityFeed')
        .doc(logId)
        .collection('comments');
  }

  Future<bool> hasLiked({
    required String ownerUid,
    required String logId,
    required String viewerUid,
  }) async {
    final doc = await _likesRef(ownerUid, logId).doc(viewerUid).get();
    return doc.exists;
  }

  Future<int> getLikeCount({required String ownerUid, required String logId}) async {
    final agg = await _likesRef(ownerUid, logId).count().get();
    return agg.count ?? 0;
  }

  /// Likes if not already liked, unlikes if already liked.
  Future<bool> toggleLike({
    required String ownerUid,
    required String logId,
    required String viewerUid,
  }) async {
    final ref = _likesRef(ownerUid, logId).doc(viewerUid);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.delete();
      return false;
    }
    await ref.set({'uid': viewerUid, 'createdAt': DateTime.now().toIso8601String()});
    return true;
  }

  Future<int> getCommentCount({required String ownerUid, required String logId}) async {
    final agg = await _commentsRef(ownerUid, logId).count().get();
    return agg.count ?? 0;
  }

  /// Oldest first (natural reading order for a comment thread).
  Future<List<Map<String, dynamic>>> getComments({
    required String ownerUid,
    required String logId,
  }) async {
    final snapshot = await _commentsRef(ownerUid, logId).get();
    final comments = snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    comments.sort((a, b) {
      final aDate = a['createdAt'] as String? ?? '';
      final bDate = b['createdAt'] as String? ?? '';
      return aDate.compareTo(bDate);
    });
    return comments;
  }

  Future<void> addComment({
    required String ownerUid,
    required String logId,
    required String authorUid,
    required String authorName,
    String? authorPhotoBase64,
    required String text,
  }) async {
    await _commentsRef(ownerUid, logId).add({
      'authorUid': authorUid,
      'authorName': authorName,
      'authorPhotoBase64': authorPhotoBase64,
      'text': text,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteComment({
    required String ownerUid,
    required String logId,
    required String commentId,
  }) async {
    await _commentsRef(ownerUid, logId).doc(commentId).delete();
  }
}
