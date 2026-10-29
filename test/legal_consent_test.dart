import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rakan/features/legal/data/legal_content.dart';
import 'package:rakan/features/legal/services/legal_consent_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// V-05: terms acceptance is recorded with a server time and the version
/// (the documents' "last updated" date).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('version is the Terms "last updated" date', () {
    expect(LegalConsentService.currentVersion, termsAndConditions.lastUpdated);
  });

  test('consent fields hold a server timestamp and the version', () {
    final fields = LegalConsentService.consentFields('29 October 2026');
    expect(fields.keys, unorderedEquals(['termsAcceptedAt', 'termsVersion']));
    expect(fields['termsAcceptedAt'], isA<FieldValue>());
    expect(fields['termsVersion'], '29 October 2026');
  });

  test('unverified sign-up keeps the acceptance until onboarding writes it',
      () async {
    final service = LegalConsentService();
    expect(await service.pendingFields('uid-1'), isEmpty);

    await service.recordAcceptance(uid: 'uid-1', canWriteNow: false);
    final pending = await service.pendingFields('uid-1');
    expect(pending['termsVersion'], LegalConsentService.currentVersion);
    expect(await service.pendingFields('uid-2'), isEmpty);

    await service.clearPending('uid-1');
    expect(await service.pendingFields('uid-1'), isEmpty);
  });
}
