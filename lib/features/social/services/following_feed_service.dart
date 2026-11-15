import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'follow_service.dart';

/// One followed person's session in the Home following feed.
class FollowingFeedItem {
  final String ownerUid;
  final String displayName;
  final String? username;
  final String? photoBase64;

  /// The `activityFeed` doc, with its id as `logId` (what
  /// ActivityLogCard / ActivityActionsRow expect).
  final Map<String, dynamic> log;

  const FollowingFeedItem({
    required this.ownerUid,
    required this.displayName,
    required this.username,
    required this.photoBase64,
    required this.log,
  });

  String get completedAt => log['completedAt'] as String? ?? '';
}

class FollowingFeed {
  /// How many accounts the viewer accepted-follows (all of them, even past
  /// [FollowingFeedService.maxAccounts]) — 0 means "follows nobody", which
  /// gets a different empty state from "no recent sessions".
  final int followingCount;
  final List<FollowingFeedItem> items;

  const FollowingFeed({required this.followingCount, required this.items});
}

/// Recent sessions from the people a user follows, newest first.
///
/// Reads each followed account's own `users/{uid}/activityFeed` rather than
/// one collection-group query (`where ownerUid in [...]`): the activityFeed
/// read rule checks, per owner, that the account is public or the viewer
/// is an accepted follower, and Firestore can't prove that rule for a
/// collection-group query spanning many owners — it would be rejected
/// outright. Per-owner queries pass the same rule the profile screen
/// already relies on, so private accounts stay visible only to accepted
/// followers. Cost is bounded by [window], [maxItems] and [maxAccounts].
class FollowingFeedService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FollowService _followService = FollowService();

  /// Cards shown at most.
  static const int maxItems = 20;

  /// Only sessions this recent are fetched.
  static const Duration window = Duration(days: 30);

  /// Most recently followed accounts the feed reads from.
  static const int maxAccounts = 50;

  Future<FollowingFeed> load(String viewerUid) async {
    // Accepted follows only (pending requests to private accounts can't
    // read the feed), newest follow first, public profile fields merged in.
    final following = await _followService.getFollowing(viewerUid);
    final accounts = following
        .where((p) => p['uid'] != viewerUid)
        .take(maxAccounts)
        .toList();

    final cutoff = DateTime.now().subtract(window).toIso8601String();

    final perAccount = await Future.wait(accounts.map((profile) async {
      final uid = profile['uid'] as String;
      try {
        // completedAt is an ISO-8601 string, so string order is time order.
        // Range + orderBy on the same single field: no composite index.
        final snap = await _db
            .collection('users')
            .doc(uid)
            .collection('activityFeed')
            .where('completedAt', isGreaterThanOrEqualTo: cutoff)
            .orderBy('completedAt', descending: true)
            .limit(maxItems)
            .get();

        final username = profile['username'] as String?;
        final name = (profile['displayName'] as String?)?.trim();
        return snap.docs.map((d) => FollowingFeedItem(
              ownerUid: uid,
              displayName: (name != null && name.isNotEmpty)
                  ? name
                  : (username ?? 'Rakan user'),
              username: username,
              photoBase64: profile['photoBase64'] as String?,
              log: {'logId': d.id, ...d.data()},
            ));
      } catch (e) {
        // e.g. unfollowed or went private since the follow list was read —
        // skip that one account rather than failing the whole feed.
        debugPrint('FollowingFeedService: feed of $uid skipped: $e');
        return const <FollowingFeedItem>[];
      }
    }));

    final items = perAccount.expand((list) => list).toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));

    return FollowingFeed(
      followingCount: following.length,
      items: items.take(maxItems).toList(),
    );
  }
}
