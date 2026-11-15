import 'package:flutter_test/flutter_test.dart';
import 'package:rakan/shared/utils/workout_stats_format.dart';

void main() {
  group('formatLogDuration', () {
    test('prefers exact seconds', () {
      expect(formatLogDuration({'totalDurationSecs': 42, 'totalDurationMins': 0}), '<1m');
      expect(formatLogDuration({'totalDurationSecs': 25 * 60 + 40}), '26m');
      expect(formatLogDuration({'totalDurationSecs': 65 * 60}), '1h 5m');
      expect(formatLogDuration({'totalDurationSecs': 120 * 60}), '2h');
    });

    test('falls back to startedAt/completedAt on full logs', () {
      expect(
        formatLogDuration({
          'startedAt': '2026-11-15T12:00:00.000',
          'completedAt': '2026-11-15T12:48:10.000',
          'totalDurationMins': 48,
        }),
        '48m',
      );
    });

    test('old truncated 0 minutes reads as under a minute, not 0m', () {
      expect(formatLogDuration({'totalDurationMins': 0}), '<1m');
      expect(formatLogDuration({'totalDurationMins': 55}), '55m');
    });

    test('missing duration shows a dash', () {
      expect(formatLogDuration({}), '—');
    });

    test('accepts doubles from Firestore', () {
      expect(formatLogDuration({'totalDurationMins': 30.0}), '30m');
    });
  });

  group('formatLogVolume', () {
    test('missing volume (older follower copy) shows a dash', () {
      expect(formatLogVolume({}), '—');
    });

    test('bodyweight session shows 0 kg', () {
      expect(formatLogVolume({'totalVolume': 0}), '0 kg');
    });

    test('formats kg and thousands', () {
      expect(formatLogVolume({'totalVolume': 850.4}), '850 kg');
      expect(formatLogVolume({'totalVolume': 12450}), '12.4k kg');
    });
  });
}
