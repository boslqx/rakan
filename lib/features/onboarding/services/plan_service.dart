import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/onboarding_data.dart';

class PlanService {
  // Render backend URL
  static const String _baseUrl = 'https://rakan-backend.onrender.com';

  /// Calls the backend to generate a workout plan and save it to Firestore.
  /// Returns the planId on success, throws an exception on failure.
  Future<String> generatePlan({
    required String uid,
    required OnboardingData data,
  }) async {
    final url = Uri.parse('$_baseUrl/generate-plan');

    // Convert OnboardingData to the format the backend expects.
    final body = jsonEncode({
      'uid': uid,
      'goal': data.fitnessGoal?.name ?? 'muscleGain',
      'experience': data.experienceLevel?.name ?? 'beginner',
      'equipment': data.equipment.map((e) => e.name).toList(),
      'workout_days': data.workoutDays.map((d) => d + 1).toList(),
      'session_duration': data.sessionDuration?.name ?? 'sixtyMin',
      'focus_areas': data.focusAreas.map((f) => f.name).toList(),
    });

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    ).timeout(
      // Render free tier cold starts can take 50+ seconds on first request so give it 90 secs
      const Duration(seconds: 90),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return json['planId'] as String;
    } else {
      throw Exception(
        'Plan generation failed: ${response.statusCode} ${response.body}',
      );
    }
  }
}