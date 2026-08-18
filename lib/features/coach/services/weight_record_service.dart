import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/weight_record.dart';

class WeightRecordService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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
}