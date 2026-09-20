import 'package:shared_preferences/shared_preferences.dart';

/// Client-side brute-force slowdown for email/password login. Persisted so
/// restarting the app doesn't clear it. Firebase also rate-limits server-side;
/// this just adds friction and a clear message before that kicks in.
class LoginThrottle {
  LoginThrottle._();

  static const _failsKey = 'login_fail_count';
  static const _lockKey = 'login_lock_until';
  static const _freeAttempts = 5;

  static Future<Duration> remainingLock() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = prefs.getInt(_lockKey) ?? 0;
      final left = until - DateTime.now().millisecondsSinceEpoch;
      return left > 0 ? Duration(milliseconds: left) : Duration.zero;
    } catch (_) {
      return Duration.zero;
    }
  }

  /// Records a failed attempt; returns the lock duration if one now applies.
  static Future<Duration> recordFailure() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fails = (prefs.getInt(_failsKey) ?? 0) + 1;
      await prefs.setInt(_failsKey, fails);
      if (fails < _freeAttempts) return Duration.zero;
      // 30s, 60s, 120s ... capped at 15 minutes.
      final secs = (30 * (1 << (fails - _freeAttempts).clamp(0, 5)))
          .clamp(30, 900);
      final lock = Duration(seconds: secs);
      await prefs.setInt(
        _lockKey,
        DateTime.now().add(lock).millisecondsSinceEpoch,
      );
      return lock;
    } catch (_) {
      return Duration.zero;
    }
  }

  static Future<void> reset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_failsKey);
      await prefs.remove(_lockKey);
    } catch (_) {}
  }
}
