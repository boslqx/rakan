import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../onboarding/services/user_profile_service.dart';
import '../../workout/services/notification_service.dart';

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

  CollectionReference<Map<String, dynamic>> _injuries(String uid) =>
      _db.collection('users').doc(uid).collection('injuries');

  /// Computes the union of excluded muscle groups
  static Set<String> excludedGroupsFor(List<Map<String, dynamic>> injuries) {
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
    final injuriesSnap = await _injuries(uid).get();
    final injuries = injuriesSnap.docs.map((d) => d.data()).toList();
    // Sent even when empty: with no injuries left, the backend restores the
    // days earlier regenerations rested or adjusted, and leaves the rest.
    final excludedGroups = excludedGroupsFor(injuries).toList();

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
      // Local date, so the backend works out "this week" in the user's
      // timezone rather than UTC.
      'client_date': DateTime.now().toIso8601String().substring(0, 10),
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

  /// Copies onboarding (Step 8) injuries, as stored on the profile, into
  /// the injuries subcollection. Callers check the subcollection is empty
  /// first so nothing is seeded twice. No recovery estimate is known for
  /// these, so no check-in reminder is scheduled.
  Future<void> seedFromProfile(String uid, List<dynamic> profileInjuries) async {
    for (final inj in profileInjuries) {
      final injMap = inj as Map<String, dynamic>;
      await _injuries(uid).add({
        'region': injMap['region'] ?? '',
        'label': injMap['label'] ?? '',
        'isCustom': injMap['isCustom'] ?? false,
        'status': 'active',
        'loggedAt': FieldValue.serverTimestamp(),
        'recoveredAt': null,
      });
    }
  }

  /// Runs right after a plan is generated: seeds the onboarding injuries
  /// (first plan only — the subcollection is still empty then), then
  /// rebuilds the new plan around any active injury that pauses a muscle
  /// group, so the very first plan already avoids injured areas. A plan
  /// reset gets the same treatment from injuries already on record.
  Future<void> applyInjuriesToNewPlan({
    required String uid,
    required String planId,
    required List<Map<String, dynamic>> onboardingInjuries,
  }) async {
    var snap = await _injuries(uid).get();
    if (snap.docs.isEmpty && onboardingInjuries.isNotEmpty) {
      await seedFromProfile(uid, onboardingInjuries);
      snap = await _injuries(uid).get();
    }
    final injuries = snap.docs.map((d) => d.data()).toList();
    if (excludedGroupsFor(injuries).isEmpty) return;
    await triggerRegeneration(uid: uid, planId: planId);
  }

  // RECOVERY CHECK-IN REMINDERS

  /// Active injuries that should have a check-in scheduled but don't yet:
  /// a recovery estimate, an expected date still ahead of [now], and no
  /// reminderNotificationId. Each map needs its doc 'id'.
  static List<Map<String, dynamic>> injuriesNeedingReminder(
    List<Map<String, dynamic>> injuries, {
    required DateTime now,
  }) {
    return injuries.where((i) {
      if ((i['status'] as String? ?? 'active') != 'active') return false;
      if (i['reminderNotificationId'] != null) return false;
      final fireAt = NotificationService.injuryReminderTime(
        (i['loggedAt'] as Timestamp?)?.toDate(),
        (i['estimatedRecoveryDays'] as num?)?.toInt(),
      );
      return fireAt != null && fireAt.isAfter(now);
    }).toList();
  }

  /// Schedules one injury's check-in and records its notification ID on the
  /// doc. Returns false when there's nothing to schedule (no estimate, or
  /// the date has passed). Permission is the caller's job.
  Future<bool> scheduleRecoveryReminder({
    required String uid,
    required String injuryId,
    required String region,
    required String label,
    required DateTime? loggedAt,
    required int? estimatedRecoveryDays,
  }) async {
    final fireAt = NotificationService.injuryReminderTime(
      loggedAt,
      estimatedRecoveryDays,
    );
    if (fireAt == null) return false;
    final id = await NotificationService().scheduleInjuryReminder(
      injuryId: injuryId,
      label: label,
      region: region,
      fireAt: fireAt,
      affectsPlan: kBodyRegionToMuscleGroups.containsKey(region),
    );
    if (id == null) return false;
    await _injuries(uid).doc(injuryId).update({'reminderNotificationId': id});
    return true;
  }

  /// Schedules check-ins missing from [injuries] (logged while notifications
  /// were off, or before reminders existed). Never prompts for permission —
  /// this runs whenever Recovery Map loads.
  Future<void> backfillRecoveryReminders(
    String uid,
    List<Map<String, dynamic>> injuries,
  ) async {
    final missing = injuriesNeedingReminder(injuries, now: DateTime.now());
    if (missing.isEmpty) return;
    try {
      if (!await NotificationService().hasPermission()) return;
      for (final injury in missing) {
        await scheduleRecoveryReminder(
          uid: uid,
          injuryId: injury['id'] as String,
          region: injury['region'] as String? ?? '',
          label: injury['label'] as String? ?? 'injury',
          loggedAt: (injury['loggedAt'] as Timestamp?)?.toDate(),
          estimatedRecoveryDays:
              (injury['estimatedRecoveryDays'] as num?)?.toInt(),
        );
      }
    } catch (e) {
      debugPrint('InjuryService reminder backfill error: $e');
    }
  }
}
