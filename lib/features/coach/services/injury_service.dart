import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../workout/services/workout_plan_service.dart';
import '../../onboarding/services/user_profile_service.dart';

/// Maps a BodyRegion (stored as its raw .name string, e.g. "rightShoulder")
const Map<String, List<String>> kBodyRegionToMuscleGroups = {
  'leftShoulder': ['shoulders', 'arms'],
  'rightShoulder': ['shoulders', 'arms'],
  'chest': ['chest'],
  'upperBack': ['back'],
  'leftArm': ['arms'],
  'rightArm': ['arms'],
  'core': ['abs'],
  'lowerBack': ['back', 'abs'],
  'leftHip': ['legs', 'glutes'],
  'rightHip': ['legs', 'glutes'],
  'leftKnee': ['legs'],
  'rightKnee': ['legs'],
  'leftAnkle': ['legs'],
  'rightAnkle': ['legs'],
  // 'head' and 'neck' deliberately omitted
};

class InjuryService {
  static const String _baseUrl = 'https://rakan-backend.onrender.com';
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Computes the union of excluded muscle groups
  Set<String> _computeExcludedGroups(List<Map<String, dynamic>> injuries) {
    final excluded = <String>{};
    for (final injury in injuries) {
      final status = injury['status'] as String?;
      if (status == 'recovered') continue;
      final region = injury['region'] as String?;
      if (region == null) continue;
      final groups = kBodyRegionToMuscleGroups[region];
      if (groups != null) excluded.addAll(groups);
    }
    return excluded;
  }

  /// Fetches current injuries fresh from Firestore 
  Future<void> triggerRegeneration({
    required String uid,
    required String planId,
  }) async {
    final injuriesSnap =
        await _db.collection('users').doc(uid).collection('injuries').get();
    final injuries = injuriesSnap.docs.map((d) => d.data()).toList();
    final excludedGroups = _computeExcludedGroups(injuries).toList();

    // No active injuries at all -> nothing to exclude
    if (excludedGroups.isEmpty) return;

    final profile = await UserProfileService().getUserProfile(uid);
    if (profile == null) return;

    final body = jsonEncode({
      'uid': uid,
      'plan_id': planId,
      'excluded_muscle_groups': excludedGroups,
      'goal': profile['fitnessGoal'] ?? 'muscleGain',
      'experience': profile['experienceLevel'] ?? 'beginner',
      'equipment': (profile['equipment'] as List?)?.cast<String>() ?? [],
      'session_duration': profile['sessionDuration'] ?? 'sixtyMin',
      'focus_areas': (profile['focusAreas'] as List?)?.cast<String>() ?? [],
    });

    // Deliberately NOT re-thrown to the caller 
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/regenerate-plan'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 90));
    } catch (e) {
      // Swallow — regeneration is best-effort. 
    }
  }
}