import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../data/exercise_data.dart';

class LoggedExerciseInfo {
  final String exerciseName;

  LoggedExerciseInfo({required this.exerciseName});
}

class AdaptService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _baseUrl = 'https://rakan-backend.onrender.com';

  /// Builds one proposal payload per unique primary muscle group 
  static List<Map<String, dynamic>> buildSessionProposals({
    required List<LoggedExerciseInfo> sessionExercises,
    required double fatigueScore,
    required String sourceLogId,
  }) {
    final payloads = <Map<String, dynamic>>[];
    final Set<String> seenMuscleGroups = {};

    for (final loggedExercise in sessionExercises) {
      final exerciseData = findExerciseByName(loggedExercise.exerciseName);
      if (exerciseData == null) continue; // unresolvable — nothing to key a proposal on

      final muscleGroup = exerciseData.muscleGroup;
      if (seenMuscleGroups.contains(muscleGroup)) continue; // already proposed this session

      seenMuscleGroups.add(muscleGroup);

      payloads.add({
        'createdAt': FieldValue.serverTimestamp(),
        'muscleGroup': muscleGroup,
        'sessionFatigueScore': fatigueScore,
        'status': 'pending',
        'sourceLogId': sourceLogId,
      });
    }

    return payloads;
  }

  /// Predicts fatigue and writes one adaptation proposal per unique primary
  Future<String> predictAndAdapt({
    required String uid,
    required double avgRpe,
    required double maxRpe,
    required double sessionDuration,
    required int exercisesCount,
    required double completionRate,
    required int experienceLevel,
    required String sourceLogId,
    required List<LoggedExerciseInfo> sessionExercises,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/adapt-plan'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'avg_rpe': avgRpe,
          'max_rpe': maxRpe,
          'session_duration': sessionDuration,
          'exercises_count': exercisesCount,
          'completion_rate': completionRate,
          'experience_level': experienceLevel,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        throw Exception('Adaptation prediction failed: ${response.statusCode}');
      }

      final result = jsonDecode(response.body) as Map<String, dynamic>;
      final double fatigueScore = (result['fatigue_score'] as num).toDouble();
      final String fatigueLevel = result['fatigue_level'] as String;
      // The backend message describes a raw adjustment. 
      print(
        'AdaptService: fatigue=$fatigueLevel; '
        'backend message=${result['message']}',
      );

      
      final proposals = buildSessionProposals(
        sessionExercises: sessionExercises,
        fatigueScore: fatigueScore,
        sourceLogId: sourceLogId,
      );

      final batch = _db.batch();
      final proposalsRef = _db
          .collection('users')
          .doc(uid)
          .collection('adaptationProposals');

      for (final proposal in proposals) {
        batch.set(proposalsRef.doc(), proposal);
      }

      await batch.commit();

      return fatigueLevel;
    } catch (e) {
      print('AdaptService error: $e');
      return '';
    }
  }
}