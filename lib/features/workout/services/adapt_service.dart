import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AdaptService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _baseUrl = 'https://rakan-backend.onrender.com';

  /// predicts fatigue, and adapts the next workout days in the active plan.
  Future<String> predictAndAdapt({
    required String uid,
    required double avgRpe,
    required double maxRpe,
    required double sessionDuration, // in minutes
    required int exercisesCount,
    required double completionRate,
  }) async {
    try {
      // Get user experience level from profile
      final profileSnap = await _db
          .collection('users')
          .doc(uid)
          .collection('profile')
          .doc('data')
          .get();

      final profileData = profileSnap.data() ?? {};
      final experienceStr = profileData['experience'] as String? ?? 'beginner';
      final experienceLevel = _experienceToInt(experienceStr);

      // Call /adapt-plan endpoint
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
      ).timeout(const Duration(seconds: 60)); // allow for cold start

      if (response.statusCode != 200) {
        print('AdaptService: API error ${response.statusCode}');
        return '';
      }

      final result = jsonDecode(response.body);
      final double intensityAdj = (result['intensity_adjustment'] as num).toDouble();
      final String fatigueLevel = result['fatigue_level'] as String;
      final double fatigueScore = (result['fatigue_score'] as num).toDouble();

      print('AdaptService: fatigue=$fatigueLevel ($fatigueScore), adjustment=$intensityAdj');

      // If no adjustment needed, stop here
      if (intensityAdj == 0.0) return result['message'] as String;

      // Find the active workout plan
      final plansSnap = await _db
          .collection('users')
          .doc(uid)
          .collection('workoutPlans')
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (plansSnap.docs.isEmpty) {
        print('AdaptService: No active plan found');
        return result['message'] as String;
      }

      final planDoc = plansSnap.docs.first;
      final planId = planDoc.id;

      // Get today's weekday 
      final todayWeekday = DateTime.now().weekday;

      // 5. Load all days in the plan
      final daysSnap = await _db
          .collection('users')
          .doc(uid)
          .collection('workoutPlans')
          .doc(planId)
          .collection('days')
          .get();

      // For each FUTURE workout day, adapt exercises
      for (final dayDoc in daysSnap.docs) {
        final dayData = dayDoc.data();
        final int dayOfWeek = dayData['dayOfWeek'] as int? ?? 0;
        final bool isRestDay = dayData['isRestDay'] as bool? ?? true;

        // Skip past days, today, and rest days
        if (dayOfWeek <= todayWeekday || isRestDay) continue;

        // Load exercises for this day
        final exercisesSnap = await _db
            .collection('users')
            .doc(uid)
            .collection('workoutPlans')
            .doc(planId)
            .collection('days')
            .doc(dayDoc.id)
            .collection('exercises')
            .get();

        // Adapt each exercise
        for (final exDoc in exercisesSnap.docs) {
          final exData = exDoc.data();
          final int currentSets = exData['sets'] as int? ?? 3;
          final int currentReps = exData['reps'] as int? ?? 10;

          // Apply adjustment with bounds
          final int newSets = _clampInt(
            (currentSets * (1 + intensityAdj)).round(),
            min: 1, max: 6,
          );
          final int newReps = _clampInt(
            (currentReps * (1 + intensityAdj)).round(),
            min: 3, max: 20,
          );

          // Only write if something actually changed
          if (newSets != currentSets || newReps != currentReps) {
            await exDoc.reference.update({
              'sets': newSets,
              'reps': newReps,
              'adaptedAt': FieldValue.serverTimestamp(),
              'fatigueLevel': fatigueLevel,
            });
          }
        }
      }

      print('AdaptService: Plan adapted successfully');
      return result['message'] as String;

    } catch (e) {
      print('AdaptService error (non-critical): $e');
      return '';
    }
  }

  /// Converts experience string from onboarding to int for the ML model
  int _experienceToInt(String experience) {
    switch (experience.toLowerCase()) {
      case 'beginner': return 0;
      case 'intermediate': return 1;
      case 'advanced': return 2;
      default: return 0;
    }
  }

  int _clampInt(int value, {required int min, required int max}) {
    return value.clamp(min, max);
  }
}