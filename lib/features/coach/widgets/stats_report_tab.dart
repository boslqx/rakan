import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/utils/number_format.dart';
import '../../../shared/widgets/pressable.dart';
import '../../workout/data/exercise_data.dart';
import '../../workout/services/workout_log_service.dart';
import '../../workout/services/workout_plan_service.dart';
import '../../workout/widgets/exercise_media.dart';
import '../services/training_stats.dart';

const List<String> _kMonthAbbrev = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

/// The Coach tab's Stats report. One range control drives the whole page:
/// summary numbers (vs the previous period), the training trend, muscle
/// balance against the plan, consistency, and strength progress.
///
/// Logs, the plan and every log's exercise breakdown are loaded once; all
/// sections are then derived in memory (see training_stats.dart), so
/// changing range, metric or exercise never re-reads Firestore.
class StatsReportTab extends StatefulWidget {
  final String uid;

  const StatsReportTab({super.key, required this.uid});

  @override
  State<StatsReportTab> createState() => _StatsReportTabState();
}

class _StatsReportTabState extends State<StatsReportTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _logs = []; // newest first
  List<Map<String, dynamic>> _planDays = [];
  Map<String, List<Map<String, dynamic>>> _exerciseLogs = {};
  bool _exerciseLogsLoading = true;

  StatsRange _range = StatsRange.month;
  int _trendMetric = 0; // 0 workouts, 1 volume, 2 time
  String? _expandedMuscle;
  String? _exercise;
  int _progressRangeIndex = 1;

  static const _rangeLabels = ['THIS WEEK', '30 DAYS', '3 MONTHS'];
  static const _rangeNames = ['this week', 'the last 30 days', 'the last 3 months'];
  static const _progressRangeLabels = ['30D', '90D', 'ALL'];
  static const _progressRangeDays = [30, 90, null];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object?>([
        WorkoutLogService().getRecentLogs(widget.uid, limit: 500),
        WorkoutPlanService().getActivePlan(widget.uid),
      ]);
      if (!mounted) return;
      final plan = results[1] as Map<String, dynamic>?;
      setState(() {
        _logs = (results[0] as List<Map<String, dynamic>>)
            .where(isCompletedLog)
            .toList();
        _planDays =
            (plan?['days'] as List? ?? const []).cast<Map<String, dynamic>>();
        _error = null;
        _loading = false;
      });
      await _loadExerciseLogs();
    } catch (e) {
      debugPrint('StatsReport: load failed: $e');
      if (!mounted) return;
      setState(() {
        _error = "Couldn't load your stats. Pull down to try again.";
        _loading = false;
        _exerciseLogsLoading = false;
      });
    }
  }

  /// Every log's exercise breakdown, fetched once in parallel batches.
  /// (These used to be re-read one log at a time — separately for the
  /// exercise list, the progression chart and muscle focus — and again on
  /// every range or exercise change.)
  Future<void> _loadExerciseLogs() async {
    final service = WorkoutLogService();
    final ids = _logs.map((l) => l['logId'] as String?).whereType<String>().toList();
    final byLog = <String, List<Map<String, dynamic>>>{};
    try {
      const batchSize = 20;
      for (var i = 0; i < ids.length; i += batchSize) {
        final batch = ids.skip(i).take(batchSize).toList();
        final results = await Future.wait(batch.map(
            (id) => service.getExerciseLogsForWorkout(uid: widget.uid, logId: id)));
        for (var j = 0; j < batch.length; j++) {
          byLog[batch[j]] = results[j];
        }
      }
    } catch (e) {
      debugPrint('StatsReport: exercise logs load failed: $e');
    }
    if (!mounted) return;
    final names = loggedExercises(byLog);
    setState(() {
      _exerciseLogs = byLog;
      _exerciseLogsLoading = false;
      if (_exercise == null || !names.contains(_exercise)) {
        _exercise = _mostImproved(names) ?? (names.isEmpty ? null : names.first);
      }
    });
  }

  /// The logged exercise with the biggest relative gain (weight, or reps
  /// for bodyweight) from its first session to its latest — the most
  /// encouraging chart to open on.
  String? _mostImproved(List<String> names) {
    String? best;
    var bestGain = 0.0;
    for (final name in names) {
      final points = progression(_logs, _exerciseLogs, name);
      if (points.length < 2) continue;
      final byReps = points.every((p) => p.maxWeight == 0);
      final first = byReps ? points.first.maxReps.toDouble() : points.first.maxWeight;
      final last = byReps ? points.last.maxReps.toDouble() : points.last.maxWeight;
      if (first <= 0) continue;
      final gain = (last - first) / first;
      if (gain > bestGain) {
        bestGain = gain;
        best = name;
      }
    }
    return best;
  }

  Future<void> _refresh() async {
    setState(() => _exerciseLogsLoading = true);
    await _load();
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    final today = dateOnly(DateTime.now());
    final window = statsWindow(_range, today);
    final summary = summarize(_logs, _planDays, window);
    final previous = summarize(_logs, _planDays, previousWindow(_range, today));

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.primary,
      backgroundColor: AppColors.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          if (_error != null) ...[
            _buildNotice(Icons.error_outline_rounded, _error!),
            const SizedBox(height: 14),
          ],
          if (_logs.isEmpty && _error == null)
            _buildEmptyState()
          else ...[
            _buildRangeSelector(),
            const SizedBox(height: 14),
            _buildSummaryGrid(summary, previous),
            const SizedBox(height: 14),
            _buildTrendCard(today),
            const SizedBox(height: 14),
            _buildMuscleBalanceCard(window),
            const SizedBox(height: 14),
            _buildConsistencyCard(today),
            const SizedBox(height: 14),
            _buildProgressCard(today),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return _card(
      child: Column(
        children: [
          const SizedBox(height: 12),
          Icon(Icons.insights_rounded,
              size: 40, color: AppColors.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(height: 14),
          Text('Your stats start with your first workout',
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
          const SizedBox(height: 6),
          Text(
            'Finish a session and this page fills in — trends, muscle balance against your plan, consistency and strength progress.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
                fontSize: 13, height: 1.5, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildRangeSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (int i = 0; i < StatsRange.values.length; i++)
            Expanded(
              child: Pressable(
                onTap: () {
                  if (_range == StatsRange.values[i]) return;
                  HapticFeedback.selectionClick();
                  setState(() {
                    _range = StatsRange.values[i];
                    _expandedMuscle = null;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _range == StatsRange.values[i]
                        ? AppColors.surfaceContainerHigh
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _rangeLabels[i],
                    textAlign: TextAlign.center,
                    style: _label(
                      fontSize: 11,
                      letterSpacing: 1.2,
                      color: _range == StatsRange.values[i]
                          ? AppColors.onSurface
                          : AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Summary ─────────────────────────────────────────────────────────

  Widget _buildSummaryGrid(PeriodSummary s, PeriodSummary prev) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildKpiTile(
                icon: Icons.fitness_center_rounded,
                label: 'WORKOUTS',
                value: '${s.workouts}',
                delta: _countDelta(s.workouts, prev.workouts),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildKpiTile(
                icon: Icons.timer_outlined,
                label: 'TIME',
                value: _formatMinutes(s.minutes),
                delta: _percentDelta(s.minutes.toDouble(), prev.minutes.toDouble()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildKpiTile(
                icon: Icons.stacked_bar_chart_rounded,
                label: 'VOLUME',
                value: _compactNumber(s.volume),
                unit: ' kg',
                delta: _percentDelta(s.volume, prev.volume),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: _buildAdherenceTile(s)),
          ],
        ),
      ],
    );
  }

  ({String text, bool up})? _countDelta(int now, int before) {
    if (now == before) return null;
    final diff = now - before;
    return (text: '${diff.abs()}', up: diff > 0);
  }

  ({String text, bool up})? _percentDelta(double now, double before) {
    if (before <= 0) return now > 0 ? (text: 'New', up: true) : null;
    final pct = ((now - before) / before * 100).round();
    if (pct == 0) return null;
    return (text: '${pct.abs()}%', up: pct > 0);
  }

  Widget _buildKpiTile({
    required IconData icon,
    required String label,
    required String value,
    String? unit,
    ({String text, bool up})? delta,
  }) {
    return _tile(
      icon: icon,
      label: label,
      value: Text.rich(
        TextSpan(
          text: value,
          children: [
            if (unit != null)
              TextSpan(
                text: unit,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant),
              ),
          ],
        ),
        style: GoogleFonts.spaceGrotesk(
            fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.onSurface, height: 1.1),
      ),
      footer: Row(
        children: [
          if (delta != null) ...[
            Icon(delta.up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 12, color: delta.up ? AppColors.primary : AppColors.onSurfaceVariant),
            const SizedBox(width: 2),
          ],
          Flexible(
            child: Text(
              delta == null ? 'Same as last period' : '${delta.text} vs last period',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: delta?.up == true
                    ? AppColors.primary
                    : AppColors.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdherenceTile(PeriodSummary s) {
    final adherence = s.adherence;
    return _tile(
      icon: Icons.task_alt_rounded,
      label: 'ON PLAN',
      trailing: adherence == null
          ? null
          : SizedBox.square(
              dimension: 26,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: adherence),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => CircularProgressIndicator(
                  value: v,
                  strokeWidth: 3.5,
                  strokeCap: StrokeCap.round,
                  backgroundColor: AppColors.surfaceContainerHigh,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
            ),
      value: Text(
        adherence == null ? '—' : '${(adherence * 100).round()}%',
        style: GoogleFonts.spaceGrotesk(
            fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.onSurface, height: 1.1),
      ),
      footer: Text(
        adherence == null
            ? 'No active plan'
            : '${math.min(s.workouts, s.scheduled)} of ${s.scheduled} done',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.manrope(
            fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String label,
    required Widget value,
    required Widget footer,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: _label())),
              ?trailing,
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: value),
          const SizedBox(height: 6),
          footer,
        ],
      ),
    );
  }

  // ── Training trend ──────────────────────────────────────────────────

  Widget _buildTrendCard(DateTime today) {
    final buckets = trendBuckets(_logs, _range, today);
    double valueOf(TrendBucket b) => switch (_trendMetric) {
          0 => b.workouts.toDouble(),
          1 => b.volume,
          _ => b.minutes.toDouble(),
        };
    final values = buckets.map(valueOf).toList();
    final total = values.fold(0.0, (a, b) => a + b);
    final maxValue = values.fold(0.0, math.max);
    final weeks = math.max(1, statsWindow(_range, today).days / 7);
    final current = buckets.lastIndexWhere((b) => !b.start.isAfter(today));

    final headline = switch (_trendMetric) {
      0 => '${total.round()} workout${total.round() == 1 ? '' : 's'}',
      1 => '${formatThousands(total)} kg',
      _ => _formatMinutes(total.round()),
    };
    final perWeek = switch (_trendMetric) {
      0 => (total / weeks).toStringAsFixed(1),
      1 => '${_compactNumber(total / weeks)} kg',
      _ => _formatMinutes((total / weeks).round()),
    };

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TRAINING TREND', style: _label()),
          const SizedBox(height: 10),
          Wrap(
            runSpacing: 6,
            children: [
              for (final (i, name) in const ['WORKOUTS', 'VOLUME', 'TIME'].indexed)
                _chip(name, selected: _trendMetric == i, onTap: () => setState(() => _trendMetric = i)),
            ],
          ),
          const SizedBox(height: 14),
          Text(headline,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
          Text(
            _range == StatsRange.week ? 'this week so far' : '$perWeek per week on average',
            style: GoogleFonts.manrope(fontSize: 12, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 140,
            child: total == 0
                ? Center(
                    child: Text('Nothing logged in this period yet',
                        style: GoogleFonts.manrope(fontSize: 12, color: AppColors.onSurfaceVariant)),
                  )
                : BarChart(
                    BarChartData(
                      maxY: maxValue * 1.15,
                      alignment: BarChartAlignment.spaceBetween,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            getTitlesWidget: (value, meta) {
                              final label = _bucketLabel(buckets, value.toInt());
                              if (label.isEmpty) return const SizedBox.shrink();
                              return SideTitleWidget(
                                meta: meta,
                                space: 6,
                                fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                                child: Text(label,
                                    style: GoogleFonts.manrope(
                                        fontSize: 9, color: AppColors.onSurfaceVariant)),
                              );
                            },
                          ),
                        ),
                      ),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => AppColors.surfaceContainerHigh,
                          getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                            '${_bucketDate(buckets[group.x])}\n',
                            GoogleFonts.manrope(fontSize: 10, color: AppColors.onSurfaceVariant),
                            children: [
                              TextSpan(
                                text: switch (_trendMetric) {
                                  0 => '${rod.toY.round()} workout${rod.toY.round() == 1 ? '' : 's'}',
                                  1 => '${formatThousands(rod.toY)} kg',
                                  _ => _formatMinutes(rod.toY.round()),
                                },
                                style: GoogleFonts.manrope(
                                    fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                              ),
                            ],
                          ),
                        ),
                      ),
                      barGroups: [
                        for (int i = 0; i < buckets.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: values[i],
                                width: switch (_range) {
                                  StatsRange.week => 18,
                                  StatsRange.month => 5,
                                  StatsRange.quarter => 12,
                                },
                                borderRadius: BorderRadius.circular(3),
                                color: i == current
                                    ? AppColors.primary
                                    : AppColors.primary.withValues(alpha: 0.45),
                                backDrawRodData: BackgroundBarChartRodData(
                                  show: _range != StatsRange.month,
                                  toY: maxValue * 1.15,
                                  color: AppColors.surfaceContainerHigh.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _bucketLabel(List<TrendBucket> buckets, int i) {
    if (i < 0 || i >= buckets.length) return '';
    final start = buckets[i].start;
    switch (_range) {
      case StatsRange.week:
        return 'MTWTFSS'[i];
      case StatsRange.month:
        return (i % 7 == 1) ? '${start.day} ${_kMonthAbbrev[start.month - 1]}' : '';
      case StatsRange.quarter:
        final monthChanged = i == 0 || buckets[i - 1].start.month != start.month;
        // Skip the first column's label if the month turns right after it.
        if (i == 0 && buckets.length > 2 && buckets[2].start.month != start.month) return '';
        return monthChanged ? _kMonthAbbrev[start.month - 1] : '';
    }
  }

  String _bucketDate(TrendBucket b) {
    final d = '${b.start.day} ${_kMonthAbbrev[b.start.month - 1]}';
    return _range == StatsRange.quarter ? 'Week of $d' : d;
  }

  // ── Muscle balance ──────────────────────────────────────────────────

  /// Sets done per muscle against what the plan scheduled in the same
  /// days — replaces the volume radar, which mixed kg (weighted lifts) with
  /// reps (bodyweight) and so couldn't be compared across groups.
  Widget _buildMuscleBalanceCard(StatsWindow window) {
    final rows = _exerciseLogsLoading
        ? <MuscleBalance>[]
        : muscleBalance(_logs, _exerciseLogs, _planDays, window);
    final hasPlan = rows.any((r) => r.targetSets > 0);
    final scale = rows.fold<int>(1, (m, r) => math.max(m, math.max(r.sets, r.targetSets)));
    final insight = muscleBalanceInsight(rows);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('MUSCLE BALANCE', style: _label()),
          const SizedBox(height: 3),
          Text(
            hasPlan
                ? 'Sets done vs scheduled, ${_rangeNames[_range.index]}'
                : 'Sets done, ${_rangeNames[_range.index]}',
            style: GoogleFonts.manrope(fontSize: 12, color: AppColors.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          if (_exerciseLogsLoading)
            const SizedBox(
              height: 120,
              child: Center(
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              ),
            )
          else ...[
            for (final row in rows) _buildMuscleRow(row, scale),
            if (hasPlan)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Container(width: 2, height: 10, color: AppColors.onSurface.withValues(alpha: 0.7)),
                    const SizedBox(width: 6),
                    Text('= scheduled so far', style: GoogleFonts.manrope(fontSize: 10.5, color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
            if (insight.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildNotice(Icons.lightbulb_outline_rounded, insight),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildMuscleRow(MuscleBalance row, int scale) {
    final expanded = _expandedMuscle == row.group;
    final behind = row.progress != null && row.progress! < 0.5;
    final idle = row.sets == 0 && row.targetSets == 0;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return Pressable(
      onTap: idle ? null : () => setState(() => _expandedMuscle = expanded ? null : row.group),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Opacity(
          opacity: idle ? 0.45 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipOval(
                    child: Container(
                      width: 26,
                      height: 26,
                      color: AppColors.surfaceContainerHigh,
                      child: Image.asset(
                        'assets/muscle_illustration/${row.group.toLowerCase()}.png',
                        fit: BoxFit.cover,
                        cacheWidth: (26 * dpr).round(),
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 74,
                    child: Text(row.group,
                        style: GoogleFonts.manrope(
                            fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) => SizedBox(
                        height: 14,
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            TweenAnimationBuilder<double>(
                              tween: Tween(end: row.sets / scale),
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeOutCubic,
                              builder: (_, v, _) => Container(
                                width: c.maxWidth * v,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: behind
                                      ? AppColors.error.withValues(alpha: 0.75)
                                      : AppColors.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            if (row.targetSets > 0)
                              Positioned(
                                left: (c.maxWidth * row.targetSets / scale - 1)
                                    .clamp(0.0, c.maxWidth - 2),
                                child: Container(
                                  width: 2,
                                  height: 14,
                                  color: AppColors.onSurface.withValues(alpha: 0.7),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      row.targetSets > 0 ? '${row.sets}/${row.targetSets}' : '${row.sets}',
                      textAlign: TextAlign.right,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: behind ? AppColors.error : AppColors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topLeft,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.only(left: 36, top: 6),
                        child: Text(
                          [
                            '${row.sets} set${row.sets == 1 ? '' : 's'}',
                            '${row.exercises} exercise${row.exercises == 1 ? '' : 's'}',
                            'trained in ${row.sessions} session${row.sessions == 1 ? '' : 's'}',
                            if (row.targetSets > 0) '${(row.progress! * 100).round()}% of plan',
                          ].join(' · '),
                          style: GoogleFonts.manrope(fontSize: 11.5, color: AppColors.onSurfaceVariant),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Consistency ─────────────────────────────────────────────────────

  /// Last 13 weeks at a glance, plus a WEEK streak (weeks in a row on
  /// plan). Replaces the month calendar and its day streak, which counted
  /// consecutive calendar days — so every planned rest day reset it to 0.
  Widget _buildConsistencyCard(DateTime today) {
    final firstWeek = addDays(weekStart(today), -7 * 12);
    final perWeek = List.filled(13, 0);
    final workedDays = <DateTime>{};
    for (final log in _logs) {
      final date = logDate(log);
      if (date == null || date.isBefore(firstWeek) || date.isAfter(today)) continue;
      workedDays.add(date);
      perWeek[StatsWindow(firstWeek, date).days ~/ 7]++;
    }
    final firstActive = perWeek.indexWhere((n) => n > 0);
    final activeWeeks = firstActive == -1 ? 1 : 13 - firstActive;
    final avg = perWeek.fold(0, (a, b) => a + b) / activeWeeks;
    final best = perWeek.fold(0, math.max);
    final streak = weekStreak(_logs, _planDays, today);
    final target = weeklyTarget(_planDays);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('CONSISTENCY', style: _label()),
              const Spacer(),
              Text('LAST 13 WEEKS', style: _label(fontSize: 9)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _miniStat('$streak', 'WEEK STREAK',
                    hint: _planDays.isEmpty ? 'goal: 1/week' : 'goal: $target/week'),
              ),
              Expanded(child: _miniStat(avg.toStringAsFixed(1), 'AVG / WEEK')),
              Expanded(child: _miniStat('$best', 'BEST WEEK')),
            ],
          ),
          const SizedBox(height: 16),
          _buildActivityGrid(firstWeek, today, workedDays),
          const SizedBox(height: 10),
          Row(
            children: [
              _legendSquare(AppColors.primary),
              const SizedBox(width: 5),
              Text('Workout', style: GoogleFonts.manrope(fontSize: 10.5, color: AppColors.onSurfaceVariant)),
              const SizedBox(width: 14),
              _legendSquare(AppColors.surfaceContainerHigh),
              const SizedBox(width: 5),
              Text('No workout', style: GoogleFonts.manrope(fontSize: 10.5, color: AppColors.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActivityGrid(DateTime firstWeek, DateTime today, Set<DateTime> workedDays) {
    const gap = 3.0;
    const labelWidth = 14.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = math.min(18.0, (constraints.maxWidth - labelWidth - gap * 13) / 13);
        String? monthLabel(int col) {
          final start = addDays(firstWeek, col * 7);
          final prev = addDays(start, -7);
          if (col == 0) {
            // Skip if the month turns within the next two columns.
            final soon = addDays(start, 14);
            return soon.month == start.month ? _kMonthAbbrev[start.month - 1] : null;
          }
          return prev.month != start.month ? _kMonthAbbrev[start.month - 1] : null;
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 14,
              child: Stack(
                children: [
                  for (int col = 0; col < 13; col++)
                    if (monthLabel(col) case final label?)
                      Positioned(
                        left: math.min(labelWidth + gap + col * (cell + gap),
                            constraints.maxWidth - 24),
                        child: Text(label,
                            style: GoogleFonts.manrope(
                                fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.onSurfaceVariant)),
                      ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            for (int row = 0; row < 7; row++)
              Padding(
                padding: EdgeInsets.only(bottom: row == 6 ? 0 : gap),
                child: Row(
                  children: [
                    SizedBox(
                      width: labelWidth,
                      child: Text(row.isEven ? 'MTWTFSS'[row] : '',
                          style: GoogleFonts.manrope(fontSize: 8.5, color: AppColors.onSurfaceVariant)),
                    ),
                    const SizedBox(width: gap),
                    for (int col = 0; col < 13; col++) ...[
                      if (col > 0) const SizedBox(width: gap),
                      Builder(builder: (context) {
                        final date = addDays(firstWeek, col * 7 + row);
                        final future = date.isAfter(today);
                        return Container(
                          width: cell,
                          height: cell,
                          decoration: BoxDecoration(
                            color: future
                                ? Colors.transparent
                                : workedDays.contains(date)
                                    ? AppColors.primary
                                    : AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(3),
                            border: date == today
                                ? Border.all(color: AppColors.primary, width: 1.5)
                                : null,
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _legendSquare(Color color) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      );

  Widget _miniStat(String value, String label, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.onSurface, height: 1.1)),
        const SizedBox(height: 2),
        Text(label, style: _label(fontSize: 9, letterSpacing: 1.2)),
        if (hint != null)
          Text(hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(fontSize: 10, color: AppColors.onSurfaceVariant.withValues(alpha: 0.7))),
      ],
    );
  }

  // ── Strength progress ───────────────────────────────────────────────

  Widget _buildProgressCard(DateTime today) {
    final exercise = _exercise;
    final rangeDays = _progressRangeDays[_progressRangeIndex];
    final points = exercise == null
        ? <ProgressPoint>[]
        : progression(_logs, _exerciseLogs, exercise,
            since: rangeDays == null ? null : addDays(today, -rangeDays + 1));
    // Bodyweight exercises have no weight to chart — track reps instead.
    final byReps = points.isNotEmpty && points.every((p) => p.maxWeight == 0);
    double valueOf(ProgressPoint p) => byReps ? p.maxReps.toDouble() : p.maxWeight;
    final unit = byReps ? 'reps' : 'kg';
    final plateaued = exercise != null && !byReps && isPlateaued(_logs, _exerciseLogs, exercise);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('STRENGTH PROGRESS', style: _label())),
              for (int i = 0; i < _progressRangeLabels.length; i++)
                _chip(_progressRangeLabels[i],
                    selected: _progressRangeIndex == i,
                    compact: true,
                    onTap: () => setState(() => _progressRangeIndex = i)),
            ],
          ),
          const SizedBox(height: 12),
          if (_exerciseLogsLoading)
            const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
            )
          else if (exercise == null)
            Text('Log a workout to start tracking your lifts.',
                style: GoogleFonts.manrope(fontSize: 13, color: AppColors.onSurfaceVariant))
          else ...[
            _buildExercisePicker(exercise),
            const SizedBox(height: 14),
            if (points.isEmpty)
              SizedBox(
                height: 120,
                child: Center(
                  child: Text('No sessions of this exercise in the selected range.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(fontSize: 12, color: AppColors.onSurfaceVariant)),
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(child: _miniStat(_fmt(points.map(valueOf).reduce(math.max)), 'BEST ${unit.toUpperCase()}')),
                  Expanded(child: _miniStat(_fmt(valueOf(points.last)), 'LATEST')),
                  Expanded(child: _buildChangeStat(points.length < 2 ? null : valueOf(points.last) - valueOf(points.first), unit)),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(height: 150, child: _buildProgressChart(points, valueOf, unit)),
            ],
            if (plateaued) ...[
              const SizedBox(height: 12),
              _buildNotice(Icons.trending_flat_rounded,
                  'Plateau: none of your last 4 sessions beat the one before by 2% or more. A deload or a variation can help.'),
            ],
          ],
        ],
      ),
    );
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  Widget _buildChangeStat(double? change, String unit) {
    final text = change == null
        ? '—'
        : change == 0
            ? '±0'
            : '${change > 0 ? '+' : '−'}${_fmt(change.abs())}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.1,
              color: change != null && change > 0 ? AppColors.primary : AppColors.onSurface,
            )),
        const SizedBox(height: 2),
        Text('CHANGE', style: _label(fontSize: 9, letterSpacing: 1.2)),
      ],
    );
  }

  Widget _buildProgressChart(
      List<ProgressPoint> points, double Function(ProgressPoint) valueOf, String unit) {
    final values = points.map(valueOf).toList();
    final best = values.reduce(math.max);
    final low = values.reduce(math.min);
    final pad = math.max(1.0, (best - low) * 0.25);
    final minY = math.max(0.0, (low - pad).floorToDouble());
    var maxY = (best + pad).ceilToDouble();
    if ((maxY - minY) % 2 != 0) maxY += 1; // even span → whole-number middle tick
    final midY = (minY + maxY) / 2;
    bool isTick(double v) => v == minY || v == maxY || v == midY;

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (maxY - minY) / 2,
          checkToShowHorizontalLine: isTick,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColors.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: (maxY - minY) / 2,
              // fl_chart also labels the axis ends — keep just bottom,
              // middle and top.
              getTitlesWidget: (value, meta) => isTick(value)
                  ? Text(_fmt(value),
                      style: GoogleFonts.manrope(fontSize: 9, color: AppColors.onSurfaceVariant))
                  : const SizedBox.shrink(),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                final n = points.length;
                // First, last, and one in the middle.
                if (i < 0 || i >= n || !(i == 0 || i == n - 1 || i == n ~/ 2)) {
                  return const SizedBox.shrink();
                }
                final d = points[i].date;
                return SideTitleWidget(
                  meta: meta,
                  fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                  child: Text('${d.day} ${_kMonthAbbrev[d.month - 1]}',
                      style: GoogleFonts.manrope(fontSize: 9, color: AppColors.onSurfaceVariant)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surfaceContainerHigh,
            getTooltipItems: (spots) => spots.map((s) {
              final d = points[s.x.toInt()].date;
              return LineTooltipItem(
                '${d.day} ${_kMonthAbbrev[d.month - 1]}\n',
                GoogleFonts.manrope(fontSize: 10, color: AppColors.onSurfaceVariant),
                children: [
                  TextSpan(
                    text: '${_fmt(s.y)} $unit',
                    style: GoogleFonts.manrope(
                        fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [for (int i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
            isCurved: true,
            preventCurveOverShooting: true,
            color: AppColors.primary,
            barWidth: 2.5,
            belowBarData: BarAreaData(show: true, color: AppColors.primary.withValues(alpha: 0.08)),
            // The best session gets a bigger, filled dot.
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, _, _) => spot.y == best
                  ? FlDotCirclePainter(
                      radius: 5, color: AppColors.primary, strokeWidth: 2, strokeColor: AppColors.surfaceContainerLow)
                  : FlDotCirclePainter(
                      radius: 2.5, color: AppColors.primary, strokeWidth: 0, strokeColor: Colors.transparent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExercisePicker(String exercise) {
    final data = findExerciseByName(exercise);
    return Pressable(
      onTap: _showExerciseSheet,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            ExerciseThumb(asset: data?.thumbnailAsset, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Text(exercise,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
            ),
            const Icon(Icons.unfold_more_rounded, color: AppColors.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _showExerciseSheet() async {
    final names = loggedExercises(_exerciseLogs);
    final sessions = {
      for (final name in names) name: progression(_logs, _exerciseLogs, name).length,
    };

    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
              child: Text('YOUR EXERCISES · MOST LOGGED FIRST', style: _label(fontSize: 11)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: names.length,
                itemBuilder: (_, i) {
                  final name = names[i];
                  final selected = name == _exercise;
                  return Pressable(
                    onTap: () => Navigator.pop(ctx, name),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.surfaceContainerHigh : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          ExerciseThumb(asset: findExerciseByName(name)?.thumbnailAsset, size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    style: GoogleFonts.spaceGrotesk(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: selected ? AppColors.primary : AppColors.onSurface)),
                                Text('${sessions[name]} session${sessions[name] == 1 ? '' : 's'}',
                                    style: GoogleFonts.manrope(fontSize: 11, color: AppColors.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          if (selected) const Icon(Icons.check_rounded, color: AppColors.primary, size: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _exercise = picked);
  }

  // ── Shared bits ─────────────────────────────────────────────────────

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }

  Widget _chip(String label, {required bool selected, required VoidCallback onTap, bool compact = false}) {
    return Padding(
      padding: EdgeInsets.only(right: compact ? 0 : 6, left: compact ? 4 : 0),
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: _label(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  color: selected ? AppColors.onPrimary : AppColors.onSurfaceVariant)),
        ),
      ),
    );
  }

  Widget _buildNotice(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: GoogleFonts.manrope(fontSize: 12, height: 1.45, color: AppColors.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }

  TextStyle _label({double fontSize = 10, double letterSpacing = 1.5, Color color = AppColors.onSurfaceVariant}) =>
      GoogleFonts.manrope(fontSize: fontSize, fontWeight: FontWeight.w700, letterSpacing: letterSpacing, color: color);

  /// 95 → "1h 35m", 40 → "40m".
  static String _formatMinutes(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60, m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  /// 12400 → "12.4k", 950 → "950".
  static String _compactNumber(double v) {
    if (v >= 10000) return '${(v / 1000).toStringAsFixed(v >= 100000 ? 0 : 1)}k';
    return formatThousands(v);
  }
}
