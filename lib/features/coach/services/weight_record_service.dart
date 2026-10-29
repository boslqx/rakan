import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/weight_record.dart';

class WeightRecordService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Doc id of the entry seeded from the onboarding weight.
  static const startingRecordId = 'onboarding-start';

  /// Whether a weight saved in Personal Stats differs from the one it
  /// replaced enough to log (V-21). The 0.05 kg margin ignores the
  /// rounding of a kg → lbs → kg round trip.
  static bool isWeightChange(double? before, double after) =>
      before == null || (after - before).abs() >= 0.05;

  CollectionReference<Map<String, dynamic>> _collection(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('weightRecords');

  /// Creates a new historical entry. Never overwrites a previous record
  Future<void> addRecord({
    required String uid,
    required WeightRecord record,
  }) async {
    await _collection(uid).doc(record.id).set(record.toMap());
  }

  Future<void> updateRecord({
    required String uid,
    required WeightRecord record,
  }) async {
    await _collection(uid).doc(record.id).set(record.toMap());
  }

  /// Deletes a record
  Future<void> deleteRecord({
    required String uid,
    required String recordId,
  }) async {
    await _collection(uid).doc(recordId).delete();
  }

  /// All records, oldest→newest (the order the Weight Journey graph wants).
  Future<List<WeightRecord>> getAllRecordsAscending(String uid) async {
    final snapshot = await _collection(uid).get();
    final records = snapshot.docs
        .map((d) => WeightRecord.fromMap(d.id, d.data()))
        .toList();
    records.sort((a, b) => a.date.compareTo(b.date));
    return records;
  }

  /// Most recent record, or null if the user has never logged one
  Future<WeightRecord?> getLatestRecord(String uid) async {
    final all = await getAllRecordsAscending(uid);
    return all.isEmpty ? null : all.last;
  }

  /// Adds the weight given at onboarding to the journey as an entry dated
  /// [signedUpAt], so it stays the starting point once the user logs a
  /// weight instead of being replaced by it. Once per user: the profile's
  /// `startingWeightSeeded` flag keeps a deleted starting entry deleted.
  ///
  /// Returns the seeded record for the caller to show straight away, or
  /// null when there's nothing to seed. The write isn't awaited — offline,
  /// Firestore only completes it on reconnect.
  WeightRecord? seedStartingRecord({
    required String uid,
    required Map<String, dynamic>? profile,
    required List<WeightRecord> existing,
    DateTime? signedUpAt,
  }) {
    final weightKg = (profile?['weightKg'] as num?)?.toDouble();
    if (profile?['startingWeightSeeded'] == true ||
        weightKg == null ||
        weightKg <= 0 ||
        existing.any((r) => r.id == startingRecordId)) {
      return null;
    }

    final record = WeightRecord(
      id: startingRecordId,
      date: signedUpAt ?? DateTime.now(),
      weightKg: weightKg,
      description: 'Starting weight from onboarding',
    );
    final batch = _db.batch()
      ..set(_collection(uid).doc(record.id), record.toMap())
      ..set(
        _db.collection('users').doc(uid).collection('profile').doc('data'),
        {'startingWeightSeeded': true},
        SetOptions(merge: true),
      );
    unawaited(batch.commit().catchError(
        (Object e) => debugPrint('Starting weight seed failed: $e')));
    return record;
  }
}
