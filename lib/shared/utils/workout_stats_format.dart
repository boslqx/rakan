/// Display helpers for a workout log's summary stats, shared by every card
/// that shows them (Home, a profile's feed, the following feed, the log
/// detail screen) so they all read the same fields the same way.
///
/// A "log" here is either a full `workoutLogs` doc or its thin
/// `activityFeed` copy — both carry the same summary field names.
library;

/// Exact session length in seconds, or null if the log doesn't say.
///
/// Prefers `totalDurationSecs` (saved since sub-minute sessions started
/// showing "0m"), then the gap between `startedAt` and `completedAt` (full
/// logs only), then the older whole-minute `totalDurationMins`.
int? logDurationSecs(Map<String, dynamic> log) {
  final secs = (log['totalDurationSecs'] as num?)?.toInt();
  if (secs != null) return secs;

  final started = DateTime.tryParse(log['startedAt'] as String? ?? '');
  final completed = DateTime.tryParse(log['completedAt'] as String? ?? '');
  if (started != null && completed != null && !completed.isBefore(started)) {
    return completed.difference(started).inSeconds;
  }

  final mins = (log['totalDurationMins'] as num?)?.toInt();
  if (mins == null) return null;
  // Older saves truncated to whole minutes, so 0 means "under a minute".
  return mins == 0 ? 0 : mins * 60;
}

/// "<1m", "42m", "1h 5m", "2h" — or "—" when the log has no duration.
String formatLogDuration(Map<String, dynamic> log) {
  final secs = logDurationSecs(log);
  if (secs == null) return '—';
  if (secs < 60) return '<1m';
  final totalMins = (secs / 60).round();
  if (totalMins < 60) return '${totalMins}m';
  final h = totalMins ~/ 60;
  final m = totalMins % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// "—" when the log has no volume field at all (older follower copies,
/// until their owner next opens the app); "0 kg" for a session with no
/// weight logged (bodyweight work); otherwise "850 kg" / "12.4k kg".
String formatLogVolume(Map<String, dynamic> log) {
  final kg = (log['totalVolume'] as num?)?.toDouble();
  if (kg == null) return '—';
  if (kg <= 0) return '0 kg';
  if (kg >= 1000) return '${(kg / 1000).toStringAsFixed(1)}k kg';
  return '${kg.toStringAsFixed(0)} kg';
}
