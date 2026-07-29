import 'package:cloud_firestore/cloud_firestore.dart';

class WeeklySummaryService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const Duration kSummaryInterval = Duration(days: 7);

  /// Checks whether at least 7 days have passed since the last weeklyn summary
  Future<void> checkAndGenerateWeeklySummary(String uid) async {
    try {
      final profileRef = _db
          .collection('users')
          .doc(uid)
          .collection('profile')
          .doc('data');

      final profileDoc = await profileRef.get();
      final lastCheckStr =
          profileDoc.data()?['lastWeeklySummaryAt'] as String?;
      final lastCheck =
          lastCheckStr != null ? DateTime.tryParse(lastCheckStr) : null;

      final now = DateTime.now();
      if (lastCheck != null && now.difference(lastCheck) < kSummaryInterval) {
        return; // not due yet
      }

      await _generateSummary(uid, now);

      // Advance the checkpoint regardless
      await profileRef.update({
        'lastWeeklySummaryAt': now.toIso8601String(),
      });
    } catch (e) {
      print('checkAndGenerateWeeklySummary failed for $uid: $e');
    }
  }

  Future<void> _generateSummary(String uid, DateTime now) async {
    final weekStart = now.subtract(kSummaryInterval);

    final logsSnapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('workoutLogs')
        .get();

    int sessionsCompleted = 0;
    double totalVolume = 0;
    final List<int> rpeValues = [];

    for (final logDoc in logsSnapshot.docs) {
      final logData = logDoc.data();
      final completedAtStr = logData['completedAt'] as String?;
      if (completedAtStr == null) continue;

      final completedAt = DateTime.tryParse(completedAtStr);
      if (completedAt == null || completedAt.isBefore(weekStart)) continue;

      sessionsCompleted++;
      totalVolume += (logData['totalVolume'] as num?)?.toDouble() ?? 0;

      // Same subcollection-scan pattern as updateMuscleRecovery 
      final exerciseLogsSnap =
          await logDoc.reference.collection('exerciseLogs').get();
      for (final exLogDoc in exerciseLogsSnap.docs) {
        final rpe = exLogDoc.data()['rpeScale'] as int? ?? 5;
        rpeValues.add(rpe);
      }
    }

    final avgRpe = rpeValues.isEmpty
        ? null
        : rpeValues.reduce((a, b) => a + b) / rpeValues.length;

    final summaryRef = _db
        .collection('users')
        .doc(uid)
        .collection('weeklySummaries')
        .doc(); // auto-generated ID 

    await summaryRef.set({
      'weekStart': weekStart.toIso8601String(),
      'weekEnd': now.toIso8601String(),
      'sessionsCompleted': sessionsCompleted,
      'avgRpe': avgRpe,
      'totalVolume': totalVolume,
      'generatedAt': now.toIso8601String(),
    });
  }

  /// Reads recent weekly summaries, most recent first.
  Future<List<Map<String, dynamic>>> getRecentSummaries(
    String uid, {
    int limit = 10,
  }) async {
    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('weeklySummaries')
        .get();

    final summaries = snapshot.docs.map((d) => d.data()).toList();
    summaries.sort((a, b) {
      final aDate = a['generatedAt'] as String? ?? '';
      final bDate = b['generatedAt'] as String? ?? '';
      return bDate.compareTo(aDate);
    });

    return summaries.take(limit).toList();
  }
}