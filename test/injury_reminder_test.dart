import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakan/features/coach/services/injury_service.dart';
import 'package:rakan/features/onboarding/models/onboarding_data.dart';
import 'package:rakan/features/workout/services/notification_service.dart';

void main() {
  group('injuryReminderId', () {
    test('is stable for the same injury', () {
      expect(
        NotificationService.injuryReminderId('a1B2c3D4e5F6g7H8i9J0'),
        NotificationService.injuryReminderId('a1B2c3D4e5F6g7H8i9J0'),
      );
    });

    test('differs between injuries', () {
      final ids = {
        for (var i = 0; i < 500; i++)
          NotificationService.injuryReminderId('injuryDoc$i'),
      };
      expect(ids.length, 500);
    });

    test('stays clear of the weekly/day/test IDs and fits a 32-bit int', () {
      for (final docId in ['', 'x', 'zzzzzzzzzzzzzzzzzzzz', 'A9fK2mQ7pL0sT3vW8yZ1']) {
        final id = NotificationService.injuryReminderId(docId);
        expect(id, greaterThanOrEqualTo(1000), reason: docId);
        expect(id, lessThan(0x7fffffff), reason: docId);
      }
    });
  });

  group('injuryReminderTime', () {
    test('is 9:00 AM on the logged date plus the estimate', () {
      final logged = DateTime(2026, 10, 13, 21, 45);
      expect(
        NotificationService.injuryReminderTime(logged, 5),
        DateTime(2026, 10, 18, 9),
      );
    });

    test('rolls over month and year ends', () {
      expect(
        NotificationService.injuryReminderTime(DateTime(2026, 12, 20, 8), 21),
        DateTime(2027, 1, 10, 9),
      );
    });

    test('is null without an estimate ("Not sure yet")', () {
      expect(
        NotificationService.injuryReminderTime(DateTime(2026, 10, 13), null),
        isNull,
      );
      expect(NotificationService.injuryReminderTime(null, 10), isNull);
    });
  });

  test('reminder body names the injury and points to Recovery Map', () {
    expect(
      NotificationService.injuryReminderBody('Runner\'s Knee'),
      "Is your Runner's Knee better? Mark it recovered in Recovery Map so it returns to your plan.",
    );
    expect(
      NotificationService.injuryReminderBody('Migraine', affectsPlan: false),
      'Is your Migraine better? Mark it recovered in Recovery Map.',
    );
  });

  group('injuriesNeedingReminder (Recovery Map backfill)', () {
    final now = DateTime(2026, 10, 13, 12);
    final loggedYesterday = Timestamp.fromDate(DateTime(2026, 10, 12, 18));

    Map<String, dynamic> injury(String id, {Map<String, dynamic>? extra}) => {
      'id': id,
      'region': 'leftKnee',
      'label': 'Sprain',
      'status': 'active',
      'loggedAt': loggedYesterday,
      'estimatedRecoveryDays': 10,
      ...?extra,
    };

    test('picks active injuries with a future date and no reminder yet', () {
      final result = InjuryService.injuriesNeedingReminder([
        injury('due'),
        injury('alreadyScheduled', extra: {'reminderNotificationId': 1234}),
        injury('recovering', extra: {'status': 'recovering'}),
        injury('recovered', extra: {'status': 'recovered'}),
        injury('notSure', extra: {'estimatedRecoveryDays': null}),
        injury('pastDue', extra: {'estimatedRecoveryDays': 1}),
        injury('pendingTimestamp', extra: {'loggedAt': null}),
      ], now: now);
      expect(result.map((i) => i['id']), ['due']);
    });

    test('an onboarding injury (no estimate fields at all) is skipped', () {
      final result = InjuryService.injuriesNeedingReminder([
        {
          'id': 'seeded',
          'region': 'leftKnee',
          'label': 'Sprain',
          'status': 'active',
          'loggedAt': loggedYesterday,
        },
      ], now: now);
      expect(result, isEmpty);
    });
  });

  group('excludedGroupsFor', () {
    test('is empty once every injury is recovered', () {
      expect(
        InjuryService.excludedGroupsFor([
          {'region': 'leftKnee', 'status': 'recovered'},
        ]),
        isEmpty,
      );
    });

    test('head and neck injuries pause nothing', () {
      expect(
        InjuryService.excludedGroupsFor([
          {'region': 'head', 'status': 'active'},
          {'region': 'neck', 'status': 'active'},
        ]),
        isEmpty,
      );
    });

    test('unions the groups of active and recovering injuries', () {
      expect(
        InjuryService.excludedGroupsFor([
          {'region': 'leftKnee', 'status': 'active'},
          {'region': 'lowerBack', 'status': 'recovering'},
          {'region': 'chest', 'status': 'recovered'},
        ]),
        {'legs', 'back', 'abs'},
      );
    });
  });

  test('onboarding injuries seed with the same shape as the profile', () {
    const entry = InjuryEntry(
      region: BodyRegion.rightShoulder,
      label: 'Rotator Cuff Strain',
    );
    expect(entry.toMap(), {
      'region': 'rightShoulder',
      'label': 'Rotator Cuff Strain',
      'isCustom': false,
    });
    expect(OnboardingData(injuries: [entry]).toMap()['injuries'], [
      entry.toMap(),
    ]);
  });
}
