import 'package:flutter_test/flutter_test.dart';
import 'package:rakan/core/utils/validators.dart';
import 'package:rakan/features/coach/services/weight_record_service.dart';

/// V-21: Personal Stats uses the same ranges as onboarding, and a changed
/// weight is also logged as a weight record (Coach shows the newest one).
void main() {
  group('body stat ranges', () {
    test('age follows the onboarding picker (13 to 80)', () {
      expect(Validators.age(13), isNull);
      expect(Validators.age(80), isNull);
      expect(Validators.age(12), isNotNull);
      expect(Validators.age(81), isNotNull);
      expect(Validators.age(null), isNotNull);
    });

    test('height and weight catch typos', () {
      expect(Validators.heightCm(175), isNull);
      expect(Validators.heightCm(1750), isNotNull); // mm typed as cm
      expect(Validators.heightCm(17.5), isNotNull);
      expect(Validators.weightKg(70), isNull);
      expect(Validators.weightKg(7), isNotNull);
      expect(Validators.weightKg(700), isNotNull);
    });

    test('bodyStats reports the first problem', () {
      expect(Validators.bodyStats(age: 25, heightCm: 175, weightKg: 70), isNull);
      expect(
        Validators.bodyStats(age: 25, heightCm: 1750, weightKg: 7),
        startsWith('Height'),
      );
    });
  });

  group('weight record on change', () {
    test('a real change is logged', () {
      expect(WeightRecordService.isWeightChange(70, 68.5), isTrue);
      expect(WeightRecordService.isWeightChange(null, 70), isTrue);
    });

    test('saving the same weight (or a kg/lbs round trip) is not', () {
      expect(WeightRecordService.isWeightChange(70, 70), isFalse);
      // 70 kg shown as 154.3 lbs, saved back as 154.3 / 2.20462 kg.
      expect(WeightRecordService.isWeightChange(70, 154.3 / 2.20462), isFalse);
    });
  });
}
